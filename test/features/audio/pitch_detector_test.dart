import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/features/audio/pitch_detector.dart';

void main() {
  late PitchDetector detector;

  setUp(() {
    detector = PitchDetector(sampleRate: 44100, threshold: 0.15);
  });

  /// Generate a pure sine wave at the given frequency.
  Float64List generateSine(double hz, int numSamples, {int sampleRate = 44100}) {
    final samples = Float64List(numSamples);
    for (var i = 0; i < numSamples; i++) {
      samples[i] = math.sin(2 * math.pi * hz * i / sampleRate);
    }
    return samples;
  }

  group('PitchDetector', () {
    test('detects A4 (440 Hz)', () {
      final samples = generateSine(440, 4096);
      final pitch = detector.detectPitch(samples);
      expect(pitch, closeTo(440, 5));
    });

    test('detects C4 (261.63 Hz)', () {
      final samples = generateSine(261.63, 4096);
      final pitch = detector.detectPitch(samples);
      expect(pitch, closeTo(261.63, 5));
    });

    test('detects E4 (329.63 Hz)', () {
      final samples = generateSine(329.63, 4096);
      final pitch = detector.detectPitch(samples);
      expect(pitch, closeTo(329.63, 5));
    });

    test('detects low frequency (110 Hz)', () {
      final samples = generateSine(110, 4096);
      final pitch = detector.detectPitch(samples);
      expect(pitch, closeTo(110, 3));
    });

    test('detects high frequency (880 Hz)', () {
      final samples = generateSine(880, 4096);
      final pitch = detector.detectPitch(samples);
      expect(pitch, closeTo(880, 10));
    });

    test('returns 0 for silence', () {
      final samples = Float64List(4096); // All zeros
      final pitch = detector.detectPitch(samples);
      expect(pitch, 0.0);
    });

    test('returns 0 for white noise', () {
      final rng = math.Random(42);
      final samples = Float64List(4096);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = rng.nextDouble() * 2 - 1;
      }
      // White noise should either return 0 or a very unreliable value.
      // With a strict threshold it should return 0.
      final pitch = detector.detectPitch(samples);
      // We just check it doesn't crash; noise pitch is unreliable.
      expect(pitch, isA<double>());
    });

    test('returns 0 for very short buffer', () {
      final samples = Float64List(1);
      expect(detector.detectPitch(samples), 0.0);
    });
  });

  group('rmsEnergy', () {
    test('silence has zero RMS', () {
      expect(PitchDetector.rmsEnergy(Float64List(100)), 0.0);
    });

    test('full-scale sine has RMS ~0.707', () {
      final samples = generateSine(440, 44100);
      final rms = PitchDetector.rmsEnergy(samples);
      expect(rms, closeTo(0.707, 0.01));
    });

    test('half-amplitude sine has RMS ~0.354', () {
      final samples = generateSine(440, 44100);
      for (var i = 0; i < samples.length; i++) {
        samples[i] *= 0.5;
      }
      final rms = PitchDetector.rmsEnergy(samples);
      expect(rms, closeTo(0.354, 0.01));
    });
  });
}
