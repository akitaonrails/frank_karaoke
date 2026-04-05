import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../audio/audio_player_service.dart';
import 'youtube_audio_service.dart';

/// Orchestrates the dual-stream architecture:
/// - Detects video ID changes from the webview
/// - Extracts audio stream URL via youtube_explode_dart
/// - On Android: plays audio via just_audio and mutes the webview
/// - On Linux: lets the webview play audio (just_audio has no Linux backend)
class YouTubeSyncService {
  final YouTubeAudioService _audioExtractor;
  final AudioPlayerService _audioPlayer;

  String? _currentVideoId;
  bool _isSyncing = false;

  /// Whether to use the separate audio player (Android) or let the
  /// webview handle audio (Linux desktop).
  bool get _useSeparateAudio => !kIsWeb && Platform.isAndroid;

  YouTubeSyncService({
    YouTubeAudioService? audioExtractor,
    AudioPlayerService? audioPlayer,
  })  : _audioExtractor = audioExtractor ?? YouTubeAudioService(),
        _audioPlayer = audioPlayer ?? AudioPlayerService();

  AudioPlayerService get audioPlayer => _audioPlayer;
  String? get currentVideoId => _currentVideoId;
  bool get isSyncing => _isSyncing;

  /// Called when the webview URL changes and a new video ID is detected.
  Future<void> onVideoDetected(String videoId) async {
    if (videoId == _currentVideoId) return;
    _currentVideoId = videoId;
    _isSyncing = true;

    debugPrint('SyncService: detected video $videoId');

    if (_useSeparateAudio) {
      try {
        final streamInfo = await _audioExtractor.getAudioStreamInfo(videoId);
        if (streamInfo == null) {
          debugPrint('SyncService: no audio stream found for $videoId');
          _isSyncing = false;
          return;
        }

        final audioUrl = streamInfo.url.toString();
        debugPrint('SyncService: starting just_audio playback');
        await _audioPlayer.playUrl(audioUrl);
      } catch (e) {
        debugPrint('SyncService: failed to sync audio for $videoId: $e');
      }
    } else {
      debugPrint('SyncService: Linux mode — webview handles audio');
    }

    _isSyncing = false;
    debugPrint('SyncService: ready for $videoId');
  }

  Future<void> stop() async {
    _currentVideoId = null;
    if (_useSeparateAudio) {
      await _audioPlayer.stop();
    }
  }

  /// Whether the webview audio should be muted (only on Android where
  /// just_audio handles playback separately).
  bool get shouldMuteWebview => _useSeparateAudio;

  static const muteVideoJs = '''
    (function() {
      const video = document.querySelector('video');
      if (video) video.muted = true;
    })();
  ''';

  static const unmuteVideoJs = '''
    (function() {
      const video = document.querySelector('video');
      if (video) video.muted = false;
    })();
  ''';

  static const getCurrentTimeJs = '''
    (function() {
      const video = document.querySelector('video');
      return video ? video.currentTime : -1;
    })();
  ''';

  void dispose() {
    _audioExtractor.dispose();
    _audioPlayer.dispose();
  }
}
