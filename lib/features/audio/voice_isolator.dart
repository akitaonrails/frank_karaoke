import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/audio_preset.dart';
import '../../core/constants.dart';

/// Processes mic audio to isolate the singer's voice from speaker bleed.
///
/// On Android with built-in mic, the mic picks up:
///   voice + instrumental (from speaker) + room reverb + speaker effects
///
/// We have the clean instrumental audio from just_audio. Using spectral
/// subtraction, we can remove (most of) the instrumental component,
/// leaving a cleaner voice signal for pitch detection.
///
/// On desktop with an external mic, this is mostly a no-op (clean signal).
class VoiceIsolator {
  final AudioPreset _preset;
  final int _sampleRate;

  // High-pass filter state (simple first-order IIR)
  double _hpPrevInput = 0;
  double _hpPrevOutput = 0;
  final double _hpAlpha;

  // Spectral subtraction: circular buffer of recent reference frames
  // for cross-correlation alignment.
  final List<Float64List> _referenceBuffer = [];
  static const _maxReferenceFrames = 50; // ~2 seconds at 100fps
  int _estimatedLagSamples = 0;
  int _lagCalibrationCount = 0;

  VoiceIsolator({
    required AudioPreset preset,
    int sampleRate = kSampleRate,
  })  : _preset = preset,
        _sampleRate = sampleRate,
        // High-pass filter coefficient for ~200 Hz cutoff.
        // alpha = RC / (RC + dt), where RC = 1/(2*pi*fc), dt = 1/sr
        _hpAlpha = _computeHpAlpha(200, sampleRate);

  static double _computeHpAlpha(double cutoffHz, int sampleRate) {
    final rc = 1.0 / (2.0 * math.pi * cutoffHz);
    final dt = 1.0 / sampleRate;
    return rc / (rc + dt);
  }

  /// Process a mic audio frame. Returns the cleaned voice signal.
  ///
  /// [micSamples] is the raw mic input (may contain voice + music).
  /// [referenceSamples] is the clean instrumental audio from just_audio
  /// (null on Linux where we don't have PCM access).
  Float64List process(Float64List micSamples, {Float64List? referenceSamples}) {
    var result = micSamples;

    // Step 1: High-pass filter (always applied for Room/Party presets).
    // Cuts low-frequency speaker bleed (bass, kick drum).
    if (_preset.useSpectralSubtraction) {
      result = _applyHighPass(result);
    }

    // Step 2: Spectral subtraction (only when reference audio is available).
    if (referenceSamples != null && _preset.useSpectralSubtraction) {
      _addReferenceFrame(referenceSamples);
      result = _spectralSubtract(result, referenceSamples);
    }

    return result;
  }

  /// Feed a reference audio frame for lag estimation without processing.
  /// Call this on every reference frame even when not processing mic audio.
  void feedReference(Float64List referenceSamples) {
    _addReferenceFrame(referenceSamples);
  }

  /// First-order high-pass IIR filter.
  /// Removes frequencies below ~200 Hz (bass, kick drum, speaker rumble).
  Float64List _applyHighPass(Float64List samples) {
    final filtered = Float64List(samples.length);
    var prevIn = _hpPrevInput;
    var prevOut = _hpPrevOutput;

    for (var i = 0; i < samples.length; i++) {
      final x = samples[i];
      final y = _hpAlpha * (prevOut + x - prevIn);
      filtered[i] = y;
      prevIn = x;
      prevOut = y;
    }

    _hpPrevInput = prevIn;
    _hpPrevOutput = prevOut;
    return filtered;
  }

  void _addReferenceFrame(Float64List frame) {
    _referenceBuffer.add(frame);
    if (_referenceBuffer.length > _maxReferenceFrames) {
      _referenceBuffer.removeAt(0);
    }
  }

