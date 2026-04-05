import 'dart:math' as math;
import 'dart:typed_data';

/// Simple IIR bandpass filter for isolating voice from mixed audio.
///
/// Voice fundamentals: 85-300 Hz, harmonics: 300-3000 Hz.
/// Music energy spreads across 20-20000 Hz.
/// By bandpass filtering 200-3500 Hz, we attenuate bass (kick drum,
/// bass guitar) and high treble (cymbals, hi-hats) that dominate
/// in music, improving the voice-to-music ratio for pitch detection.
///
/// Uses cascaded second-order sections (biquads) for stability.
class BandpassFilter {
  late final _Biquad _highPass; // removes below lowCutoff
  late final _Biquad _lowPass;  // removes above highCutoff

  BandpassFilter({
    double sampleRate = 44100,
    double lowCutoff = 200,
    double highCutoff = 3500,
  }) {
    _highPass = _Biquad.highPass(lowCutoff, sampleRate);
    _lowPass = _Biquad.lowPass(highCutoff, sampleRate);
  }

  Float64List? _outputBuffer;

  /// Filter a frame of samples and return the filtered result.
  /// Reuses an internal buffer to avoid per-frame allocations.
  Float64List process(Float64List samples) {
    if (_outputBuffer == null || _outputBuffer!.length != samples.length) {
      _outputBuffer = Float64List(samples.length);
    }
    final result = _outputBuffer!;
    for (var i = 0; i < samples.length; i++) {
      var s = samples[i];
      s = _highPass.process(s);
      s = _lowPass.process(s);
      result[i] = s;
    }
    return result;
  }

  void reset() {
    _highPass.reset();
    _lowPass.reset();
  }
}

/// Second-order IIR filter (biquad).
class _Biquad {
  final double b0, b1, b2, a1, a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  /// Butterworth high-pass filter.
  factory _Biquad.highPass(double cutoff, double sampleRate) {
    final w0 = 2 * math.pi * cutoff / sampleRate;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * 0.707); // Q = 0.707 (Butterworth)

    final a0 = 1 + alpha;
    return _Biquad(
      (1 + cosW0) / 2 / a0,
      -(1 + cosW0) / a0,
      (1 + cosW0) / 2 / a0,
      -2 * cosW0 / a0,
      (1 - alpha) / a0,
    );
  }

  /// Butterworth low-pass filter.
  factory _Biquad.lowPass(double cutoff, double sampleRate) {
    final w0 = 2 * math.pi * cutoff / sampleRate;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * 0.707);

    final a0 = 1 + alpha;
    return _Biquad(
      (1 - cosW0) / 2 / a0,
      (1 - cosW0) / a0,
      (1 - cosW0) / 2 / a0,
      -2 * cosW0 / a0,
      (1 - alpha) / a0,
    );
  }

  double process(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }
}
