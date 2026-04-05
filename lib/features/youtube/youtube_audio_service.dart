import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Extracts audio stream URLs from YouTube videos using youtube_explode_dart.
class YouTubeAudioService {
  final _yt = YoutubeExplode();

  /// Extract the best audio-only stream URL for a given video ID.
  /// Returns null if extraction fails.
  Future<AudioStreamInfo?> getAudioStreamInfo(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly.sortByBitrate();
      if (audioStreams.isEmpty) return null;
      // Pick the highest bitrate audio stream.
      return audioStreams.last;
    } catch (e) {
      debugPrint('Failed to extract audio for $videoId: $e');
      return null;
    }
  }

  /// Get the video title for display.
  Future<String?> getVideoTitle(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      return video.title;
    } catch (e) {
      debugPrint('Failed to get title for $videoId: $e');
      return null;
    }
  }

  void dispose() {
    _yt.close();
  }
}
