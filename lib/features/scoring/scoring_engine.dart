import 'dart:math' as math;

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
