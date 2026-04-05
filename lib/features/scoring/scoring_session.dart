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

  // Exponential moving average for the live score.
  // Alpha controls reactivity: higher = faster response, lower = more memory.
  // 0.05 means each frame contributes ~5%, so it takes ~20 frames (~1 second)
  // for a change to be fully reflected, but old history fades gradually.
  double _emaScore = 0;
  bool _emaInitialized = false;
  static const _emaAlpha = 0.05;

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

  /// Live score — exponential moving average that reacts quickly to
  /// current singing but still carries accumulated history.
  int get currentScore {
    if (!_emaInitialized) return 0;
    return (_emaScore * 100).round().clamp(0, 100);
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

    _emaScore = 0;
    _emaInitialized = false;
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

    // --- Chromatic snap (60%) ---
    // How close to the nearest musical note?
    // Use a generous curve: anything within 30 cents scores 90%+.
    // Only truly off-pitch singing (40+ cents) drops significantly.
    final midi = hzToMidi(pitchHz);
    final nearestNote = midi.roundToDouble();
    final deviationCents = (midi - nearestNote).abs() * 100;
    // Quadratic falloff: gentle near center, steep at edges
    final normalizedDev = (deviationCents / 50.0).clamp(0.0, 1.0);
    final snapScore = 1.0 - (normalizedDev * normalizedDev);

    // --- Pitch stability (30%) ---
    // How steady is the pitch? Low variance = holding a note = good.
    _recentPitches.add(midi);
    if (_recentPitches.length > _stabilityWindowSize) _recentPitches.removeAt(0);
    double stabilityScore = 0.7; // generous default before enough data
    if (_recentPitches.length >= 3) {
      final mean = _recentPitches.reduce((a, b) => a + b) / _recentPitches.length;
      final variance = _recentPitches
          .map((p) => (p - mean) * (p - mean))
          .reduce((a, b) => a + b) / _recentPitches.length;
      final stddev = math.sqrt(variance);
      // Generous: stddev < 1 semitone = good. Only > 3 semitones = bad.
      stabilityScore = (1.0 - (stddev / 3.0)).clamp(0.0, 1.0);
    }

    // --- Dynamics (10%) ---
    // Mostly a bonus — doesn't drag the score down much.
    double dynamicsScore = 0.7; // generous default
    if (_recentRms.length >= 10) {
      final meanRms = _recentRms.reduce((a, b) => a + b) / _recentRms.length;
      final rmsVariance = _recentRms
          .map((r) => (r - meanRms) * (r - meanRms))
          .reduce((a, b) => a + b) / _recentRms.length;
      final rmsStddev = math.sqrt(rmsVariance);
      // Any reasonable variation scores well
      dynamicsScore = rmsStddev > 0.003 ? 0.8 : 0.5;
    }

    // Composite — designed so decent singing scores 70-85%,
    // good singing 85-95%, only terrible singing drops below 50%.
    final frameScore = snapScore * 0.60
        + stabilityScore * 0.30
        + dynamicsScore * 0.10;

    _pushScore(frameScore);

    if (_processedFrames <= 5 || _processedFrames % 100 == 0) {
      debugPrint('Scoring: #$_processedFrames '
          'snap=${snapScore.toStringAsFixed(2)} '
          'stab=${stabilityScore.toStringAsFixed(2)} '
          'dyn=${dynamicsScore.toStringAsFixed(2)} '
          'frame=${frameScore.toStringAsFixed(2)} '
          'total=$currentScore '
          'dev=${deviationCents.toStringAsFixed(0)}c');
    }

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
