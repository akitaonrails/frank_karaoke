import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../core/constants.dart';

/// Captures raw PCM audio from the microphone.
/// Normalizes quiet signals for pitch detection, preserves raw peak for gating.
class MicCaptureService {
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  final _pcmController = StreamController<MicFrame>.broadcast();
  bool _isRecording = false;
  bool _sessionConfigured = false;

  Stream<MicFrame> get pcmStream => _pcmController.stream;
  bool get isRecording => _isRecording;

  /// Configure audio session so mic recording doesn't pause YouTube video.
  Future<void> _ensureAudioSession() async {
    if (_sessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.mixWithOthers,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidWillPauseWhenDucked: false,
      ));
      _sessionConfigured = true;
      debugPrint('MicCapture: audio session configured');
    } catch (e) {
      debugPrint('MicCapture: audio session failed: $e');
    }
  }

  Future<bool> start() async {
    if (_isRecording) return true;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('MicCapture: no microphone permission');
      return false;
    }

    // Configure audio session to allow simultaneous playback + recording.
    await _ensureAudioSession();

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kSampleRate,
          numChannels: 1,
          // CRITICAL: autoGain must be FALSE on Samsung devices.
          // Samsung's AutomaticGainControl DSP ATTENUATES the signal
          // instead of boosting it, reducing peak to ~0.003.
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
          androidConfig: AndroidRecordConfig(
            // voicePerformance: Android's dedicated source for karaoke/
            // live singing apps. Provides better gain than defaultSource.
            audioSource: AndroidAudioSource.voicePerformance,
            manageBluetooth: false,
            // Use AudioRecord (not MediaRecorder) for direct PCM access.
            useLegacy: false,
          ),
        ),
      );

      _streamSub = stream.listen(_onAudioData);
      _isRecording = true;
      debugPrint('MicCapture: recording started (voicePerformance, no AGC)');
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

    // Software gain for quiet mics: only normalize when peak is
    // very low (< 0.01). This handles devices where hardware gain
    // is insufficient without distorting normal-level signals.
    if (peak > 0.00001 && peak < 0.01) {
      final gain = 0.3 / peak;
      final clampedGain = gain > 30 ? 30.0 : gain;
      for (var i = 0; i < samples.length; i++) {
        samples[i] *= clampedGain;
      }
      if (_frameCount <= 5) {
        debugPrint('MicCapture: software gain ${clampedGain.toStringAsFixed(1)}x');
      }
    }

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
