import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/audio_preset.dart';
import '../features/audio/audio_player_service.dart';
import '../features/audio/mic_capture_service.dart';
import '../features/youtube/youtube_audio_service.dart';
import '../features/youtube/youtube_sync_service.dart';

// Navigation
final currentTabProvider = StateProvider<int>((ref) => 0);

// YouTube
final currentVideoIdProvider = StateProvider<String?>((ref) => null);
final currentVideoTitleProvider = StateProvider<String?>((ref) => null);
final isVideoPlayingProvider = StateProvider<bool>((ref) => false);
final isAudioSyncingProvider = StateProvider<bool>((ref) => false);

// Overlay
final overlayVisibleProvider = StateProvider<bool>((ref) => true);

// Audio settings
final audioPresetProvider = StateProvider<AudioPreset>((ref) => AudioPreset.roomMic);
final audioEffectProvider = StateProvider<AudioEffect>((ref) => AudioEffect.none);
final pitchShiftProvider = StateProvider<int>((ref) => 0);

// Session
final participantsProvider = StateProvider<List<String>>((ref) => []);
final sessionActiveProvider = StateProvider<bool>((ref) => false);

// Scoring (placeholder for Phase 3)
final currentScoreProvider = StateProvider<int>((ref) => 0);

// Services
final youtubeAudioServiceProvider = Provider<YouTubeAudioService>((ref) {
  final service = YouTubeAudioService();
  ref.onDispose(service.dispose);
  return service;
});

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService();
  ref.onDispose(service.dispose);
  return service;
});

final micCaptureServiceProvider = Provider<MicCaptureService>((ref) {
  final service = MicCaptureService();
  ref.onDispose(service.dispose);
  return service;
});

final syncServiceProvider = Provider<YouTubeSyncService>((ref) {
  final service = YouTubeSyncService(
    audioExtractor: ref.watch(youtubeAudioServiceProvider),
    audioPlayer: ref.watch(audioPlayerServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
