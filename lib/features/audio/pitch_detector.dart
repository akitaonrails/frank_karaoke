import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';

/// Result of pitch detection including confidence level.
class PitchResult {
  /// Detected fundamental frequency in Hz. 0 if no pitch detected.
  final double pitchHz;

  /// Confidence level 0.0-1.0. Higher = more certain this is a real
  /// pitched sound (singing) vs noise/speech.
  /// Based on the CMNDF minimum: clear tones produce low CMNDF values.
  final double confidence;

  const PitchResult(this.pitchHz, this.confidence);

  static const none = PitchResult(0, 0);
}

/// YIN pitch detection algorithm with confidence output.
///
/// Reference: "YIN, a fundamental frequency estimator for speech and music"
/// by Alain de Cheveigné and Hideki Kawahara (2002).
class PitchDetector {
  final int sampleRate;
  final double threshold;

  int _debugCount = 0;
  Float64List? _diffBuf;
  Float64List? _cmndfBuf;

  PitchDetector({
    this.sampleRate = kSampleRate,
    this.threshold = 0.70, // Relaxed for mixed mic+speaker signals
  });

  /// Detect the fundamental frequency in Hz from a PCM audio frame.
  /// Returns 0.0 if no pitch is detected (silence or noise).
  double detectPitch(Float64List samples) {
    return detectPitchWithConfidence(samples).pitchHz;
  }

  /// Detect pitch with confidence level.
  PitchResult detectPitchWithConfidence(Float64List samples) {
    if (samples.length < 2) return PitchResult.none;

    final halfLen = samples.length ~/ 2;

    final diff = _differenceFunction(samples, halfLen);
    final cmndf = _cumulativeMeanNormalized(diff, halfLen);

    final result = _absoluteThresholdWithConfidence(cmndf, halfLen);
    if (result == null) {
      // Log the minimum CMNDF value to understand why detection fails.
      double minCmndf = 1.0;
      for (var tau = sampleRate ~/ 1000; tau < halfLen; tau++) {
        if (cmndf[tau] < minCmndf) minCmndf = cmndf[tau];
      }
      _debugCount++;
      if (_debugCount <= 5 || _debugCount % 200 == 0) {
        debugPrint('YIN: no pitch, minCMNDF=${minCmndf.toStringAsFixed(3)}, '
            'threshold=$threshold, samples=${samples.length}');
      }
      return PitchResult.none;
    }

    final tauEstimate = result.$1;
    final cmndfMin = result.$2;

    final betterTau = _parabolicInterpolation(cmndf, tauEstimate, halfLen);

    if (betterTau <= 0) return PitchResult.none;

    final pitchHz = sampleRate / betterTau;
    // Confidence: CMNDF minimum of 0.0 = perfect, 0.15 = threshold.
    // Map to 0.0-1.0: lower CMNDF = higher confidence.
    final confidence = (1.0 - cmndfMin / threshold).clamp(0.0, 1.0);

    return PitchResult(pitchHz, confidence);
  }

  Float64List _differenceFunction(Float64List samples, int halfLen) {
    if (_diffBuf == null || _diffBuf!.length != halfLen) _diffBuf = Float64List(halfLen);
    final diff = _diffBuf!;
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

  Float64List _cumulativeMeanNormalized(Float64List diff, int halfLen) {
    if (_cmndfBuf == null || _cmndfBuf!.length != halfLen) _cmndfBuf = Float64List(halfLen);
    final cmndf = _cmndfBuf!;
    cmndf[0] = 1.0;
    double runningSum = 0.0;
    for (var tau = 1; tau < halfLen; tau++) {
      runningSum += diff[tau];
      cmndf[tau] = diff[tau] * tau / runningSum;
    }
    return cmndf;
  }

  /// Returns (tau, cmndfMinValue) or null if no pitch detected.
  (int, double)? _absoluteThresholdWithConfidence(Float64List cmndf, int halfLen) {
    final minTau = sampleRate ~/ 1000;
    for (var tau = minTau; tau < halfLen; tau++) {
      if (cmndf[tau] < threshold) {
        while (tau + 1 < halfLen && cmndf[tau + 1] < cmndf[tau]) {
          tau++;
        }
        return (tau, cmndf[tau]);
      }
    }
    return null;
  }

  double _parabolicInterpolation(Float64List cmndf, int tau, int halfLen) {
    if (tau <= 0 || tau >= halfLen - 1) return tau.toDouble();

    final s0 = cmndf[tau - 1];
    final s1 = cmndf[tau];
    final s2 = cmndf[tau + 1];

    final denominator = 2 * s1 - s2 - s0;
    if (denominator.abs() < 1e-10) return tau.toDouble();

    return tau + (s2 - s0) / (2 * denominator);
  }

  /// Utility: compute RMS energy of a frame.
  static double rmsEnergy(Float64List samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    return math.sqrt(sum / samples.length);
  }
}
