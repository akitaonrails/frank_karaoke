import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/features/audio/bandpass_filter.dart';

void main() {
  late BandpassFilter filter;

  setUp(() {
    filter = BandpassFilter();
  });

  Float64List generateSine(double hz, int numSamples,
      {int sampleRate = 44100}) {
    final samples = Float64List(numSamples);
    for (var i = 0; i < numSamples; i++) {
      samples[i] = math.sin(2 * math.pi * hz * i / sampleRate);
    }
    return samples;
  }

  double rms(Float64List samples) {
    double sum = 0;
    for (final s in samples) { sum += s * s; }
    return math.sqrt(sum / samples.length);
  }

  group('BandpassFilter', () {
    test('passes voice frequencies (300-3000 Hz)', () {
      final input = generateSine(500, 4096);
      final output = filter.process(input);
      // Voice frequency should pass with minimal attenuation.
      expect(rms(output), greaterThan(rms(input) * 0.5));
    });

    test('attenuates low bass (50 Hz)', () {
      final input = generateSine(50, 4096);
      final output = filter.process(input);
      // Bass should be significantly attenuated.
      expect(rms(output), lessThan(rms(input) * 0.3));
    });

    test('attenuates high treble (8000 Hz)', () {
      final input = generateSine(8000, 4096);
      final output = filter.process(input);
      // High treble should be attenuated.
      expect(rms(output), lessThan(rms(input) * 0.5));
    });

    test('preserves output length', () {
      final input = Float64List(1000);
      expect(filter.process(input).length, 1000);
    });

    test('reset clears state', () {
      final input = generateSine(500, 100);
      filter.process(input);
      filter.reset();
      // After reset, processing again should give same result as first time.
      final out1 = BandpassFilter().process(input);
      final out2 = filter.process(input);
      expect(rms(out2), closeTo(rms(out1), 0.01));
    });
  });
}
