import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/audio_player_service.dart';
import 'youtube_audio_service.dart';

/// Orchestrates the dual-stream architecture:
/// - Detects video ID changes from the webview
/// - Extracts audio stream URL via youtube_explode_dart
/// - Plays audio via just_audio
/// - Provides the JS to mute/unmute the webview video element
class YouTubeSyncService {
  final YouTubeAudioService _audioExtractor;
  final AudioPlayerService _audioPlayer;

  String? _currentVideoId;
  bool _isSyncing = false;

  YouTubeSyncService({
    YouTubeAudioService? audioExtractor,
    AudioPlayerService? audioPlayer,
  })  : _audioExtractor = audioExtractor ?? YouTubeAudioService(),
        _audioPlayer = audioPlayer ?? AudioPlayerService();

  AudioPlayerService get audioPlayer => _audioPlayer;
  String? get currentVideoId => _currentVideoId;
  bool get isSyncing => _isSyncing;

  /// Called when the webview URL changes and a new video ID is detected.
  /// Extracts the audio, starts playback, and returns the JS to mute the webview.
  Future<void> onVideoDetected(String videoId) async {
    if (videoId == _currentVideoId) return;
    _currentVideoId = videoId;
    _isSyncing = true;

    debugPrint('SyncService: detected video $videoId, extracting audio...');

    try {
      final streamInfo = await _audioExtractor.getAudioStreamInfo(videoId);
      if (streamInfo == null) {
        debugPrint('SyncService: no audio stream found for $videoId');
        _isSyncing = false;
        return;
      }

      final audioUrl = streamInfo.url.toString();
      debugPrint('SyncService: got audio URL, starting playback');

      await _audioPlayer.playUrl(audioUrl);
      _isSyncing = false;

      debugPrint('SyncService: audio playing for $videoId');
    } catch (e) {
      debugPrint('SyncService: failed to sync video $videoId: $e');
      _isSyncing = false;
    }
  }

  /// Stop audio and clear state.
  Future<void> stop() async {
    _currentVideoId = null;
    await _audioPlayer.stop();
  }

  /// JS to mute the video element in the webview.
  static const muteVideoJs = '''
    (function() {
      const video = document.querySelector('video');
      if (video) video.muted = true;
    })();
  ''';

  /// JS to unmute the video element in the webview.
  static const unmuteVideoJs = '''
    (function() {
      const video = document.querySelector('video');
      if (video) video.muted = false;
    })();
  ''';

  /// JS to read the current playback time from the webview video element.
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
