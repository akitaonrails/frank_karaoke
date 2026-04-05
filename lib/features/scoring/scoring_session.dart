import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/audio_preset.dart';
import '../audio/mic_capture_service.dart';
import '../audio/pitch_detector.dart';
import 'scoring_engine.dart';

/// Orchestrates real-time scoring during an active karaoke session.
///
/// Listens to the mic PCM stream, runs pitch detection on each frame,
/// and updates the score aggregator. Emits score updates via a stream.
class ScoringSession {
  final MicCaptureService _mic;
  final PitchDetector _pitchDetector;
  final ScoreAggregator _aggregator;
  final double _noiseGateThreshold;

  StreamSubscription<Float64List>? _micSub;
  final _scoreController = StreamController<ScoringUpdate>.broadcast();
  bool _isActive = false;

  ScoringSession({
    required MicCaptureService mic,
    required AudioPreset preset,
  })  : _mic = mic,
        _pitchDetector = PitchDetector(),
        _aggregator = ScoreAggregator.fromPreset(preset),
        _noiseGateThreshold = preset.noiseGateThreshold;

  Stream<ScoringUpdate> get scoreStream => _scoreController.stream;
  bool get isActive => _isActive;
  int get currentScore => _aggregator.currentScore;
  int get frameCount => _aggregator.frameCount;

  /// Start scoring — begins mic capture and pitch analysis.
  Future<bool> start() async {
    if (_isActive) return true;

    final started = await _mic.start();
    if (!started) {
      debugPrint('ScoringSession: mic failed to start');
      return false;
    }

    _aggregator.reset();
    _isActive = true;

    _micSub = _mic.pcmStream.listen(_onMicFrame);
    debugPrint('ScoringSession: started');
    return true;
  }

  int _processedFrames = 0;
  int _gatedFrames = 0;

  void _onMicFrame(Float64List samples) {
    if (!_isActive) return;

    final rms = PitchDetector.rmsEnergy(samples);

    _processedFrames++;
    if (_processedFrames <= 3 || _processedFrames % 200 == 0) {
      debugPrint('Scoring: frame #$_processedFrames, '
          'rms=${rms.toStringAsFixed(4)}, '
          'gated=$_gatedFrames/$_processedFrames, '
          'samples=${samples.length}');
    }

    if (rms < _noiseGateThreshold) {
      _gatedFrames++;
      return;
    }

    final singerPitch = _pitchDetector.detectPitch(samples);

    // For now, without reference audio on Linux, we score based on
    // whether the singer is producing a pitched sound at all.
    // On Android with just_audio, we'd compare against reference pitch.
    //
    // Placeholder: any detected pitch above 80 Hz scores well.
    // This will be replaced with real reference comparison in Phase 3b.
    final referencePitch = singerPitch > 80 ? singerPitch * 1.0 : 0.0;

    _aggregator.addFrame(
      referencePitchHz: referencePitch,
      singerPitchHz: singerPitch,
    );

    final update = ScoringUpdate(
      singerPitchHz: singerPitch,
      referencePitchHz: referencePitch,
      frameScore: singerPitch > 80 ? 1.0 : 0.0,
      totalScore: _aggregator.currentScore,
      rmsEnergy: rms,
    );

    _scoreController.add(update);
  }

  /// Stop scoring and mic capture.
  Future<void> stop() async {
    _isActive = false;
    await _micSub?.cancel();
    _micSub = null;
    await _mic.stop();
    debugPrint('ScoringSession: stopped, final score: ${_aggregator.currentScore}');
  }

  Future<void> dispose() async {
    await stop();
    await _scoreController.close();
  }
}

/// A single scoring update emitted per audio frame.
class ScoringUpdate {
  final double singerPitchHz;
  final double referencePitchHz;
  final double frameScore;
  final int totalScore;
  final double rmsEnergy;

  const ScoringUpdate({
    required this.singerPitchHz,
    required this.referencePitchHz,
    required this.frameScore,
    required this.totalScore,
    required this.rmsEnergy,
  });
}
