import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/audio_preset.dart';
import '../../core/scoring_mode.dart';
import '../audio/mic_capture_service.dart';
import '../audio/pitch_detector.dart';
import '../audio/reference_audio_analyzer.dart';
import '../audio/voice_isolator.dart';
import 'scoring_engine.dart';

/// Karaoke scoring with pluggable strategies and pitch confidence gating.
class ScoringSession {
  final MicCaptureService _mic;
  final PitchDetector _pitchDetector;
  final VoiceIsolator _voiceIsolator;
  final double _noiseGateThreshold;
  final double _singingThreshold;
  final ScoringMode _mode;

  StreamSubscription<Float64List>? _micSub;
  final _scoreController = StreamController<ScoringUpdate>.broadcast();
  bool _isActive = false;

  // Reference pitch (Android only)
  double _currentReferencePitchHz = 0;
  bool _hasReference = false;
  StreamSubscription<ReferencePitchFrame>? _refSub;
  Float64List? _currentReferenceFrame;

  // EMA for live score — alpha=0.15 for fast response (~7 frames to reflect)
  double _emaScore = 0;
  bool _emaInitialized = false;
  static const _emaAlpha = 0.15;

  // Stability: rolling MIDI values
  final List<double> _recentPitches = [];
  static const _stabilityWindowSize = 15;

  // Dynamics: rolling RMS
  final List<double> _recentRms = [];
  static const _dynamicsWindowSize = 50;

  // Totals for final score
  int _totalVoicedFrames = 0;
  double _allTimeScoreSum = 0;

  // Contour state
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

  // Silence gap tracking
  int _silentFrames = 0;

  ScoringSession({
    required MicCaptureService mic,
    required AudioPreset preset,
    required ScoringMode mode,
    double? calibratedNoiseGate,
    double? calibratedSingingThreshold,
  })  : _mic = mic,
        _mode = mode,
        _pitchDetector = PitchDetector(),
        _voiceIsolator = VoiceIsolator(preset: preset),
        _noiseGateThreshold = calibratedNoiseGate ?? preset.noiseGateThreshold,
        _singingThreshold = calibratedSingingThreshold ?? 0.04;

  Stream<ScoringUpdate> get scoreStream => _scoreController.stream;
  bool get isActive => _isActive;
  bool get hasReference => _hasReference;
  ScoringMode get mode => _mode;

  int get currentScore {
    if (!_emaInitialized) return 0;
    return (_emaScore * 100).round().clamp(0, 100);
  }

  int get finalScore {
    if (_totalVoicedFrames == 0) return 0;
    return (_allTimeScoreSum / _totalVoicedFrames * 100).round().clamp(0, 100);
  }

  int get streakCount => _streakCount;

  void connectReferenceAnalyzer(ReferenceAudioAnalyzer analyzer) {
    _refSub?.cancel();
    _hasReference = true;
    _refSub = analyzer.pitchStream.listen((frame) {
      _currentReferencePitchHz = frame.pitchHz;
    });
  }

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
    _recentRms.clear();
    _totalVoicedFrames = 0;
    _allTimeScoreSum = 0;
    _singerContour.clear();
    _refContour.clear();
    _prevSingerMidi = 0;
    _prevRefMidi = 0;
    _prevSingerPitch = 0;
    _prevRefPitch = 0;
    _streakCount = 0;
    _silentFrames = 0;
    _currentReferenceFrame = null;
    _voiceIsolator.reset();
    _isActive = true;
    _processedFrames = 0;

