import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/audio_preset.dart';
import '../audio/mic_capture_service.dart';
import '../audio/pitch_detector.dart';
import '../audio/reference_audio_analyzer.dart';
import '../audio/voice_isolator.dart';
import 'scoring_engine.dart';

/// Karaoke scoring with reference pitch comparison.
///
/// Two modes:
/// - **With reference** (Linux via ffmpeg, Android via just_audio):
///   Compares singer's pitch against the instrumental's dominant pitch.
///   Octave-agnostic — singing in any octave counts.
///   Score = how close your pitch class matches the reference.
/// - **Without reference** (fallback):
///   Scores vocal quality only (chromatic snap + stability).
///
/// The live score uses EMA for responsiveness.
/// The final score averages the entire performance.
class ScoringSession {
  final MicCaptureService _mic;
  final PitchDetector _pitchDetector;
  final VoiceIsolator _voiceIsolator;
  final double _noiseGateThreshold;

  StreamSubscription<Float64List>? _micSub;
  final _scoreController = StreamController<ScoringUpdate>.broadcast();
  bool _isActive = false;

  // Reference pitch tracking.
  // On Linux: fed by ReferenceAudioAnalyzer (ffmpeg decode + YIN).
  // On Android: fed by just_audio PCM tap.
  double _currentReferencePitchHz = 0;
  bool _hasReference = false;
  StreamSubscription<ReferencePitchFrame>? _refSub;

  // Reference audio (raw PCM for voice isolation on Android)
  Float64List? _currentReferenceFrame;

  // EMA for live score
  double _emaScore = 0;
  bool _emaInitialized = false;
  static const _emaAlpha = 0.05;

  // Pitch stability
  final List<double> _recentPitches = [];
  static const _stabilityWindowSize = 12;

  // Dynamics
  final List<double> _recentRms = [];
  static const _dynamicsWindowSize = 50;

  // Totals for final score
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
  bool get hasReference => _hasReference;

  int get currentScore {
    if (!_emaInitialized) return 0;
    return (_emaScore * 100).round().clamp(0, 100);
  }

  int get finalScore {
    if (_totalVoicedFrames == 0) return 0;
    return (_allTimeScoreSum / _totalVoicedFrames * 100).round().clamp(0, 100);
  }

  int get frameCount => _totalVoicedFrames;

  /// Connect a ReferenceAudioAnalyzer (Linux: ffmpeg-based).
  void connectReferenceAnalyzer(ReferenceAudioAnalyzer analyzer) {
    _refSub?.cancel();
    _hasReference = true;
    _refSub = analyzer.pitchStream.listen((frame) {
      _currentReferencePitchHz = frame.pitchHz;
    });
    debugPrint('ScoringSession: connected reference analyzer');
  }

