import 'dart:math' as math;

import '../../core/audio_preset.dart';

/// Computes a frame-level singing score by comparing the singer's pitch
/// to the reference pitch.
///
/// Returns a value between 0.0 and 1.0, where 1.0 is a perfect match.
/// [referencePitchHz] and [singerPitchHz] are fundamental frequencies in Hz.
/// [tolerance] is the allowed deviation in semitones before score drops to 0.
double scoreFrame({
  required double referencePitchHz,
  required double singerPitchHz,
  required double tolerance,
}) {
  if (referencePitchHz <= 0 || singerPitchHz <= 0) return 0.0;

  final deviationSemitones = hzToSemitoneDistance(referencePitchHz, singerPitchHz);
  if (deviationSemitones >= tolerance) return 0.0;

  return 1.0 - (deviationSemitones / tolerance);
}

/// Converts the distance between two frequencies to semitones.
/// Always returns a non-negative value.
double hzToSemitoneDistance(double hz1, double hz2) {
  if (hz1 <= 0 || hz2 <= 0) return double.infinity;
  return (12.0 * (math.log(hz1 / hz2) / math.ln2)).abs();
}

/// Converts a frequency in Hz to a MIDI note number.
/// A4 (440 Hz) = MIDI note 69.
double hzToMidi(double hz) {
  if (hz <= 0) return 0;
  return 69.0 + 12.0 * (math.log(hz / 440.0) / math.ln2);
}

/// Converts a MIDI note number to a frequency in Hz.
double midiToHz(double midi) {
  return 440.0 * math.pow(2, (midi - 69.0) / 12.0);
}

/// Aggregates frame scores into a session score (0-100).
class ScoreAggregator {
  final double tolerance;

  ScoreAggregator({required this.tolerance});

  factory ScoreAggregator.fromPreset(AudioPreset preset) {
    return ScoreAggregator(tolerance: preset.pitchTolerance);
  }

  final List<double> _frameScores = [];

  void addFrame({
    required double referencePitchHz,
    required double singerPitchHz,
  }) {
    final score = scoreFrame(
      referencePitchHz: referencePitchHz,
      singerPitchHz: singerPitchHz,
      tolerance: tolerance,
    );
    _frameScores.add(score);
  }

  /// Returns the current aggregate score (0-100).
  int get currentScore {
    if (_frameScores.isEmpty) return 0;
    final avg = _frameScores.reduce((a, b) => a + b) / _frameScores.length;
    return (avg * 100).round().clamp(0, 100);
  }

  /// Number of frames scored so far.
  int get frameCount => _frameScores.length;

  void reset() => _frameScores.clear();
}
