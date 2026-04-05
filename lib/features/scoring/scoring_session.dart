import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/audio_preset.dart';
import '../audio/mic_capture_service.dart';
import '../audio/pitch_detector.dart';
import 'scoring_engine.dart';

/// Reference-free karaoke scoring.
///
/// Based on Nakano et al. (2006) and Tsai & Lee (2012):
/// scores singing quality without a reference melody by measuring
/// chromatic intonation, pitch stability, presence, and dynamics.
///
/// Scoring dimensions:
/// - **Chromatic snap** (40%): how cleanly the singer lands on musical
///   notes (semitone boundaries). Good singers snap; bad singers drift.
/// - **Pitch stability** (30%): low pitch variance over ~500ms windows
///   means the singer is holding notes steadily.
/// - **Presence** (15%): fraction of time actually singing vs silent.
/// - **Dynamics** (15%): natural volume variation (not flat screaming).
///
/// Octave-agnostic: singing in any octave scores equally (like SingStar).
class ScoringSession {
  final MicCaptureService _mic;
  final PitchDetector _pitchDetector;
  final double _noiseGateThreshold;

  StreamSubscription<Float64List>? _micSub;
  final _scoreController = StreamController<ScoringUpdate>.broadcast();
  bool _isActive = false;

  // Frame counters
  int _totalFrames = 0;
  int _voicedFrames = 0;

  // Chromatic snap accumulator
  double _snapScoreSum = 0;

  // Pitch stability: rolling window of recent pitch values (in semitones)
  final List<double> _recentPitches = [];
  static const _stabilityWindowSize = 12; // ~500ms at 100fps mic rate
  double _stabilityScoreSum = 0;

  // Dynamics: rolling RMS values to measure variance
  final List<double> _recentRms = [];
  static const _dynamicsWindowSize = 50; // ~2 seconds
  double _dynamicsScoreSum = 0;

  ScoringSession({
    required MicCaptureService mic,
    required AudioPreset preset,
  })  : _mic = mic,
        _pitchDetector = PitchDetector(),
        _noiseGateThreshold = preset.noiseGateThreshold;

  Stream<ScoringUpdate> get scoreStream => _scoreController.stream;
  bool get isActive => _isActive;

  int get currentScore {
    if (_totalFrames == 0) return 0;
    final voiced = _voicedFrames > 0 ? _voicedFrames : 1;

    // Weighted combination
    final snapAvg = _snapScoreSum / voiced;
    final stabilityAvg = _stabilityScoreSum / voiced;
    final presence = _voicedFrames / _totalFrames;
    final dynamicsAvg = _voicedFrames > 0 ? _dynamicsScoreSum / voiced : 0.0;

    final raw = snapAvg * 0.40
        + stabilityAvg * 0.30
        + presence * 0.15
        + dynamicsAvg * 0.15;

    return (raw * 100).round().clamp(0, 100);
  }

  int get frameCount => _totalFrames;

  Future<bool> start() async {
    if (_isActive) return true;

    final started = await _mic.start();
    if (!started) {
      debugPrint('ScoringSession: mic failed to start');
      return false;
    }

    _totalFrames = 0;
    _voicedFrames = 0;
    _snapScoreSum = 0;
    _stabilityScoreSum = 0;
    _dynamicsScoreSum = 0;
    _recentPitches.clear();
    _recentRms.clear();
    _isActive = true;

    _micSub = _mic.pcmStream.listen(_onMicFrame);
    debugPrint('ScoringSession: started');
    return true;
  }

  void _onMicFrame(Float64List samples) {
    if (!_isActive) return;

    final rms = PitchDetector.rmsEnergy(samples);
    _totalFrames++;

    // Track RMS for dynamics scoring
    _recentRms.add(rms);
    if (_recentRms.length > _dynamicsWindowSize) _recentRms.removeAt(0);

    if (_totalFrames <= 3 || _totalFrames % 200 == 0) {
      debugPrint('Scoring: frame #$_totalFrames, '
          'rms=${rms.toStringAsFixed(4)}, '
          'score=$currentScore, '
          'voiced=$_voicedFrames/$_totalFrames');
    }

    // Noise gate: quiet frames count toward presence denominator
    // but don't contribute to pitch-based scores.
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

    final pitchHz = _pitchDetector.detectPitch(samples);
    if (pitchHz < 60) {
      // Unpitched sound (noise, breath) — skip pitch scoring.
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

    _voicedFrames++;

    // --- Chromatic snap score ---
    // How close is the detected pitch to the nearest semitone?
    // Perfect = 0 cents deviation, worst = 50 cents (quarter-tone).
    final midi = hzToMidi(pitchHz);
    final nearestNote = midi.roundToDouble();
    final deviationCents = (midi - nearestNote).abs() * 100; // in cents
    final snapScore = (1.0 - (deviationCents / 50.0)).clamp(0.0, 1.0);
    _snapScoreSum += snapScore;

    // --- Pitch stability score ---
    _recentPitches.add(midi);
    if (_recentPitches.length > _stabilityWindowSize) _recentPitches.removeAt(0);
    double stabilityScore = 0.5; // default if not enough data
    if (_recentPitches.length >= 3) {
      // Standard deviation of pitch over the window.
      // Low stddev = stable note holding. Target < 0.5 semitones.
      final mean = _recentPitches.reduce((a, b) => a + b) / _recentPitches.length;
      final variance = _recentPitches
          .map((p) => (p - mean) * (p - mean))
          .reduce((a, b) => a + b) / _recentPitches.length;
      final stddev = math.sqrt(variance);
      // Map: stddev 0 = score 1.0, stddev 2+ = score 0.0
      stabilityScore = (1.0 - (stddev / 2.0)).clamp(0.0, 1.0);
    }
    _stabilityScoreSum += stabilityScore;

    // --- Dynamics score ---
    double dynamicsScore = 0.5;
    if (_recentRms.length >= 10) {
      final rmsValues = _recentRms;
      final meanRms = rmsValues.reduce((a, b) => a + b) / rmsValues.length;
      final rmsVariance = rmsValues
          .map((r) => (r - meanRms) * (r - meanRms))
          .reduce((a, b) => a + b) / rmsValues.length;
      final rmsStddev = math.sqrt(rmsVariance);
      // Reward moderate variation (0.01-0.1 stddev is good).
      // Flat (< 0.005) or extreme (> 0.2) scores lower.
      if (rmsStddev < 0.005) {
        dynamicsScore = 0.3; // too flat
      } else if (rmsStddev > 0.2) {
        dynamicsScore = 0.4; // too erratic
      } else {
        dynamicsScore = (0.5 + rmsStddev * 5).clamp(0.5, 1.0);
      }
    }
    _dynamicsScoreSum += dynamicsScore;

    // Frame composite
    final frameScore = snapScore * 0.40
        + stabilityScore * 0.30
        + 1.0 * 0.15 // presence = 1.0 for voiced frames
        + dynamicsScore * 0.15;

    // Note name for display
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

  Future<void> stop() async {
    _isActive = false;
    await _micSub?.cancel();
    _micSub = null;
    await _mic.stop();
    debugPrint('ScoringSession: stopped, final score: $currentScore');
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
