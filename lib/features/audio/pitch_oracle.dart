import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/constants.dart';
import 'pitch_detector.dart';

/// Pitch oracle: knows what pitch the music is playing at any moment.
///
/// Downloads reference audio, decodes to PCM, runs YIN pitch detection,
/// and builds a timestamped pitch timeline. Results are cached locally
/// by video ID so the same song never needs to be downloaded twice.
///
/// Used to distinguish singer from speaker bleed:
/// - mic pitch ≠ reference pitch → singer → score it
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
  /// Checks cache first; downloads and decodes only if not cached.
  Future<bool> buildForVideo(String videoId, AudioStreamInfo streamInfo) async {
    if (_videoId == videoId && _isReady) return true;
    if (_isLoading) return false;

    _isLoading = true;
    _timeline.clear();
    _isReady = false;
    _videoId = videoId;

    try {
      // Try loading from cache first.
      if (await _loadFromCache(videoId)) {
        _isReady = true;
        _isLoading = false;
        debugPrint('PitchOracle: loaded from cache, ${_timeline.length} entries');
        return true;
      }

      // Download and decode.
      debugPrint('PitchOracle: downloading audio for $videoId...');

      final yt = YoutubeExplode();
      final byteList = <int>[];
      var lastLog = DateTime.now();
      await for (final chunk in yt.videos.streamsClient.get(streamInfo).timeout(
        const Duration(seconds: 45),
        onTimeout: (sink) {
          debugPrint('PitchOracle: download timeout, using ${byteList.length} bytes');
          sink.close();
        },
      )) {
        byteList.addAll(chunk);
        final now = DateTime.now();
        if (now.difference(lastLog).inSeconds >= 2) {
          lastLog = now;
          debugPrint('PitchOracle: downloaded ${byteList.length} bytes...');
        }
      }
      yt.close();

      if (byteList.isEmpty) {
        debugPrint('PitchOracle: no data downloaded');
        _isLoading = false;
        return false;
      }

      final audioBytes = Uint8List.fromList(byteList);
      debugPrint('PitchOracle: downloaded ${audioBytes.length} bytes');

      // Determine format from codec.
      final codec = streamInfo.codec.mimeType;
      String formatHint;
      if (codec.contains('opus') || codec.contains('webm')) {
        formatHint = 'webm';
      } else if (codec.contains('mp4') || codec.contains('m4a') || codec.contains('aac')) {
        formatHint = 'm4a';
      } else {
        formatHint = 'mp4';
      }
      debugPrint('PitchOracle: decoding ($formatHint)...');

      // Decode to raw 16-bit mono PCM.
      final pcmBytes = await AudioDecoder.convertToWavBytes(
        audioBytes,
        formatHint: formatHint,
        sampleRate: kSampleRate,
        channels: 1,
        bitDepth: 16,
        includeHeader: false,
      );

      debugPrint('PitchOracle: decoded ${pcmBytes.length} PCM bytes');

      // Convert to Float64 and build timeline.
      final numSamples = pcmBytes.length ~/ 2;
      final samples = Float64List(numSamples);
      final byteData = ByteData.sublistView(pcmBytes);
      for (var i = 0; i < numSamples; i++) {
        samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      }

      _buildTimeline(samples, kSampleRate);

      // Save to cache.
      await _saveToCache(videoId);

      _isReady = true;
      _isLoading = false;
      debugPrint('PitchOracle: ready, ${_timeline.length} entries, '
          '${(numSamples / kSampleRate).toStringAsFixed(1)}s');
      return true;
    } catch (e) {
      debugPrint('PitchOracle: failed: $e');
      _isLoading = false;
      return false;
    }
  }

  /// Get the reference pitch at a given playback position (seconds).
  double getPitchAtSeconds(double seconds) {
    if (!_isReady || _timeline.isEmpty) return 0;

    final ms = (seconds * 1000).round();
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

  /// Singer confidence: 0.0 (speaker bleed) to 1.0 (singer).
  /// Uses video currentTime (seconds) for accurate sync.
  double singerConfidence(double micPitchHz, double videoTimeSeconds) {
    if (!_isReady) return 0.5;

    final refPitch = getPitchAtSeconds(videoTimeSeconds);
    if (refPitch <= 0) return 1.0; // music is silent = definitely singer

    final micMidi = 69 + 12 * _log2(micPitchHz / 440);
    final refMidi = 69 + 12 * _log2(refPitch / 440);
    final micClass = micMidi % 12;
    final refClass = refMidi % 12;
    var dist = (micClass - refClass).abs();
    if (dist > 6) dist = 12 - dist;

    return (dist / 2.0).clamp(0.0, 1.0);
  }

  // --- Cache ---

  Future<File> _cacheFile(String videoId) async {
    final dir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${dir.path}/pitch_oracle');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    return File('${cacheDir.path}/$videoId.json');
  }

  Future<bool> _loadFromCache(String videoId) async {
    try {
      final file = await _cacheFile(videoId);
      if (!file.existsSync()) return false;

      final json = jsonDecode(await file.readAsString());
      final entries = json['entries'] as List;
      _timeline.clear();
      for (final e in entries) {
        _timeline.add(_PitchEntry(e['t'] as int, (e['p'] as num).toDouble()));
      }
      return _timeline.isNotEmpty;
    } catch (e) {
      debugPrint('PitchOracle: cache load error: $e');
      return false;
    }
  }

  Future<void> _saveToCache(String videoId) async {
    try {
      final file = await _cacheFile(videoId);
      final entries = _timeline.map((e) => {'t': e.timestampMs, 'p': e.pitchHz}).toList();
      await file.writeAsString(jsonEncode({'videoId': videoId, 'entries': entries}));
      debugPrint('PitchOracle: cached ${_timeline.length} entries');
    } catch (e) {
      debugPrint('PitchOracle: cache save error: $e');
    }
  }

  // --- Timeline building ---

  void _buildTimeline(Float64List samples, int sampleRate) {
    final detector = PitchDetector(sampleRate: sampleRate, threshold: 0.15);
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
