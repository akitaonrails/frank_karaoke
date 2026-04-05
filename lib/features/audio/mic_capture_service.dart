import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../core/constants.dart';

/// Captures raw PCM audio from the microphone.
class MicCaptureService {
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  final _pcmController = StreamController<MicFrame>.broadcast();
  bool _isRecording = false;

  Stream<MicFrame> get pcmStream => _pcmController.stream;
  bool get isRecording => _isRecording;

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
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
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

    final samples = Float64List(bytes.length ~/ 2);
    final byteData = ByteData.sublistView(bytes);

    double peak = 0;
    for (var i = 0; i < samples.length; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      samples[i] = sample / 32768.0;
      final abs = samples[i].abs();
      if (abs > peak) peak = abs;
    }

    if (_frameCount <= 5 || _frameCount % 100 == 0) {
      debugPrint('MicCapture: frame #$_frameCount, '
          'peak=${peak.toStringAsFixed(4)}, ${bytes.length} bytes');
    }

    // No software gain — YIN autocorrelation is amplitude-independent.
    // Normalizing quiet signals amplifies noise uniformly, making
    // YIN unable to distinguish periodicity from noise floor.
    _pcmController.add(MicFrame(samples, peak));
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    await _streamSub?.cancel();
    _streamSub = null;
    await _recorder.stop();
    _isRecording = false;
    _frameCount = 0;
    debugPrint('MicCapture: recording stopped');
  }

  Future<void> dispose() async {
    await stop();
    await _pcmController.close();
    _recorder.dispose();
  }
}

/// A mic audio frame with processed samples and raw peak amplitude.
class MicFrame {
  final Float64List samples;
  final double rawPeak;
  const MicFrame(this.samples, this.rawPeak);
}
