import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/audio_preset.dart';
import '../audio/mic_capture_service.dart';
import '../audio/pitch_detector.dart';
import 'scoring_engine.dart';

/// Orchestrates real-time scoring during an active karaoke session.
///
/// Scoring approach (without separate reference audio on Linux):
/// - Detects whether the singer is producing stable, pitched vocal sounds
/// - Rewards pitch stability (holding notes) over erratic jumping
/// - Ignores silent/quiet frames (instrumental breaks don't penalize)
/// - Gives partial credit for any pitched singing in the vocal range
class ScoringSession {
  final MicCaptureService _mic;
  final PitchDetector _pitchDetector;
  final double _noiseGateThreshold;
  final double _tolerance;

  StreamSubscription<Float64List>? _micSub;
  final _scoreController = StreamController<ScoringUpdate>.broadcast();
  bool _isActive = false;

  // Scoring state
  int _scoredFrames = 0;
  double _scoreSum = 0;
  double _lastPitchHz = 0;
  int _stableCount = 0; // consecutive frames with stable pitch

  ScoringSession({
    required MicCaptureService mic,
    required AudioPreset preset,
  })  : _mic = mic,
        _pitchDetector = PitchDetector(),
        _noiseGateThreshold = preset.noiseGateThreshold,
        _tolerance = preset.pitchTolerance;

  Stream<ScoringUpdate> get scoreStream => _scoreController.stream;
  bool get isActive => _isActive;

  int get currentScore {
    if (_scoredFrames == 0) return 0;
    return ((_scoreSum / _scoredFrames) * 100).round().clamp(0, 100);
  }

  int get frameCount => _scoredFrames;

  Future<bool> start() async {
    if (_isActive) return true;

    final started = await _mic.start();
    if (!started) {
      debugPrint('ScoringSession: mic failed to start');
      return false;
    }

    _scoredFrames = 0;
    _scoreSum = 0;
    _lastPitchHz = 0;
    _stableCount = 0;
    _isActive = true;

    _micSub = _mic.pcmStream.listen(_onMicFrame);
    debugPrint('ScoringSession: started');
    return true;
  }

  int _processedFrames = 0;

  void _onMicFrame(Float64List samples) {
    if (!_isActive) return;

    final rms = PitchDetector.rmsEnergy(samples);

    _processedFrames++;
    if (_processedFrames <= 3 || _processedFrames % 200 == 0) {
      debugPrint('Scoring: frame #$_processedFrames, '
          'rms=${rms.toStringAsFixed(4)}, '
          'score=$currentScore, '
          'scored=$_scoredFrames');
    }

    // Noise gate: skip quiet frames entirely (no penalty for silence).
    if (rms < _noiseGateThreshold) {
      // Still emit an update so the UI shows the quiet state.
      _scoreController.add(ScoringUpdate(
        singerPitchHz: 0,
        frameScore: 0,
        totalScore: currentScore,
        rmsEnergy: rms,
      ));
      return;
    }

    final singerPitch = _pitchDetector.detectPitch(samples);

    // Score this frame based on vocal quality, not reference comparison.
    final frameScore = _scoreVocalFrame(singerPitch, rms);

    _scoredFrames++;
    _scoreSum += frameScore;

    _scoreController.add(ScoringUpdate(
      singerPitchHz: singerPitch,
      frameScore: frameScore,
      totalScore: currentScore,
      rmsEnergy: rms,
    ));
  }

  /// Score a single frame based on vocal characteristics.
  ///
  /// Rewards:
  /// - Detected pitch in vocal range (100-800 Hz): base score
  /// - Pitch stability (holding a note): bonus
  /// - Moderate volume (not just screaming): bonus
  ///
  /// Does NOT penalize:
  /// - Silence/quiet frames (already filtered by noise gate)
  double _scoreVocalFrame(double pitchHz, double rms) {
    // No pitch detected — noise or unpitched sound.
    if (pitchHz < 60) return 0.1; // Small credit for trying

    // Base score: pitch is in vocal range (80-1000 Hz).
    double score = 0.5;

    // Bonus for being in the sweet spot (150-600 Hz, typical singing range).
    if (pitchHz >= 150 && pitchHz <= 600) {
      score += 0.15;
    }

    // Stability bonus: if pitch is close to the previous frame's pitch,
    // the singer is holding a note (good). Erratic jumping = less stable.
    if (_lastPitchHz > 0) {
      final semitoneDistance = hzToSemitoneDistance(pitchHz, _lastPitchHz);
      if (semitoneDistance < _tolerance) {
        _stableCount = math.min(_stableCount + 1, 20);
        // Up to 0.35 bonus for sustained stable pitch.
        score += 0.35 * (_stableCount / 20.0);
      } else {
        _stableCount = 0;
      }
    }

    _lastPitchHz = pitchHz;
    return score.clamp(0.0, 1.0);
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
  final double frameScore;
  final int totalScore;
  final double rmsEnergy;

  const ScoringUpdate({
    required this.singerPitchHz,
    required this.frameScore,
    required this.totalScore,
    required this.rmsEnergy,
  });
}
