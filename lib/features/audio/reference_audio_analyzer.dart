import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import 'pitch_detector.dart';

/// Decodes a remote audio URL to PCM using ffmpeg and runs pitch detection
/// to extract the reference melody's dominant pitch over time.
///
/// Works on Linux (and any platform with ffmpeg installed).
/// This gives us the instrumental track's pitch contour to compare
/// against the singer's voice.
class ReferenceAudioAnalyzer {
  final PitchDetector _pitchDetector = PitchDetector();
  Process? _ffmpegProcess;
  final _pitchController = StreamController<ReferencePitchFrame>.broadcast();
  bool _isRunning = false;
  DateTime? _startTime;

  Stream<ReferencePitchFrame> get pitchStream => _pitchController.stream;
  bool get isRunning => _isRunning;

  /// Start decoding and analyzing the audio URL.
  /// ffmpeg decodes to raw 16-bit signed mono PCM at 44100 Hz and pipes
  /// it to stdout. We read it in chunks and run pitch detection.
  Future<bool> start(String audioUrl) async {
    if (_isRunning) await stop();

    try {
      _ffmpegProcess = await Process.start('ffmpeg', [
        '-i', audioUrl,
        '-f', 's16le',      // raw PCM output
        '-acodec', 'pcm_s16le',
        '-ar', '$kSampleRate',
        '-ac', '1',          // mono
        '-v', 'quiet',       // suppress ffmpeg banner
        '-',                 // output to stdout
      ]);

      _isRunning = true;
      _startTime = DateTime.now();

      // Buffer for accumulating PCM data into analysis frames.
      final buffer = BytesBuilder();
      final frameBytes = kFrameSize * 2; // 16-bit = 2 bytes per sample
      var frameCount = 0;

      _ffmpegProcess!.stdout.listen(
        (chunk) {
          buffer.add(chunk);

          // Process complete frames.
          while (buffer.length >= frameBytes) {
            final bytes = buffer.takeBytes();
            final frameData = Uint8List.fromList(bytes.sublist(0, frameBytes));

            // If there's leftover, put it back.
            if (bytes.length > frameBytes) {
              buffer.add(bytes.sublist(frameBytes));
            }

            // Convert to doubles and detect pitch.
            final samples = Float64List(kFrameSize);
            final byteData = ByteData.sublistView(frameData);
            for (var i = 0; i < kFrameSize; i++) {
              samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
            }

            final pitchHz = _pitchDetector.detectPitch(samples);
            final rms = PitchDetector.rmsEnergy(samples);

            // Timestamp: estimate based on samples processed.
            final timestamp = Duration(
              milliseconds: (frameCount * kFrameSize * 1000 ~/ kSampleRate),
            );

            frameCount++;

            if (!_pitchController.isClosed) {
              _pitchController.add(ReferencePitchFrame(
                pitchHz: pitchHz,
                rms: rms,
                timestamp: timestamp,
              ));
            }

            if (frameCount <= 3 || frameCount % 500 == 0) {
              debugPrint('RefAudio: frame #$frameCount, '
                  'pitch=${pitchHz.toStringAsFixed(1)} Hz, '
                  'time=${timestamp.inSeconds}s');
            }
          }
        },
        onDone: () {
          debugPrint('RefAudio: ffmpeg stream ended, $frameCount frames');
          _isRunning = false;
        },
        onError: (e) {
          debugPrint('RefAudio: ffmpeg error: $e');
          _isRunning = false;
        },
      );

      // Log stderr for debugging.
      _ffmpegProcess!.stderr.listen((data) {
        // ffmpeg sends info to stderr; ignore with -v quiet
      });

      debugPrint('RefAudio: started analyzing $audioUrl');
      return true;
    } catch (e) {
      debugPrint('RefAudio: failed to start ffmpeg: $e');
      _isRunning = false;
      return false;
    }
  }

  /// Get the elapsed playback time since start.
  Duration get elapsed {
    if (_startTime == null) return Duration.zero;
    return DateTime.now().difference(_startTime!);
  }

  Future<void> stop() async {
    _isRunning = false;
    _ffmpegProcess?.kill();
    _ffmpegProcess = null;
    _startTime = null;
  }

  Future<void> dispose() async {
    await stop();
    await _pitchController.close();
  }
}

/// A single reference pitch frame from the instrumental track.
class ReferencePitchFrame {
  final double pitchHz;
  final double rms;
  final Duration timestamp;

  const ReferencePitchFrame({
    required this.pitchHz,
    required this.rms,
    required this.timestamp,
  });
}