  /// Feed a reference audio frame directly (Android: just_audio PCM).
  void feedReferenceFrame(Float64List samples) {
    _currentReferenceFrame = samples;
    _voiceIsolator.feedReference(samples);
    // Also detect pitch from the reference for comparison.
    final refPitch = _pitchDetector.detectPitch(samples);
    if (refPitch > 60) {
      _currentReferencePitchHz = refPitch;
      _hasReference = true;
    }
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
    debugPrint('ScoringSession: started (ref=${_hasReference ? "yes" : "no"})');
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

    // Noise gate
    if (rms < _noiseGateThreshold) {
      _scoreController.add(ScoringUpdate(
        singerPitchHz: 0,
        referencePitchHz: _currentReferencePitchHz,
        noteName: '--',
        pitchMatchScore: 0,
        stabilityScore: 0,
        frameScore: 0,
        totalScore: currentScore,
        overallScore: finalScore,
        rmsEnergy: rms,
      ));
      return;
    }

    final pitchHz = _pitchDetector.detectPitch(samples);
    if (pitchHz < 60) {
      _scoreController.add(ScoringUpdate(
        singerPitchHz: 0,
        referencePitchHz: _currentReferencePitchHz,
        noteName: '--',
        pitchMatchScore: 0,
        stabilityScore: 0,
        frameScore: 0,
        totalScore: currentScore,
        overallScore: finalScore,
        rmsEnergy: rms,
      ));
      return;
    }

    final singerMidi = hzToMidi(pitchHz);
    final nearestNote = singerMidi.roundToDouble();

    // --- Pitch match score (60%) ---
    double pitchMatchScore;
    if (_hasReference && _currentReferencePitchHz > 60) {
      // Compare singer's pitch class against reference pitch class.
      // Octave-agnostic: C3 vs C5 = perfect match.
      final refMidi = hzToMidi(_currentReferencePitchHz);
      final singerPitchClass = singerMidi % 12;
      final refPitchClass = refMidi % 12;
      // Distance in semitones around the circle (0-6)
      var classDist = (singerPitchClass - refPitchClass).abs();
      if (classDist > 6) classDist = 12 - classDist;
      // Score: 0 semitones = 1.0, 3 semitones = 0.0
      pitchMatchScore = (1.0 - classDist / 3.0).clamp(0.0, 1.0);
    } else {
      // Fallback: chromatic snap (how close to ANY note)
      final deviationCents = (singerMidi - nearestNote).abs() * 100;
      final normalizedDev = (deviationCents / 50.0).clamp(0.0, 1.0);
      pitchMatchScore = 1.0 - (normalizedDev * normalizedDev);
    }

    // --- Pitch stability (30%) ---
    _recentPitches.add(singerMidi);
    if (_recentPitches.length > _stabilityWindowSize) _recentPitches.removeAt(0);
    double stabilityScore = 0.7;
    if (_recentPitches.length >= 3) {
      final mean = _recentPitches.reduce((a, b) => a + b) / _recentPitches.length;
      final variance = _recentPitches
          .map((p) => (p - mean) * (p - mean))
          .reduce((a, b) => a + b) / _recentPitches.length;
      final stddev = math.sqrt(variance);
      stabilityScore = (1.0 - (stddev / 3.0)).clamp(0.0, 1.0);
    }

    // --- Dynamics (10%) ---
    double dynamicsScore = 0.7;
    if (_recentRms.length >= 10) {
      final meanRms = _recentRms.reduce((a, b) => a + b) / _recentRms.length;
      final rmsVariance = _recentRms
          .map((r) => (r - meanRms) * (r - meanRms))
          .reduce((a, b) => a + b) / _recentRms.length;
      final rmsStddev = math.sqrt(rmsVariance);
      dynamicsScore = rmsStddev > 0.003 ? 0.8 : 0.5;
    }

    final frameScore = pitchMatchScore * 0.60
        + stabilityScore * 0.30
        + dynamicsScore * 0.10;

    _pushScore(frameScore);

    if (_processedFrames <= 5 || _processedFrames % 100 == 0) {
      debugPrint('Scoring: #$_processedFrames '
          'match=${pitchMatchScore.toStringAsFixed(2)} '
          'stab=${stabilityScore.toStringAsFixed(2)} '
          'frame=${frameScore.toStringAsFixed(2)} '
          'live=$currentScore overall=$finalScore '
          'ref=${_currentReferencePitchHz.toStringAsFixed(0)}Hz '
          'singer=${pitchHz.toStringAsFixed(0)}Hz');
    }

    // Note name
    final noteIndex = nearestNote.round() % 12;
    final octave = (nearestNote.round() ~/ 12) - 1;
    const names = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
    final noteName = '${names[noteIndex]}$octave';

    _scoreController.add(ScoringUpdate(
      singerPitchHz: pitchHz,
      referencePitchHz: _currentReferencePitchHz,
      noteName: noteName,
      pitchMatchScore: pitchMatchScore,
      stabilityScore: stabilityScore,
      frameScore: frameScore,
      totalScore: currentScore,
      overallScore: finalScore,
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
  final double pitchMatchScore;
  final double stabilityScore;
  final double frameScore;
  final int totalScore;
  final int overallScore;
  final double rmsEnergy;

  const ScoringUpdate({
    required this.singerPitchHz,
    required this.referencePitchHz,
    required this.noteName,
    required this.pitchMatchScore,
    required this.stabilityScore,
    required this.frameScore,
    required this.totalScore,
    required this.overallScore,
    required this.rmsEnergy,
  });
}
