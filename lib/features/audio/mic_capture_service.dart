import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../core/constants.dart';

/// Captures raw PCM audio from the microphone using the record package.
/// Streams audio frames for real-time pitch detection.
class MicCaptureService {
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  final _pcmController = StreamController<Float64List>.broadcast();
  bool _isRecording = false;

  /// Stream of PCM audio frames (16-bit signed, mono, converted to doubles).
  Stream<Float64List> get pcmStream => _pcmController.stream;
  bool get isRecording => _isRecording;

  /// Start capturing audio from the microphone.
  Future<bool> start() async {
    if (_isRecording) return true;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('MicCapture: no microphone permission');
      return false;
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kSampleRate,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );

      _streamSub = stream.listen(_onAudioData);
      _isRecording = true;
      debugPrint('MicCapture: recording started');
      return true;
    } catch (e) {
      debugPrint('MicCapture: failed to start: $e');
      return false;
    }
  }

  int _frameCount = 0;

  void _onAudioData(Uint8List bytes) {
    if (bytes.isEmpty) return;

    _frameCount++;
    if (_frameCount <= 3 || _frameCount % 100 == 0) {
      debugPrint('MicCapture: frame #$_frameCount, ${bytes.length} bytes');
    }

    // Convert 16-bit signed PCM to double array (-1.0 to 1.0).
    final samples = Float64List(bytes.length ~/ 2);
    final byteData = ByteData.sublistView(bytes);
    for (var i = 0; i < samples.length; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      samples[i] = sample / 32768.0;
    }
    _pcmController.add(samples);
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    await _streamSub?.cancel();
    _streamSub = null;
    await _recorder.stop();
    _isRecording = false;
    debugPrint('MicCapture: recording stopped');
  }

  Future<void> dispose() async {
    await stop();
    await _pcmController.close();
    _recorder.dispose();
  }
}
