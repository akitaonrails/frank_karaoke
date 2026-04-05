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

/// Karaoke scoring with pluggable scoring strategies.
///
/// Four modes:
/// - **Pitch Match**: octave-agnostic pitch class comparison (SingStar-style)
/// - **Contour**: correlate the shape of pitch movement over time
/// - **Intervals**: compare the jumps between consecutive notes
/// - **Streak**: combo multiplier that rewards consecutive good frames
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

  // Reference pitch
  double _currentReferencePitchHz = 0;
  bool _hasReference = false;
  StreamSubscription<ReferencePitchFrame>? _refSub;
  Float64List? _currentReferenceFrame;

  // EMA for live score
  double _emaScore = 0;
  bool _emaInitialized = false;
  static const _emaAlpha = 0.05;

  // Stability: rolling MIDI values
  final List<double> _recentPitches = [];
  static const _stabilityWindowSize = 12;

  // Dynamics: rolling RMS
  final List<double> _recentRms = [];
  static const _dynamicsWindowSize = 50;

  // Totals for final score
  int _totalVoicedFrames = 0;
  double _allTimeScoreSum = 0;

  // --- Mode-specific state ---

  // Contour mode: recent pitch directions for both singer and reference
  final List<double> _singerContour = [];
  final List<double> _refContour = [];
  static const _contourWindowSize = 20;
  double _prevSingerMidi = 0;
  double _prevRefMidi = 0;

  // Interval mode: previous pitches for interval comparison
  double _prevSingerPitch = 0;
  double _prevRefPitch = 0;

  // Streak mode
  int _streakCount = 0;

  // Silence gap tracking — reset pitch history after prolonged silence
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

    _micSub = _mic.pcmStream.listen(_onMicFrame);
    debugPrint('ScoringSession: started mode=${_mode.name} '
        'ref=${_hasReference ? "yes" : "no"}');
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

    if (rms < _noiseGateThreshold) {
      _silentFrames++;
      // After ~0.5s of silence, reset pitch history so the next sung note
      // isn't compared against the pre-pause note. This prevents contour
      // and interval modes from penalizing correct re-entries after breaks.
      if (_silentFrames > 12) {
        _prevSingerMidi = 0;
        _prevSingerPitch = 0;
        _recentPitches.clear();
        _singerContour.clear();
      }
      _scoreController.add(ScoringUpdate(
        singerPitchHz: 0,
        referencePitchHz: _currentReferencePitchHz,
        noteName: '--',
        primaryScore: 0,
        stabilityScore: 0,
        frameScore: 0,
        totalScore: currentScore,
        overallScore: finalScore,
        rmsEnergy: rms,
        streakCount: _streakCount,
      ));
      return;
    }
    _silentFrames = 0;

    // Require a strong enough signal to be actual singing, not just
    // ambient noise that passed the gate. Threshold is set by calibration
    // or defaults to 0.04. Prevents score inflation from room noise.
    final isSinging = rms > _singingThreshold;

    final pitchHz = _pitchDetector.detectPitch(samples);
    if (pitchHz < 60 || !isSinging) {
      // Unpitched noise while mic is active — this DOES break streak
      // (you're making sound but it's not singing)
      if (_mode == ScoringMode.streak) _streakCount = 0;
      _scoreController.add(ScoringUpdate(
        singerPitchHz: 0,
        referencePitchHz: _currentReferencePitchHz,
        noteName: '--',
        primaryScore: 0,
        stabilityScore: 0,
        frameScore: 0,
        totalScore: currentScore,
        overallScore: finalScore,
        rmsEnergy: rms,
        streakCount: _streakCount,
      ));
      return;
    }

    final singerMidi = hzToMidi(pitchHz);
    final refMidi = _currentReferencePitchHz > 60
        ? hzToMidi(_currentReferencePitchHz)
        : 0.0;

    // --- Primary score based on selected mode ---
    final primaryScore = _computePrimaryScore(singerMidi, refMidi, pitchHz);

    // --- Stability (30%) ---
    _recentPitches.add(singerMidi);
    if (_recentPitches.length > _stabilityWindowSize) _recentPitches.removeAt(0);
    double stabilityScore = 0.4;
    if (_recentPitches.length >= 3) {
      final mean = _recentPitches.reduce((a, b) => a + b) / _recentPitches.length;
      final variance = _recentPitches
          .map((p) => (p - mean) * (p - mean))
          .reduce((a, b) => a + b) / _recentPitches.length;
      stabilityScore = (1.0 - (math.sqrt(variance) / 3.0)).clamp(0.0, 1.0);
    }

    // --- Dynamics (10%) ---
    double dynamicsScore = 0.5;
    if (_recentRms.length >= 10) {
      final meanRms = _recentRms.reduce((a, b) => a + b) / _recentRms.length;
      final rmsVar = _recentRms
          .map((r) => (r - meanRms) * (r - meanRms))
          .reduce((a, b) => a + b) / _recentRms.length;
      dynamicsScore = math.sqrt(rmsVar) > 0.003 ? 0.8 : 0.5;
    }

    // --- Composite ---
    var frameScore = primaryScore * 0.60
        + stabilityScore * 0.30
        + dynamicsScore * 0.10;

    // Streak mode: combo system
    if (_mode == ScoringMode.streak) {
      if (primaryScore >= 0.5) {
        // Good frame: build streak
        _streakCount++;
        // Bonus ramps with streak: 0 at start, up to +0.4 at 30+ streak
        final streakBonus = math.min(_streakCount, 30) / 75.0;
        frameScore = (frameScore + streakBonus).clamp(0.0, 1.0);
      } else {
        // Bad frame: break streak and punish hard
        if (_streakCount > 5) {
          // Lost a good streak — push a penalty into the EMA
          frameScore = 0.05;
        }
        _streakCount = 0;
      }
    }

    _pushScore(frameScore);

    // Update mode-specific state for next frame
    _prevSingerPitch = pitchHz;
    _prevSingerMidi = singerMidi;
    if (_currentReferencePitchHz > 60) {
      _prevRefPitch = _currentReferencePitchHz;
      _prevRefMidi = refMidi;
    }

    if (_processedFrames <= 5 || _processedFrames % 100 == 0) {
      debugPrint('Scoring[${_mode.name}]: #$_processedFrames '
          'primary=${primaryScore.toStringAsFixed(2)} '
          'frame=${frameScore.toStringAsFixed(2)} '
          'live=$currentScore overall=$finalScore '
          'streak=$_streakCount '
          'ref=${_currentReferencePitchHz.toStringAsFixed(0)}Hz '
          'singer=${pitchHz.toStringAsFixed(0)}Hz');
    }

    // Note name
    final nearestNote = singerMidi.roundToDouble();
    final noteIndex = nearestNote.round() % 12;
    final octave = (nearestNote.round() ~/ 12) - 1;
    const names = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
    final noteName = '${names[noteIndex]}$octave';

    _scoreController.add(ScoringUpdate(
      singerPitchHz: pitchHz,
      referencePitchHz: _currentReferencePitchHz,
      noteName: noteName,
      primaryScore: primaryScore,
      stabilityScore: stabilityScore,
      frameScore: frameScore,
      totalScore: currentScore,
      overallScore: finalScore,
      rmsEnergy: rms,
      streakCount: _streakCount,
    ));
  }

  /// Compute the primary score based on the selected scoring mode.
  double _computePrimaryScore(double singerMidi, double refMidi, double pitchHz) {
    switch (_mode) {
      case ScoringMode.pitchClass:
        return _scorePitchClass(singerMidi, refMidi);
      case ScoringMode.contour:
        return _scoreContour(singerMidi, refMidi);
      case ScoringMode.interval:
        return _scoreInterval(singerMidi, refMidi);
      case ScoringMode.streak:
        // Streak mode uses pitch class as the base, combo is applied later
        return _scorePitchClass(singerMidi, refMidi);
    }
  }

  /// Pitch Class: compare pitch classes (C, D, E...) ignoring octave.
  double _scorePitchClass(double singerMidi, double refMidi) {
    if (!_hasReference || refMidi <= 0) {
      // No reference: use chromatic snap (how clean is the note?)
      // plus pitch variety (are you moving around, not monotone?).
      final deviation = (singerMidi - singerMidi.roundToDouble()).abs() * 100;
      final snap = 1.0 - ((deviation / 50.0).clamp(0.0, 1.0));
      // Penalize monotone singing: if pitch hasn't changed much, reduce score.
      double variety = 0.5;
      if (_recentPitches.length >= 5) {
        final pitchRange = _recentPitches.reduce(math.max) -
            _recentPitches.reduce(math.min);
        // Singing the same note = range 0 = variety 0.3
        // Moving 4+ semitones = variety 1.0
        variety = (0.3 + pitchRange / 6.0).clamp(0.3, 1.0);
      }
      return snap * 0.6 + variety * 0.4;
    }
    final singerClass = singerMidi % 12;
    final refClass = refMidi % 12;
    var dist = (singerClass - refClass).abs();
    if (dist > 6) dist = 12 - dist;
    return (1.0 - dist / 3.0).clamp(0.0, 1.0);
  }

  /// Contour: correlate the pitch movement direction over a window.
  double _scoreContour(double singerMidi, double refMidi) {
    if (_prevSingerMidi > 0) {
      _singerContour.add(singerMidi - _prevSingerMidi);
      if (_singerContour.length > _contourWindowSize) _singerContour.removeAt(0);
    }
    if (_prevRefMidi > 0 && refMidi > 0) {
      _refContour.add(refMidi - _prevRefMidi);
      if (_refContour.length > _contourWindowSize) _refContour.removeAt(0);
    }

    // No reference: score based on melodic movement (not monotone).
    if (!_hasReference || refMidi <= 0) {
      if (_singerContour.length < 3) return 0.5;
      // Reward varied movement — count direction changes.
      int changes = 0;
      for (var i = 1; i < _singerContour.length; i++) {
        if (_singerContour[i] * _singerContour[i - 1] < 0) changes++;
      }
      // More direction changes = more melodic = higher score.
      return (0.3 + changes / (_singerContour.length * 0.6)).clamp(0.3, 1.0);
    }

    if (_singerContour.length < 3 || _refContour.length < 3) return 0.5;

    final n = math.min(_singerContour.length, _refContour.length);
    double dotProduct = 0, normA = 0, normB = 0;
    for (var i = 0; i < n; i++) {
      final a = _singerContour[_singerContour.length - n + i];
      final b = _refContour[_refContour.length - n + i];
      dotProduct += a * b;
      normA += a * a;
      normB += b * b;
    }
    // If either signal is flat (sustained note), use simple direction match
    // instead of correlation to avoid the 0.5 trap.
    if (normA < 0.001 || normB < 0.001) {
      // Both flat = both sustained = good match.
      if (normA < 0.001 && normB < 0.001) return 0.85;
      // One flat, one moving = partial match.
      return 0.4;
    }
    final correlation = dotProduct / (math.sqrt(normA) * math.sqrt(normB));
    return ((correlation + 1) / 2).clamp(0.0, 1.0);
  }

  /// Interval: compare the pitch JUMP between consecutive frames.
  double _scoreInterval(double singerMidi, double refMidi) {
    if (_prevSingerPitch <= 0) return 0.4; // first note, neutral

    final singerInterval = singerMidi - hzToMidi(_prevSingerPitch);

    if (!_hasReference || _prevRefPitch <= 0 || refMidi <= 0) {
      // No reference: reward small, musical intervals (1-5 semitones).
      // Large jumps (>7) or static (0) score lower.
      final absInterval = singerInterval.abs();
      if (absInterval < 0.5) return 0.5; // monotone
      if (absInterval <= 5) return 0.9;  // musical interval
      if (absInterval <= 7) return 0.6;  // large but possible
      return 0.3;                         // wild jump
    }

    final refInterval = refMidi - _prevRefMidi;
    final intervalDiff = (singerInterval - refInterval).abs();
    return (1.0 - intervalDiff / 4.0).clamp(0.0, 1.0);
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
