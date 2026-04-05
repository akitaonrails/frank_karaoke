import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/audio_preset.dart';
import '../audio/mic_capture_service.dart';
import '../audio/pitch_detector.dart';
import '../audio/voice_isolator.dart';
import 'scoring_engine.dart';

/// Karaoke scoring with voice isolation and reference-aware processing.
///
/// Pipeline:
/// 1. Mic captures raw audio (voice + possible speaker bleed)
/// 2. VoiceIsolator processes the signal:
///    - External Mic preset: minimal processing (clean signal)
///    - Room Mic preset: high-pass filter (200 Hz cutoff)
///    - Party Mode: high-pass + spectral subtraction (if reference available)
/// 3. YIN pitch detection on the cleaned signal
/// 4. Multi-dimensional scoring:
///    - Chromatic snap (40%): landing on musical notes
///    - Pitch stability (30%): holding notes steadily
///    - Presence (15%): singing vs silence
///    - Dynamics (15%): volume expression
///
/// When reference audio is available (Android with just_audio), spectral
/// subtraction removes instrumental bleed from the mic signal before
/// pitch detection. Cross-correlation aligns for Bluetooth/speaker delay.
class ScoringSession {
  final MicCaptureService _mic;
  final PitchDetector _pitchDetector;
  final VoiceIsolator _voiceIsolator;
  final double _noiseGateThreshold;

  StreamSubscription<Float64List>? _micSub;
  final _scoreController = StreamController<ScoringUpdate>.broadcast();
  bool _isActive = false;

  // Reference audio buffer (from just_audio on Android).
  // null on Linux where we don't have PCM access.
  Float64List? _currentReferenceFrame;

  // Frame counters
  int _totalFrames = 0;
  int _voicedFrames = 0;

  // Chromatic snap accumulator
  double _snapScoreSum = 0;

  // Pitch stability: rolling window of recent pitch values (in semitones)
  final List<double> _recentPitches = [];
  static const _stabilityWindowSize = 12; // ~500ms
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
        _voiceIsolator = VoiceIsolator(preset: preset),
        _noiseGateThreshold = preset.noiseGateThreshold;

  Stream<ScoringUpdate> get scoreStream => _scoreController.stream;
  bool get isActive => _isActive;

  int get currentScore {
    if (_totalFrames == 0) return 0;
    final voiced = _voicedFrames > 0 ? _voicedFrames : 1;

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

  /// Feed a reference audio frame from just_audio (Android only).
  /// Call this on every reference audio frame during playback.
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

    _totalFrames = 0;
    _voicedFrames = 0;
    _snapScoreSum = 0;
    _stabilityScoreSum = 0;
    _dynamicsScoreSum = 0;
    _recentPitches.clear();
    _recentRms.clear();
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

    // Step 1: Voice isolation — clean the mic signal.
    final samples = _voiceIsolator.process(
      rawSamples,
      referenceSamples: _currentReferenceFrame,
    );

    final rms = PitchDetector.rmsEnergy(samples);
    _totalFrames++;

    _recentRms.add(rms);
    if (_recentRms.length > _dynamicsWindowSize) _recentRms.removeAt(0);

    _processedFrames++;
    if (_processedFrames <= 3 || _processedFrames % 200 == 0) {
      debugPrint('Scoring: frame #$_processedFrames, '
          'rms=${rms.toStringAsFixed(4)}, '
          'score=$currentScore, '
          'voiced=$_voicedFrames/$_totalFrames, '
          'ref=${_currentReferenceFrame != null ? "yes" : "no"}');
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

    // Step 2: Pitch detection on the cleaned signal.
    final pitchHz = _pitchDetector.detectPitch(samples);
    if (pitchHz < 60) {
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

    // Step 3: Multi-dimensional scoring.

    // --- Chromatic snap ---
    final midi = hzToMidi(pitchHz);
    final nearestNote = midi.roundToDouble();
    final deviationCents = (midi - nearestNote).abs() * 100;
    final snapScore = (1.0 - (deviationCents / 50.0)).clamp(0.0, 1.0);
    _snapScoreSum += snapScore;

    // --- Pitch stability ---
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
    _stabilityScoreSum += stabilityScore;

    // --- Dynamics ---
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
    _dynamicsScoreSum += dynamicsScore;

    // Composite frame score
    final frameScore = snapScore * 0.40
        + stabilityScore * 0.30
        + 1.0 * 0.15
        + dynamicsScore * 0.15;

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
