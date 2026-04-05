import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/audio_preset.dart';
import '../audio/mic_capture_service.dart';
import '../audio/pitch_detector.dart';
import '../audio/voice_isolator.dart';
import 'scoring_engine.dart';

/// Karaoke scoring with voice isolation and rolling-window responsiveness.
///
/// The score reflects the singer's CURRENT performance (last ~15 seconds),
/// not a stale average of the entire song. Good singing immediately raises
/// the score; bad singing immediately drops it.
///
/// Scoring dimensions (Nakano 2006 / Tsai & Lee 2012):
/// - Chromatic snap (50%): landing on musical notes cleanly
/// - Pitch stability (35%): holding notes, not jumping erratically
/// - Dynamics (15%): expressive volume variation
///
/// Presence is no longer a scored dimension — silence is simply skipped.
class ScoringSession {
  final MicCaptureService _mic;
  final PitchDetector _pitchDetector;
  final VoiceIsolator _voiceIsolator;
  final double _noiseGateThreshold;

  StreamSubscription<Float64List>? _micSub;
  final _scoreController = StreamController<ScoringUpdate>.broadcast();
  bool _isActive = false;

  // Reference audio (from just_audio on Android, null on Linux)
  Float64List? _currentReferenceFrame;

  // Rolling window of recent frame scores (~15 seconds at ~25fps mic rate)
  final List<double> _recentScores = [];
  static const _scoreWindowSize = 375;

  // Pitch stability: rolling window of recent MIDI values
  final List<double> _recentPitches = [];
  static const _stabilityWindowSize = 12;

  // Dynamics: rolling RMS values
  final List<double> _recentRms = [];
  static const _dynamicsWindowSize = 50;

  // Track total voiced frames for the final end-of-song score
  int _totalVoicedFrames = 0;
  double _allTimeScoreSum = 0;

  ScoringSession({
    required MicCaptureService mic,
    required AudioPreset preset,
  })  : _mic = mic,
        _pitchDetector = PitchDetector(),
        _voiceIsolator = VoiceIsolator(preset: preset),
        _noiseGateThreshold = preset.noiseGateThreshold;

  Stream<ScoringUpdate> get scoreStream => _scoreController.stream;
  bool get isActive => _isActive;

  /// Current score based on rolling window (responsive to recent singing).
  int get currentScore {
    if (_recentScores.isEmpty) return 0;
    final avg = _recentScores.reduce((a, b) => a + b) / _recentScores.length;
    return (avg * 100).round().clamp(0, 100);
  }

  /// Final score for end-of-song (average of entire performance).
  int get finalScore {
    if (_totalVoicedFrames == 0) return 0;
    return (_allTimeScoreSum / _totalVoicedFrames * 100).round().clamp(0, 100);
  }

  int get frameCount => _totalVoicedFrames;

  void feedReferenceFrame(Float64List samples) {
    _currentReferenceFrame = samples;
    _voiceIsolator.feedReference(samples);
  }

  Future<bool> start() async {
    if (_isActive) return true;

    final started = await _mic.start();
    if (!started) {
      debugPrint('ScoringSession: mic failed to start');
      return false;
    }

    _recentScores.clear();
    _recentPitches.clear();
    _recentRms.clear();
    _totalVoicedFrames = 0;
    _allTimeScoreSum = 0;
    _currentReferenceFrame = null;
    _voiceIsolator.reset();
    _isActive = true;

    _micSub = _mic.pcmStream.listen(_onMicFrame);
    debugPrint('ScoringSession: started');
    return true;
  }

  int _processedFrames = 0;

