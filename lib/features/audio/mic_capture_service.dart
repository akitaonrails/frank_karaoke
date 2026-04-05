import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../core/constants.dart';

/// Captures raw PCM audio from the microphone using the record package.
/// Configured for simultaneous playback + recording on Android.
class MicCaptureService {
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  final _pcmController = StreamController<Float64List>.broadcast();
  bool _isRecording = false;
  bool _sessionConfigured = false;

  Stream<Float64List> get pcmStream => _pcmController.stream;
  bool get isRecording => _isRecording;

  /// Configure the audio session for simultaneous playback + recording.
  /// Must be called before starting the mic on Android.
  Future<void> _configureAudioSession() async {
    if (_sessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.mixWithOthers,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.game,
        ),
        androidWillPauseWhenDucked: false,
      ));
      _sessionConfigured = true;
      debugPrint('MicCapture: audio session configured for mix mode');
    } catch (e) {
      debugPrint('MicCapture: audio session config failed: $e');
    }
  }

  Future<bool> start() async {
    if (_isRecording) return true;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('MicCapture: no microphone permission');
      return false;
    }

    // On Android, configure audio session BEFORE starting recording
    // to prevent the mic from stealing audio focus from the webview.
    if (!kIsWeb && Platform.isAndroid) {
      await _configureAudioSession();
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kSampleRate,
          numChannels: 1,
          autoGain: true,
          // Disable echo cancellation on Android — it uses
          // VOICE_COMMUNICATION mode which steals audio focus
          // and can mute the speaker.
          echoCancel: false,
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
