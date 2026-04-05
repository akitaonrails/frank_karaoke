import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/features/scoring/scoring_engine.dart';

void main() {
  group('hzToSemitoneDistance', () {
    test('same frequency returns 0', () {
      expect(hzToSemitoneDistance(440, 440), 0.0);
    });

    test('one octave up is 12 semitones', () {
      expect(hzToSemitoneDistance(440, 880), closeTo(12.0, 0.01));
    });

    test('one octave down is 12 semitones', () {
      expect(hzToSemitoneDistance(880, 440), closeTo(12.0, 0.01));
    });

    test('one semitone difference', () {
      expect(hzToSemitoneDistance(440, 466.16), closeTo(1.0, 0.01));
    });

    test('zero hz returns infinity', () {
      expect(hzToSemitoneDistance(0, 440), double.infinity);
      expect(hzToSemitoneDistance(440, 0), double.infinity);
    });

    test('negative hz returns infinity', () {
      expect(hzToSemitoneDistance(-100, 440), double.infinity);
    });
  });

  group('hzToMidi', () {
    test('A4 (440 Hz) is MIDI 69', () {
      expect(hzToMidi(440), closeTo(69.0, 0.01));
    });

    test('C4 (261.63 Hz) is MIDI 60', () {
      expect(hzToMidi(261.63), closeTo(60.0, 0.01));
    });

    test('zero returns 0', () {
      expect(hzToMidi(0), 0);
    });
  });

  group('midiToHz', () {
    test('MIDI 69 is 440 Hz', () {
      expect(midiToHz(69), closeTo(440.0, 0.01));
    });

    test('MIDI 60 is ~261.63 Hz', () {
      expect(midiToHz(60), closeTo(261.63, 0.1));
    });

    test('round-trip hzToMidi -> midiToHz', () {
      const freq = 523.25;
      expect(midiToHz(hzToMidi(freq)), closeTo(freq, 0.01));
    });
  });
}
