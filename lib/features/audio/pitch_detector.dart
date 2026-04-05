import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/constants.dart';

/// YIN pitch detection algorithm.
///
/// Detects the fundamental frequency (F0) of a monophonic audio signal.
/// Reference: "YIN, a fundamental frequency estimator for speech and music"
/// by Alain de Cheveigné and Hideki Kawahara (2002).
class PitchDetector {
  final int sampleRate;
  final double threshold;

  PitchDetector({
    this.sampleRate = kSampleRate,
    this.threshold = 0.15,
  });

  /// Detect the fundamental frequency in Hz from a PCM audio frame.
  /// Returns 0.0 if no pitch is detected (silence or noise).
  double detectPitch(Float64List samples) {
    if (samples.length < 2) return 0.0;

    final halfLen = samples.length ~/ 2;

    // Step 1: Difference function
    final diff = _differenceFunction(samples, halfLen);

    // Step 2: Cumulative mean normalized difference function (CMNDF)
    final cmndf = _cumulativeMeanNormalized(diff, halfLen);

    // Step 3: Absolute threshold
    final tauEstimate = _absoluteThreshold(cmndf, halfLen);
    if (tauEstimate == -1) return 0.0;

    // Step 4: Parabolic interpolation for sub-sample accuracy
    final betterTau = _parabolicInterpolation(cmndf, tauEstimate, halfLen);

    if (betterTau <= 0) return 0.0;
    return sampleRate / betterTau;
  }

  /// Step 1: Compute the difference function d(tau).
  Float64List _differenceFunction(Float64List samples, int halfLen) {
    final diff = Float64List(halfLen);
    for (var tau = 1; tau < halfLen; tau++) {
      double sum = 0.0;
      for (var i = 0; i < halfLen; i++) {
        final delta = samples[i] - samples[i + tau];
        sum += delta * delta;
      }
      diff[tau] = sum;
    }
    return diff;
  }

  /// Step 2: Cumulative mean normalized difference function.
  Float64List _cumulativeMeanNormalized(Float64List diff, int halfLen) {
    final cmndf = Float64List(halfLen);
    cmndf[0] = 1.0;
    double runningSum = 0.0;
    for (var tau = 1; tau < halfLen; tau++) {
      runningSum += diff[tau];
      cmndf[tau] = diff[tau] * tau / runningSum;
    }
    return cmndf;
  }

  /// Step 3: Find the first tau where CMNDF dips below threshold.
  int _absoluteThreshold(Float64List cmndf, int halfLen) {
    // Skip very low tau values (would be unrealistically high frequencies).
    final minTau = sampleRate ~/ 1000; // ~1000 Hz max
    for (var tau = minTau; tau < halfLen; tau++) {
      if (cmndf[tau] < threshold) {
        // Walk forward to find the local minimum.
        while (tau + 1 < halfLen && cmndf[tau + 1] < cmndf[tau]) {
          tau++;
        }
        return tau;
      }
    }
    return -1; // No pitch detected
  }

  /// Step 4: Parabolic interpolation for sub-sample accuracy.
  double _parabolicInterpolation(Float64List cmndf, int tau, int halfLen) {
    if (tau <= 0 || tau >= halfLen - 1) return tau.toDouble();

    final s0 = cmndf[tau - 1];
    final s1 = cmndf[tau];
    final s2 = cmndf[tau + 1];

    final denominator = 2 * s1 - s2 - s0;
    if (denominator.abs() < 1e-10) return tau.toDouble();

    return tau + (s2 - s0) / (2 * denominator);
  }

  /// Utility: compute RMS energy of a frame. Used for noise gating.
  static double rmsEnergy(Float64List samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    return math.sqrt(sum / samples.length);
  }
}