  void _onMicFrame(Float64List rawSamples) {
    if (!_isActive) return;

    // Voice isolation
    final samples = _voiceIsolator.process(
      rawSamples,
      referenceSamples: _currentReferenceFrame,
    );

    final rms = PitchDetector.rmsEnergy(samples);

    _recentRms.add(rms);
    if (_recentRms.length > _dynamicsWindowSize) _recentRms.removeAt(0);

    _processedFrames++;
    if (_processedFrames <= 3 || _processedFrames % 200 == 0) {
      debugPrint('Scoring: frame #$_processedFrames, '
          'rms=${rms.toStringAsFixed(4)}, '
          'score=$currentScore, '
          'window=${_recentScores.length}');
    }

    // Noise gate: skip silently, don't dilute scores
    if (rms < _noiseGateThreshold) {
      _scoreController.add(ScoringUpdate(
        singerPitchHz: 0,
        noteName: '--',
        chromaticSnapScore: 0,
        stabilityScore: 0,
        frameScore: 0,
        totalScore: currentScore,
        rmsEnergy: rms,
      ));
      return;
    }

    // Pitch detection on cleaned signal
    final pitchHz = _pitchDetector.detectPitch(samples);
    if (pitchHz < 60) {
      // Unpitched sound — skip, don't dilute the score window.
      _scoreController.add(ScoringUpdate(
        singerPitchHz: 0,
        noteName: '--',
        chromaticSnapScore: 0,
        stabilityScore: 0,
        frameScore: 0,
        totalScore: currentScore,
        rmsEnergy: rms,
      ));
      return;
    }

    // --- Chromatic snap (50%) ---
    // How close to the nearest musical note? 100-cent tolerance (1 semitone)
    // is generous enough for party karaoke with room mic noise.
    final midi = hzToMidi(pitchHz);
    final nearestNote = midi.roundToDouble();
    final deviationCents = (midi - nearestNote).abs() * 100;
    final snapScore = (1.0 - (deviationCents / 100.0)).clamp(0.0, 1.0);

    // --- Pitch stability (35%) ---
    _recentPitches.add(midi);
    if (_recentPitches.length > _stabilityWindowSize) _recentPitches.removeAt(0);
    double stabilityScore = 0.5;
    if (_recentPitches.length >= 3) {
      final mean = _recentPitches.reduce((a, b) => a + b) / _recentPitches.length;
      final variance = _recentPitches
          .map((p) => (p - mean) * (p - mean))
          .reduce((a, b) => a + b) / _recentPitches.length;
      final stddev = math.sqrt(variance);
      stabilityScore = (1.0 - (stddev / 2.0)).clamp(0.0, 1.0);
    }

    // --- Dynamics (15%) ---
    double dynamicsScore = 0.5;
    if (_recentRms.length >= 10) {
      final meanRms = _recentRms.reduce((a, b) => a + b) / _recentRms.length;
      final rmsVariance = _recentRms
          .map((r) => (r - meanRms) * (r - meanRms))
          .reduce((a, b) => a + b) / _recentRms.length;
      final rmsStddev = math.sqrt(rmsVariance);
      if (rmsStddev < 0.005) {
        dynamicsScore = 0.3;
      } else if (rmsStddev > 0.2) {
        dynamicsScore = 0.4;
      } else {
        dynamicsScore = (0.5 + rmsStddev * 5).clamp(0.5, 1.0);
      }
    }

    // Composite
    final frameScore = snapScore * 0.50
        + stabilityScore * 0.35
        + dynamicsScore * 0.15;

    _pushScore(frameScore);

    // Note name
    final noteIndex = nearestNote.round() % 12;
    final octave = (nearestNote.round() ~/ 12) - 1;
    const names = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
    final noteName = '${names[noteIndex]}$octave';

    _scoreController.add(ScoringUpdate(
      singerPitchHz: pitchHz,
      noteName: noteName,
      chromaticSnapScore: snapScore,
      stabilityScore: stabilityScore,
      frameScore: frameScore,
      totalScore: currentScore,
      rmsEnergy: rms,
    ));
  }

  void _pushScore(double score) {
    _recentScores.add(score);
    if (_recentScores.length > _scoreWindowSize) _recentScores.removeAt(0);
    _totalVoicedFrames++;
    _allTimeScoreSum += score;
  }

  Future<void> stop() async {
    _isActive = false;
    await _micSub?.cancel();
    _micSub = null;
    await _mic.stop();
    debugPrint('ScoringSession: stopped, final score: $finalScore');
  }

  Future<void> dispose() async {
    await stop();
    await _scoreController.close();
  }
}

class ScoringUpdate {
  final double singerPitchHz;
  final String noteName;
  final double chromaticSnapScore;
  final double stabilityScore;
  final double frameScore;
  final int totalScore;
  final double rmsEnergy;

  const ScoringUpdate({
    required this.singerPitchHz,
    required this.noteName,
    required this.chromaticSnapScore,
    required this.stabilityScore,
    required this.frameScore,
    required this.totalScore,
    required this.rmsEnergy,
  });
}
