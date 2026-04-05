import 'dart:async';

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

  /// Separate audio player disabled for now — youtube_explode URLs
  /// get rejected by just_audio on Android (CDN blocks non-browser UA).
  /// TODO: fix user agent or use a different approach for reference PCM.
  bool get _useSeparateAudio => false;

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
