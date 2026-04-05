import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/audio_preset.dart';
import '../../core/scoring_mode.dart';
import '../audio/bandpass_filter.dart';
import '../audio/mic_capture_service.dart';
import '../audio/pitch_oracle.dart';
import '../audio/pitch_detector.dart';
import '../audio/voice_isolator.dart';
import 'scoring_engine.dart';

/// Karaoke scoring.
///
/// WITH reference (Android): 4 modes compare singer vs music.
/// WITHOUT reference (Linux): single combined voice quality score
/// that rewards clean pitch, melodic movement, and good technique.
/// The mode selector still works but all modes use the same combined
/// algorithm — mode selection is saved for when reference is available.
class ScoringSession {
  final MicCaptureService _mic;
  final PitchDetector _pitchDetector;
  final VoiceIsolator _voiceIsolator;
  final BandpassFilter _bandpass;
  PitchOracle? _oracle;
  final double _noiseGateThreshold;
  final double _singingThreshold;
  final ScoringMode _mode;

  StreamSubscription<MicFrame>? _micSub;
  final _scoreController = StreamController<ScoringUpdate>.broadcast();
  bool _isActive = false;

  // Reference pitch (Android only)
  double _currentReferencePitchHz = 0;
  bool _hasReference = false;
  Float64List? _currentReferenceFrame;

  // EMA for live score
  double _emaScore = 0;
  bool _emaInitialized = false;
  static const _emaAlpha = 0.15;

  // Pitch history
  final List<double> _recentPitches = [];
  static const _historySize = 15;

  // Contour state (for reference mode)
  final List<double> _singerContour = [];
  final List<double> _refContour = [];
  static const _contourWindowSize = 20;
  double _prevSingerMidi = 0;
  double _prevRefMidi = 0;

  // Interval state
  double _prevSingerPitch = 0;
  double _prevRefPitch = 0;

  // Streak
  int _streakCount = 0;

  // Silence gap
  int _silentFrames = 0;

  // Playback time tracking for pitch oracle
  DateTime? _playbackStartTime;

  // Totals for final score
  int _totalVoicedFrames = 0;
  double _allTimeScoreSum = 0;

  ScoringSession({
    required MicCaptureService mic,
    required AudioPreset preset,
    required ScoringMode mode,
    PitchOracle? oracle,
    double? calibratedNoiseGate,
    double? calibratedSingingThreshold,
  })  : _mic = mic,
        _oracle = oracle,
        _mode = mode,
        _pitchDetector = PitchDetector(),
        _voiceIsolator = VoiceIsolator(preset: preset),
        _bandpass = BandpassFilter(),
        _noiseGateThreshold = calibratedNoiseGate ?? preset.noiseGateThreshold,
        _singingThreshold = calibratedSingingThreshold ?? 0.02;

  Stream<ScoringUpdate> get scoreStream => _scoreController.stream;
  bool get isActive => _isActive;
  bool get isPaused => _isPaused;
  bool get hasReference => _hasReference;
  ScoringMode get mode => _mode;
  bool _isPaused = false;
  bool _warmupDone = false;

  int get currentScore {
    if (!_emaInitialized) return 0;
    return (_emaScore * 100).round().clamp(0, 100);
  }

  int get finalScore {
    if (_totalVoicedFrames == 0) return 0;
    return (_allTimeScoreSum / _totalVoicedFrames * 100).round().clamp(0, 100);
  }

  int get streakCount => _streakCount;

  /// Connect an oracle after the session has started (background loading).
  void setOracle(PitchOracle oracle) {
    _oracle = oracle;
    debugPrint('ScoringSession: oracle connected (${oracle.entryCount} entries)');
  }

  /// Pause scoring (video paused). Mic keeps running but frames are ignored.
  void pause() {
    _isPaused = true;
  }

  /// Resume scoring (video playing again).
  void resume() {
    _isPaused = false;
  }

  /// Reset scores to zero (video seeked/restarted).
  void resetScore() {
    _emaScore = 0;
    _emaInitialized = false;
    _totalVoicedFrames = 0;
    _allTimeScoreSum = 0;
    _streakCount = 0;
    _recentPitches.clear();
    _singerContour.clear();
    _prevSingerMidi = 0;
    _prevSingerPitch = 0;
    _warmupDone = false;
    // Restart warmup timer.
    Future.delayed(const Duration(seconds: 5), () {
      _warmupDone = true;
      debugPrint('Scoring: warmup complete, scoring active');
    });
    debugPrint('Scoring: score reset, 5s warmup started');
  }

