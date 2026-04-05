import 'dart:math' as math;

import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import 'pitch_detector.dart';

/// Pitch oracle: knows what pitch the music is playing at any moment.
///
/// Downloads the reference audio, decodes to PCM via Android MediaCodec,
/// runs YIN pitch detection, and builds a timeline of pitches.
///
/// Used by the scoring system to distinguish singer from speaker bleed:
/// - mic pitch ≠ reference pitch → singer is singing → score it
/// - mic pitch ≈ reference pitch → speaker bleed → ignore
class PitchOracle {
  final List<_PitchEntry> _timeline = [];
  bool _isReady = false;
  bool _isLoading = false;
  String? _videoId;

  bool get isReady => _isReady;
  bool get isLoading => _isLoading;
  int get entryCount => _timeline.length;

  /// Build the pitch timeline for a video.
  Future<bool> buildForVideo(String videoId, String audioUrl) async {
    if (_videoId == videoId && _isReady) return true;
    if (_isLoading) return false;

    _isLoading = true;
    _timeline.clear();
    _isReady = false;
    _videoId = videoId;

    try {
      debugPrint('PitchOracle: downloading audio...');

      // Download audio bytes.
      final response = await http.get(
        Uri.parse(audioUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) '
              'AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('PitchOracle: download failed (${response.statusCode})');
        _isLoading = false;
        return false;
      }

      debugPrint('PitchOracle: downloaded ${response.bodyBytes.length} bytes, decoding...');

      // Decode to raw 16-bit mono PCM using audio_decoder (MediaCodec).
      final pcmBytes = await AudioDecoder.convertToWavBytes(
        response.bodyBytes,
        formatHint: 'm4a',
        sampleRate: kSampleRate,
        channels: 1,
        bitDepth: 16,
        includeHeader: false, // raw PCM, no WAV header
      );

      debugPrint('PitchOracle: decoded ${pcmBytes.length} bytes of PCM');

      // Convert 16-bit signed PCM to Float64.
      final numSamples = pcmBytes.length ~/ 2;
      final samples = Float64List(numSamples);
      final byteData = ByteData.sublistView(pcmBytes);
      for (var i = 0; i < numSamples; i++) {
        samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      }

      // Build pitch timeline.
      _buildTimeline(samples, kSampleRate);

      _isReady = true;
      _isLoading = false;
      debugPrint('PitchOracle: ready, ${_timeline.length} entries, '
          '${(numSamples / kSampleRate).toStringAsFixed(1)}s of audio');
      return true;
    } catch (e) {
      debugPrint('PitchOracle: failed: $e');
      _isLoading = false;
      return false;
    }
  }

  /// Get the reference pitch at a given playback timestamp.
  double getPitchAt(Duration timestamp) {
    if (!_isReady || _timeline.isEmpty) return 0;

    final ms = timestamp.inMilliseconds;
    var lo = 0, hi = _timeline.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_timeline[mid].timestampMs < ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0 && (ms - _timeline[lo - 1].timestampMs).abs() <
        (_timeline[lo].timestampMs - ms).abs()) {
      lo--;
    }
    return _timeline[lo].pitchHz;
  }

  /// How confident are we that the mic pitch is the SINGER, not speaker bleed?
  /// Returns 0.0 (speaker bleed) to 1.0 (definitely singer).
  double singerConfidence(double micPitchHz, Duration timestamp) {
    if (!_isReady) return 0.5;

    final refPitch = getPitchAt(timestamp);
    if (refPitch <= 0) return 1.0; // silence in music = definitely singer

    // Octave-agnostic pitch class distance.
    final micMidi = 69 + 12 * _log2(micPitchHz / 440);
    final refMidi = 69 + 12 * _log2(refPitch / 440);
    final micClass = micMidi % 12;
    final refClass = refMidi % 12;
    var dist = (micClass - refClass).abs();
    if (dist > 6) dist = 12 - dist;

    // dist 0 = same note = speaker bleed
    // dist 2+ = different note = singer
    return (dist / 2.0).clamp(0.0, 1.0);
  }

  void _buildTimeline(Float64List samples, int sampleRate) {
    final detector = PitchDetector(sampleRate: sampleRate);
    final frameSize = kFrameSize;
    final hopSize = frameSize ~/ 2;

    for (var i = 0; i + frameSize <= samples.length; i += hopSize) {
      final frame = Float64List.sublistView(samples, i, i + frameSize);
      final result = detector.detectPitchWithConfidence(frame);
      final timestampMs = (i * 1000 / sampleRate).round();

      _timeline.add(_PitchEntry(
        timestampMs,
        result.pitchHz > 60 && result.confidence > 0.2 ? result.pitchHz : 0,
      ));
    }
  }

  double _log2(double x) => x > 0 ? math.log(x) / math.ln2 : 0;

  void reset() {
    _timeline.clear();
    _isReady = false;
    _isLoading = false;
    _videoId = null;
  }
}

class _PitchEntry {
  final int timestampMs;
  final double pitchHz;
  const _PitchEntry(this.timestampMs, this.pitchHz);
}