  /// Spectral subtraction: remove the instrumental component from the mic.
  ///
  /// mic_signal ≈ voice + α * reference (delayed and colored by speaker/room)
  /// voice ≈ mic_signal - α * reference (after alignment)
  ///
  /// We work in the frequency domain: subtract the reference magnitude
  /// spectrum from the mic magnitude spectrum, keep the mic phase.
  Float64List _spectralSubtract(Float64List mic, Float64List reference) {
    final n = math.min(mic.length, reference.length);
    if (n < 64) return mic; // too short for meaningful FFT

    // Simple time-domain subtraction with gain estimate.
    // Full FFT-based spectral subtraction would be better but this is
    // computationally cheaper and works for our use case.
    //
    // Estimate the gain factor α: how loud is the speaker bleed in the mic?
    // Use cross-correlation energy ratio.
    final alpha = _estimateBleedGain(mic, reference, n);

    if (alpha < 0.05) return mic; // negligible bleed, don't process

    // Subtract scaled reference from mic (time-domain, lag-aligned).
    final result = Float64List(mic.length);
    for (var i = 0; i < mic.length; i++) {
      final refIdx = i + _estimatedLagSamples;
      final refSample = (refIdx >= 0 && refIdx < reference.length)
          ? reference[refIdx]
          : 0.0;
      result[i] = mic[i] - alpha * refSample;
    }

    return result;
  }

  /// Estimate how much of the reference signal is present in the mic input.
  /// Returns a gain factor α (0 = no bleed, 1 = same level, >1 = louder).
  double _estimateBleedGain(Float64List mic, Float64List ref, int n) {
    // Calibrate lag periodically using cross-correlation.
    _lagCalibrationCount++;
    if (_lagCalibrationCount % 50 == 1) {
      _estimatedLagSamples = _estimateLag(mic, ref, n);
    }

    // Compute energy ratio at the estimated lag.
    double refEnergy = 0;
    for (var i = 0; i < n; i++) {
      refEnergy += ref[i] * ref[i];
    }
    if (refEnergy < 1e-10) return 0;

    // Cross-energy at lag
    double cross = 0;
    for (var i = 0; i < n; i++) {
      final refIdx = i + _estimatedLagSamples;
      if (refIdx >= 0 && refIdx < n) {
        cross += mic[i] * ref[refIdx];
      }
    }

    // α ≈ cross / refEnergy (projection coefficient)
    final alpha = cross / refEnergy;
    return alpha.clamp(0.0, 3.0); // cap at 3x to avoid over-subtraction
  }

  /// Estimate the time lag between mic and reference using cross-correlation.
  /// Searches ±500ms for the best alignment.
  int _estimateLag(Float64List mic, Float64List ref, int n) {
    final maxLag = (_sampleRate * 0.5).round(); // ±500ms
    final searchRange = math.min(maxLag, n ~/ 2);

    double bestCorr = -1;
    int bestLag = _estimatedLagSamples; // keep previous if no better found

    // Coarse search: step by 10 samples (~0.2ms at 44100Hz)
    for (var lag = -searchRange; lag < searchRange; lag += 10) {
      double corr = 0;
      int count = 0;
      for (var i = 0; i < n; i++) {
        final refIdx = i + lag;
        if (refIdx >= 0 && refIdx < n) {
          corr += mic[i] * ref[refIdx];
          count++;
        }
      }
      if (count > 0) corr /= count;
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }

    // Fine search around best coarse result
    for (var lag = bestLag - 10; lag <= bestLag + 10; lag++) {
      double corr = 0;
      int count = 0;
      for (var i = 0; i < n; i++) {
        final refIdx = i + lag;
        if (refIdx >= 0 && refIdx < n) {
          corr += mic[i] * ref[refIdx];
          count++;
        }
      }
      if (count > 0) corr /= count;
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }

    return bestLag;
  }

  /// Reset filter state (call when starting a new song).
  void reset() {
    _hpPrevInput = 0;
    _hpPrevOutput = 0;
    _referenceBuffer.clear();
    _estimatedLagSamples = 0;
    _lagCalibrationCount = 0;
  }
}