    _micSub = _mic.pcmStream.listen(_onMicFrame);
    debugPrint('ScoringSession: started mode=${_mode.name}');
    return true;
  }

  int _processedFrames = 0;

  void _onMicFrame(Float64List rawSamples) {
    if (!_isActive) return;

    final samples = _voiceIsolator.process(
      rawSamples,
      referenceSamples: _currentReferenceFrame,
    );

    final rms = PitchDetector.rmsEnergy(samples);
    _recentRms.add(rms);
    if (_recentRms.length > _dynamicsWindowSize) _recentRms.removeAt(0);
    _processedFrames++;

    // --- Noise gate: skip silent frames ---
    if (rms < _noiseGateThreshold) {
      _silentFrames++;
      if (_silentFrames > 12) {
        _prevSingerMidi = 0;
        _prevSingerPitch = 0;
        _recentPitches.clear();
        _singerContour.clear();
      }
      _emitUpdate(0, 0, '--', 0, 0, 0, rms);
      return;
    }
    _silentFrames = 0;

    // --- Singing threshold: require actual vocal volume ---
    final isSinging = rms > _singingThreshold;

    // --- Pitch detection with confidence ---
    final pitchResult = _pitchDetector.detectPitchWithConfidence(samples);
    final pitchHz = pitchResult.pitchHz;
    final confidence = pitchResult.confidence;

    if (pitchHz < 60 || !isSinging || confidence < 0.3) {
      if (_mode == ScoringMode.streak) _streakCount = 0;
      _emitUpdate(0, 0, '--', 0, 0, 0, rms);
      return;
    }

    final singerMidi = hzToMidi(pitchHz);
    final refMidi = _currentReferencePitchHz > 60
        ? hzToMidi(_currentReferencePitchHz)
        : 0.0;

    // --- Update pitch history ---
    _recentPitches.add(singerMidi);
    if (_recentPitches.length > _stabilityWindowSize) _recentPitches.removeAt(0);

    // --- Compute stability ---
    double stability = 0.5;
    if (_recentPitches.length >= 3) {
      final mean = _recentPitches.reduce((a, b) => a + b) / _recentPitches.length;
      final variance = _recentPitches
          .map((p) => (p - mean) * (p - mean))
          .reduce((a, b) => a + b) / _recentPitches.length;
      final stddev = math.sqrt(variance);
      // stddev 0 = perfectly stable = 1.0
      // stddev 1 = some wobble = 0.5
      // stddev 3+ = very unstable = 0.0
      stability = (1.0 - stddev / 3.0).clamp(0.0, 1.0);
    }

    // --- Primary score ---
    final primaryScore = _computePrimaryScore(singerMidi, refMidi, pitchHz);

    // --- Frame score = primary * confidence ---
    // Confidence directly scales the output: clear singing (conf 0.9)
    // gets full credit; borderline detection (conf 0.35) gets 35%.
    var frameScore = primaryScore * confidence;

    // --- Streak combo ---
    if (_mode == ScoringMode.streak) {
      if (primaryScore >= 0.5 && confidence >= 0.5) {
        _streakCount++;
        final bonus = math.min(_streakCount, 30) / 75.0;
        frameScore = (frameScore + bonus).clamp(0.0, 1.0);
      } else {
        if (_streakCount > 5) frameScore = 0.05;
        _streakCount = 0;
      }
    }

    _pushScore(frameScore);

    // Update state for next frame
    _prevSingerPitch = pitchHz;
    _prevSingerMidi = singerMidi;
    if (_currentReferencePitchHz > 60) {
      _prevRefPitch = _currentReferencePitchHz;
      _prevRefMidi = refMidi;
    }

    // Note name
    final nearestNote = singerMidi.roundToDouble();
    final noteIndex = nearestNote.round() % 12;
    final octave = (nearestNote.round() ~/ 12) - 1;
    const names = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
    final noteName = '${names[noteIndex]}$octave';

    if (_processedFrames <= 5 || _processedFrames % 100 == 0) {
      debugPrint('Scoring[${_mode.name}]: #$_processedFrames '
          'primary=${primaryScore.toStringAsFixed(2)} '
          'conf=${confidence.toStringAsFixed(2)} '
          'stab=${stability.toStringAsFixed(2)} '
          'frame=${frameScore.toStringAsFixed(2)} '
          'live=$currentScore overall=$finalScore '
          'streak=$_streakCount '
          'singer=${pitchHz.toStringAsFixed(0)}Hz');
    }

    _emitUpdate(pitchHz, primaryScore, noteName, stability, frameScore, rms, rms);
  }

  void _emitUpdate(double pitchHz, double primary, String noteName,
      double stability, double frameScore, double rms, double rmsForUi) {
    _scoreController.add(ScoringUpdate(
      singerPitchHz: pitchHz,
      referencePitchHz: _currentReferencePitchHz,
      noteName: noteName,
      primaryScore: primary,
      stabilityScore: stability,
      frameScore: frameScore,
      totalScore: currentScore,
      overallScore: finalScore,
      rmsEnergy: rmsForUi,
      streakCount: _streakCount,
    ));
  }

  // ===== SCORING MODES =====

  double _computePrimaryScore(double singerMidi, double refMidi, double pitchHz) {
    if (_hasReference && refMidi > 0) {
      return switch (_mode) {
        ScoringMode.pitchClass || ScoringMode.streak =>
          _refPitchClass(singerMidi, refMidi),
        ScoringMode.contour => _refContourScore(singerMidi, refMidi),
        ScoringMode.interval => _refIntervalScore(singerMidi, refMidi),
      };
    }
    return switch (_mode) {
      ScoringMode.pitchClass || ScoringMode.streak =>
        _voicePitchStability(singerMidi),
      ScoringMode.contour => _voiceContourMelody(singerMidi),
      ScoringMode.interval => _voiceIntervalQuality(singerMidi),
    };
  }

  // --- With reference (Android) ---

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

  // --- Without reference (Linux) ---
  // These modes score DIFFERENTLY from each other. The key insight:
  // without reference, we score HOW you sing, not WHAT you sing.

  /// Pitch mode: rewards pitch STABILITY — holding clean, steady notes.
  /// Wobbling, drifting, or unstable pitch = low. Steady = high.
  /// This is different from the old chromatic snap which was always high.
  double _voicePitchStability(double singerMidi) {
    if (_recentPitches.length < 3) return 0.3;
    // How stable is the pitch over the last few frames?
    final mean = _recentPitches.reduce((a, b) => a + b) / _recentPitches.length;
    final variance = _recentPitches
        .map((p) => (p - mean) * (p - mean))
        .reduce((a, b) => a + b) / _recentPitches.length;
    final stddev = math.sqrt(variance);

    // Holding a note (stddev < 0.3): score 0.85-1.0
    // Slight wobble (0.3-1.0): score 0.5-0.85
    // Big wobble (1.0-2.0): score 0.2-0.5
    // Very unstable (2.0+): score 0.0-0.2
    if (stddev < 0.3) return 0.85 + (0.3 - stddev) * 0.5;
    if (stddev < 1.0) return 0.85 - (stddev - 0.3) * 0.5;
    if (stddev < 2.0) return 0.5 - (stddev - 1.0) * 0.3;
    return (0.2 - (stddev - 2.0) * 0.1).clamp(0.0, 0.2);
  }

  /// Contour mode: rewards melodic MOVEMENT with shape.
  /// Smooth ups and downs = high. Flat monotone OR jerky noise = low.
  double _voiceContourMelody(double singerMidi) {
    if (_prevSingerMidi > 0) {
      _singerContour.add(singerMidi - _prevSingerMidi);
      if (_singerContour.length > _contourWindowSize) _singerContour.removeAt(0);
    }
    if (_singerContour.length < 5) return 0.3;

    int dirChanges = 0;
    double totalMovement = 0;
    double smoothness = 0;
    for (var i = 1; i < _singerContour.length; i++) {
      if (_singerContour[i] * _singerContour[i - 1] < 0) dirChanges++;
      totalMovement += _singerContour[i].abs();
      // Smoothness: how similar are consecutive movements?
      smoothness += (_singerContour[i] - _singerContour[i - 1]).abs();
    }
    final n = _singerContour.length - 1;

    // No movement = monotone = bad
    if (totalMovement < 0.5) return 0.1;

    final changeRate = dirChanges / n;
    final avgMovement = totalMovement / n;
    final avgJerkiness = smoothness / n;

    // Smooth melody: moderate movement (1-3 semitones/frame avg),
    // moderate direction changes (0.1-0.4), low jerkiness
    double score = 0.5;

    // Movement reward (0 to +0.3)
    if (avgMovement >= 0.3 && avgMovement <= 4.0) {
      score += 0.3;
    } else if (avgMovement < 0.3) {
      score -= 0.2; // too flat
    }

    // Direction change reward (0 to +0.3)
    if (changeRate >= 0.1 && changeRate <= 0.4) {
      score += 0.3;
    } else if (changeRate < 0.1) {
      score -= 0.2; // monotone
    } else {
      score -= 0.1; // too jerky
    }

    // Smoothness penalty (jerkiness reduces score)
    if (avgJerkiness > 3.0) score -= 0.2;

    return score.clamp(0.0, 1.0);
  }

  /// Interval mode: rewards MUSICAL intervals between notes.
  /// Steps, thirds, fifths = high. Same note or wild jumps = low.
  /// Uses a smooth curve instead of hard thresholds.
  double _voiceIntervalQuality(double singerMidi) {
    if (_prevSingerPitch <= 0) return 0.3;
    final interval = (singerMidi - hzToMidi(_prevSingerPitch)).abs();

    // Smooth scoring curve peaking at 2 semitones (whole step)
    // and dropping off for larger intervals.
    // 0 = same note (0.1), 1 = half step (0.7), 2 = whole step (1.0),
    // 3-4 = third (0.85), 5 = fourth (0.65), 7 = fifth (0.45),
    // 12 = octave (0.15), >12 = wild (0.05)
    if (interval < 0.3) return 0.1; // no movement
    // Bell curve centered at 2.0 semitones
    final x = (interval - 2.0).abs();
    final score = math.exp(-x * x / 8.0); // Gaussian, sigma=2
    return score.clamp(0.05, 1.0);
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
    await _refSub?.cancel();
    _refSub = null;
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
    required this.frameScore,
    required this.totalScore,
    required this.overallScore,
    required this.rmsEnergy,
    required this.streakCount,
  });
}