  /// Feed a reference audio frame (Android: from just_audio PCM tap).
  void feedReferenceFrame(Float64List samples) {
    _currentReferenceFrame = samples;
    _voiceIsolator.feedReference(samples);
    final refPitch = _pitchDetector.detectPitch(samples);
    if (refPitch > 60) {
      _currentReferencePitchHz = refPitch;
      _hasReference = true;
    }
  }

  Future<bool> start() async {
    if (_isActive) return true;
    final started = await _mic.start();
    if (!started) return false;

    _emaScore = 0;
    _emaInitialized = false;
    _recentPitches.clear();
    _singerContour.clear();
    _refContour.clear();
    _prevSingerMidi = 0;
    _prevRefMidi = 0;
    _prevSingerPitch = 0;
    _prevRefPitch = 0;
    _streakCount = 0;
    _silentFrames = 0;
    _totalVoicedFrames = 0;
    _allTimeScoreSum = 0;
    _currentReferenceFrame = null;
    _voiceIsolator.reset();
    _bandpass.reset();
    _isPaused = false;
    _warmupDone = false;
    _isActive = true;
    _processedFrames = 0;
    _playbackStartTime = DateTime.now();

    // 5-second warmup: ignore initial noise/clicks from playback start.
    Future.delayed(const Duration(seconds: 5), () {
      _warmupDone = true;
      debugPrint('Scoring: warmup complete');
    });

    _micSub = _mic.pcmStream.listen((frame) => _onMicFrame(frame.samples, frame.rawPeak));
    debugPrint('ScoringSession: started mode=${_mode.name} '
        'ref=${_hasReference ? "yes" : "no"}');
    return true;
  }

  int _processedFrames = 0;

  void _onMicFrame(Float64List normalizedSamples, double rawPeak) {
    if (!_isActive || _isPaused || !_warmupDone) return;

    // Processing pipeline:
    // 1. Voice isolator (spectral subtraction when reference available)
    // 2. Bandpass filter 200-3500 Hz (attenuates music bass/treble,
    //    emphasizes vocal frequency range for better pitch detection
    //    when phone mic picks up speaker audio + voice together)
    var samples = _voiceIsolator.process(
      normalizedSamples,
      referenceSamples: _currentReferenceFrame,
    );
    samples = _bandpass.process(samples);

    final rms = rawPeak;
    _processedFrames++;

    // Log every 10th frame to see the full picture without flooding
    final shouldLog = _processedFrames <= 10 || _processedFrames % 10 == 0;

    if (shouldLog) {
      debugPrint('SC #$_processedFrames pk=${rawPeak.toStringAsFixed(4)}');
    }

    // Noise gate
    if (rawPeak < _noiseGateThreshold) {
      if (shouldLog) debugPrint('  -> GATED (pk < ${_noiseGateThreshold.toStringAsFixed(4)})');

      _silentFrames++;
      if (_silentFrames > 12) {
        _prevSingerMidi = 0;
        _prevSingerPitch = 0;
        _recentPitches.clear();
        _singerContour.clear();
      }
      _emit(0, 0, '--', 0, 0, 0, rms);
      return;
    }
    _silentFrames = 0;

    // Singing threshold
    if (rawPeak < _singingThreshold) {
      if (_mode == ScoringMode.streak) _streakCount = 0;
      if (shouldLog) debugPrint('  -> LOW (pk < sing ${_singingThreshold.toStringAsFixed(4)})');
      _emit(0, 0, '--', 0, 0, 0, rms);
      return;
    }

    // Pitch detection
    final result = _pitchDetector.detectPitchWithConfidence(samples);
    if (result.pitchHz < 60 || result.confidence < 0.3) {
      if (_mode == ScoringMode.streak) _streakCount = 0;
      if (shouldLog) {
        debugPrint('  -> NOPITCH hz=${result.pitchHz.toStringAsFixed(0)} '
            'conf=${result.confidence.toStringAsFixed(2)}');
      }
      _emit(0, 0, '--', 0, result.confidence, 0, rms);
      return;
    }

    final pitchHz = result.pitchHz;
    final confidence = result.confidence;
    final singerMidi = hzToMidi(pitchHz);

    // Update pitch history
    _recentPitches.add(singerMidi);
    if (_recentPitches.length > _historySize) _recentPitches.removeAt(0);

    // Pitch oracle: determine if this is the singer or speaker bleed.
    double singerConf = 1.0; // assume singer unless oracle says otherwise
    final oracle = _oracle;
    if (oracle != null && oracle.isReady && _playbackStartTime != null) {
      final elapsed = DateTime.now().difference(_playbackStartTime!);
      singerConf = oracle.singerConfidence(pitchHz, elapsed);
      final refPitch = oracle.getPitchAt(elapsed);

      // If the oracle says this is speaker bleed, skip it.
      if (singerConf < 0.3) {
        if (shouldLog) {
          debugPrint('  -> BLEED singerConf=${singerConf.toStringAsFixed(2)} '
              'ref=${refPitch.toStringAsFixed(0)}Hz');
        }
        _emit(0, 0, '--', 0, confidence, 0, rms);
        return;
      }

      // If oracle has reference, use reference-based scoring.
      if (refPitch > 60) {
        _hasReference = true;
        _currentReferencePitchHz = refPitch;
      }
    }

    // Compute score
    final primaryScore = _hasReference
        ? _scoreWithReference(singerMidi, pitchHz)
        : _scoreVoiceOnly(singerMidi, pitchHz, confidence);

    // Scale by singer confidence: partial bleed gets partial score.
    var frameScore = primaryScore * singerConf;

    // Streak combo
    if (_mode == ScoringMode.streak) {
      if (frameScore >= 0.4) {
        _streakCount++;
        frameScore = (frameScore + math.min(_streakCount, 30) / 75.0)
            .clamp(0.0, 1.0);
      } else {
        if (_streakCount > 5) frameScore = 0.05;
        _streakCount = 0;
      }
    }

    _pushScore(frameScore);

    // Update state
    _prevSingerPitch = pitchHz;
    _prevSingerMidi = singerMidi;
    if (_currentReferencePitchHz > 60) {
      _prevRefPitch = _currentReferencePitchHz;
      _prevRefMidi = hzToMidi(_currentReferencePitchHz);
    }

    // Note name
    final nn = singerMidi.round();
    const names = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
    final noteName = '${names[nn % 12]}${nn ~/ 12 - 1}';

    if (shouldLog) {
      debugPrint('  -> HIT! ${pitchHz.toStringAsFixed(0)}Hz '
          'conf=${confidence.toStringAsFixed(2)} '
          'prim=${primaryScore.toStringAsFixed(2)} '
          'frame=${frameScore.toStringAsFixed(2)} '
          'live=$currentScore');
    }

    _emit(pitchHz, primaryScore, noteName, 0, confidence, frameScore, rms);
  }

