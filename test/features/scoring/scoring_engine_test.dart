import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/core/audio_preset.dart';
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
      // A4 (440) to A#4 (466.16)
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
      const freq = 523.25; // C5
      expect(midiToHz(hzToMidi(freq)), closeTo(freq, 0.01));
    });
  });

  group('scoreFrame', () {
    test('perfect match returns 1.0', () {
      expect(
        scoreFrame(referencePitchHz: 440, singerPitchHz: 440, tolerance: 2.0),
        1.0,
      );
    });

    test('half tolerance deviation returns 0.5', () {
      // 1 semitone off with 2 semitone tolerance = 0.5
      final oneSemitoneUp = 440.0 * math.pow(2, 1 / 12).toDouble();
      final score = scoreFrame(
        referencePitchHz: 440,
        singerPitchHz: oneSemitoneUp,
        tolerance: 2.0,
      );
      expect(score, closeTo(0.5, 0.01));
    });

    test('at tolerance boundary returns 0', () {
      final twoSemitonesUp = 440.0 * math.pow(2, 2 / 12).toDouble();
      final score = scoreFrame(
        referencePitchHz: 440,
        singerPitchHz: twoSemitonesUp,
        tolerance: 2.0,
      );
      expect(score, closeTo(0.0, 0.01));
    });

    test('beyond tolerance returns 0', () {
      expect(
        scoreFrame(referencePitchHz: 440, singerPitchHz: 880, tolerance: 2.0),
        0.0,
      );
    });

    test('zero reference returns 0', () {
      expect(
        scoreFrame(referencePitchHz: 0, singerPitchHz: 440, tolerance: 2.0),
        0.0,
      );
    });

    test('zero singer returns 0', () {
      expect(
        scoreFrame(referencePitchHz: 440, singerPitchHz: 0, tolerance: 2.0),
        0.0,
      );
    });

    test('generous tolerance yields higher scores', () {
      final oneSemitoneUp = 440.0 * math.pow(2, 1 / 12).toDouble();
      final strictScore = scoreFrame(
        referencePitchHz: 440,
        singerPitchHz: oneSemitoneUp,
        tolerance: 1.5,
      );
      final generousScore = scoreFrame(
        referencePitchHz: 440,
        singerPitchHz: oneSemitoneUp,
        tolerance: 3.5,
      );
      expect(generousScore, greaterThan(strictScore));
    });
  });

  group('ScoreAggregator', () {
    test('empty aggregator returns 0', () {
      final agg = ScoreAggregator(tolerance: 2.0);
      expect(agg.currentScore, 0);
      expect(agg.frameCount, 0);
    });

    test('all perfect frames returns 100', () {
      final agg = ScoreAggregator(tolerance: 2.0);
      for (var i = 0; i < 100; i++) {
        agg.addFrame(referencePitchHz: 440, singerPitchHz: 440);
      }
      expect(agg.currentScore, 100);
      expect(agg.frameCount, 100);
    });

    test('all silent frames returns 0', () {
      final agg = ScoreAggregator(tolerance: 2.0);
      for (var i = 0; i < 50; i++) {
        agg.addFrame(referencePitchHz: 440, singerPitchHz: 0);
      }
      expect(agg.currentScore, 0);
    });

    test('mixed frames returns intermediate score', () {
      final agg = ScoreAggregator(tolerance: 2.0);
      // 50 perfect frames, 50 silent frames
      for (var i = 0; i < 50; i++) {
        agg.addFrame(referencePitchHz: 440, singerPitchHz: 440);
      }
      for (var i = 0; i < 50; i++) {
        agg.addFrame(referencePitchHz: 440, singerPitchHz: 0);
      }
      expect(agg.currentScore, 50);
    });

    test('reset clears state', () {
      final agg = ScoreAggregator(tolerance: 2.0);
      agg.addFrame(referencePitchHz: 440, singerPitchHz: 440);
      expect(agg.frameCount, 1);
      agg.reset();
      expect(agg.frameCount, 0);
      expect(agg.currentScore, 0);
    });

    test('fromPreset uses preset tolerance', () {
      final agg = ScoreAggregator.fromPreset(AudioPreset.partyMode);
      // Party mode has 3.5 semitone tolerance - should be more generous
      final oneSemitoneUp = 440.0 * math.pow(2, 1 / 12).toDouble();
      agg.addFrame(referencePitchHz: 440, singerPitchHz: oneSemitoneUp);

      final strictAgg = ScoreAggregator.fromPreset(AudioPreset.externalMic);
      strictAgg.addFrame(referencePitchHz: 440, singerPitchHz: oneSemitoneUp);

      expect(agg.currentScore, greaterThan(strictAgg.currentScore));
    });

    test('score is clamped to 0-100', () {
      final agg = ScoreAggregator(tolerance: 2.0);
      agg.addFrame(referencePitchHz: 440, singerPitchHz: 440);
      expect(agg.currentScore, inInclusiveRange(0, 100));
    });
  });
}
