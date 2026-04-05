import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/audio_preset.dart';
import '../core/scoring_mode.dart';
import '../features/audio/mic_capture_service.dart';
import '../features/audio/pitch_oracle.dart';
import '../features/youtube/youtube_audio_service.dart';

// YouTube
final currentVideoIdProvider = StateProvider<String?>((ref) => null);
final currentVideoTitleProvider = StateProvider<String?>((ref) => null);
final isVideoPlayingProvider = StateProvider<bool>((ref) => false);
final isAudioSyncingProvider = StateProvider<bool>((ref) => false);

// Audio settings
final audioPresetProvider = StateProvider<AudioPreset>((ref) => AudioPreset.roomMic);
final pitchShiftProvider = StateProvider<int>((ref) => 0);

// Scoring
final scoringModeProvider = StateProvider<ScoringMode>((ref) => ScoringMode.pitchClass);
final currentScoreProvider = StateProvider<int>((ref) => 0);

// Calibrated thresholds (null = use preset defaults)
final calibratedNoiseGateProvider = StateProvider<double?>((ref) => null);
final calibratedSingingThresholdProvider = StateProvider<double?>((ref) => null);

// Services
final youtubeAudioServiceProvider = Provider<YouTubeAudioService>((ref) {
  final service = YouTubeAudioService();
  ref.onDispose(service.dispose);
  return service;
});

final micCaptureServiceProvider = Provider<MicCaptureService>((ref) {
  final service = MicCaptureService();
  ref.onDispose(service.dispose);
  return service;
});

final pitchOracleProvider = Provider<PitchOracle>((ref) {
  final oracle = PitchOracle();
  ref.onDispose(oracle.reset);
  return oracle;
});