  // =====================================================
  // VOICE-ONLY SCORING (Linux, no reference)
  // =====================================================
  // Combined score from 3 signals:
  // 1. Confidence (40%): how "sung" vs "spoken" is this sound?
  //    Clear tonal singing = high confidence. Speech/noise = low.
  // 2. Pitch cleanliness (30%): how close to a clean note center?
  //    But use confidence-weighted snap, not raw deviation.
  // 3. Musicality (30%): is the singer creating musical patterns?
  //    Measured by pitch range + interval quality over recent history.

  double _scoreVoiceOnly(double singerMidi, double pitchHz, double confidence) {
    // 1. Confidence score: directly rewards singing-like sounds.
    // conf 0.3 (gate minimum) = 0.0, conf 0.9 = 1.0
    final confScore = ((confidence - 0.3) / 0.6).clamp(0.0, 1.0);

    // 2. Pitch cleanliness: deviation from nearest note.
    // Weighted by confidence — low-confidence detections shouldn't
    // get credit for accidentally landing near a note.
    final deviation = (singerMidi - singerMidi.roundToDouble()).abs() * 100;
    final rawSnap = (1.0 - deviation / 40.0).clamp(0.0, 1.0);
    final cleanScore = rawSnap * confScore; // only counts if confident

    // 3. Musicality: pitch variety + interval quality
    double musicalScore = 0.3; // default
    if (_recentPitches.length >= 5) {
      final maxP = _recentPitches.reduce(math.max);
      final minP = _recentPitches.reduce(math.min);
      final range = maxP - minP;

      // Range: 0 = monotone (0.0), 2-5 semitones = sweet spot (1.0)
      double rangeScore;
      if (range < 0.5) {
        rangeScore = 0.0;
      } else if (range <= 6.0) {
        rangeScore = (range / 6.0).clamp(0.0, 1.0);
      } else {
        rangeScore = math.max(0.3, 1.0 - (range - 6.0) / 10.0);
      }

      // Interval quality: current jump
      double intervalScore = 0.5;
      if (_prevSingerPitch > 0) {
        final interval = (singerMidi - hzToMidi(_prevSingerPitch)).abs();
        if (interval < 0.3) {
          intervalScore = 0.6; // holding a note
        } else if (interval <= 5.0) {
          intervalScore = 1.0; // musical step/third
        } else if (interval <= 8.0) {
          intervalScore = 0.4; // wide jump
        } else {
          intervalScore = 0.1; // wild
        }
      }

      musicalScore = rangeScore * 0.5 + intervalScore * 0.5;
    }

    final combined = confScore * 0.40 + cleanScore * 0.30 + musicalScore * 0.30;
    return combined.clamp(0.0, 1.0);
  }

  // =====================================================
  // WITH-REFERENCE SCORING (Android)
  // =====================================================

  double _scoreWithReference(double singerMidi, double pitchHz) {
    final refMidi = hzToMidi(_currentReferencePitchHz);
    return switch (_mode) {
      ScoringMode.pitchClass || ScoringMode.streak =>
        _refPitchClass(singerMidi, refMidi),
      ScoringMode.contour => _refContourScore(singerMidi, refMidi),
      ScoringMode.interval => _refIntervalScore(singerMidi, refMidi),
    };
  }

  double _refPitchClass(double singerMidi, double refMidi) {
    final singerClass = singerMidi % 12;
    final refClass = refMidi % 12;
    var dist = (singerClass - refClass).abs();
    if (dist > 6) dist = 12 - dist;
    return (1.0 - dist / 3.0).clamp(0.0, 1.0);
  }

  double _refContourScore(double singerMidi, double refMidi) {
    if (_prevSingerMidi > 0) {
      _singerContour.add(singerMidi - _prevSingerMidi);
      if (_singerContour.length > _contourWindowSize) _singerContour.removeAt(0);
    }
    if (_prevRefMidi > 0) {
      _refContour.add(refMidi - _prevRefMidi);
      if (_refContour.length > _contourWindowSize) _refContour.removeAt(0);
    }
    if (_singerContour.length < 3 || _refContour.length < 3) return 0.3;
    final n = math.min(_singerContour.length, _refContour.length);
    double dot = 0, nA = 0, nB = 0;
    for (var i = 0; i < n; i++) {
      final a = _singerContour[_singerContour.length - n + i];
      final b = _refContour[_refContour.length - n + i];
      dot += a * b; nA += a * a; nB += b * b;
    }
    if (nA < 0.001 && nB < 0.001) return 0.8;
    if (nA < 0.001 || nB < 0.001) return 0.3;
    return ((dot / (math.sqrt(nA) * math.sqrt(nB)) + 1) / 2).clamp(0.0, 1.0);
  }

  double _refIntervalScore(double singerMidi, double refMidi) {
    if (_prevSingerPitch <= 0 || _prevRefPitch <= 0) return 0.3;
    final singerInt = singerMidi - hzToMidi(_prevSingerPitch);
    final refInt = refMidi - _prevRefMidi;
    return (1.0 - (singerInt - refInt).abs() / 4.0).clamp(0.0, 1.0);
  }

  // =====================================================

  void _emit(double pitchHz, double primary, String noteName,
      double stability, double confidence, double frameScore, double rms) {
    _scoreController.add(ScoringUpdate(
      singerPitchHz: pitchHz,
      referencePitchHz: _currentReferencePitchHz,
      noteName: noteName,
      primaryScore: primary,
      stabilityScore: stability,
      confidence: confidence,
      frameScore: frameScore,
      totalScore: currentScore,
      overallScore: finalScore,
      rmsEnergy: rms,
      streakCount: _streakCount,
    ));
  }

  void _pushScore(double score) {
    if (!_emaInitialized) {
      _emaScore = score;
      _emaInitialized = true;
    } else {
      _emaScore = _emaAlpha * score + (1 - _emaAlpha) * _emaScore;
    }
    _totalVoicedFrames++;
    _allTimeScoreSum += score;
  }

  Future<void> stop() async {
    _isActive = false;
    await _micSub?.cancel();
    _micSub = null;
    await _mic.stop();
    debugPrint('ScoringSession: stopped, final=$finalScore');
  }

  Future<void> dispose() async {
    await stop();
    await _scoreController.close();
  }
}

class ScoringUpdate {
  final double singerPitchHz;
  final double referencePitchHz;
  final String noteName;
  final double primaryScore;
  final double stabilityScore;
  final double confidence;
  final double frameScore;
  final int totalScore;
  final int overallScore;
  final double rmsEnergy;
  final int streakCount;

  const ScoringUpdate({
    required this.singerPitchHz,
    required this.referencePitchHz,
    required this.noteName,
    required this.primaryScore,
    required this.stabilityScore,
    required this.confidence,
    required this.frameScore,
    required this.totalScore,
    required this.overallScore,
    required this.rmsEnergy,
    required this.streakCount,
  });
}
