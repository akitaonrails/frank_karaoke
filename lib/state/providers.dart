import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/audio_preset.dart';

// Navigation
final currentTabProvider = StateProvider<int>((ref) => 0);

// YouTube
final currentVideoIdProvider = StateProvider<String?>((ref) => null);
final currentVideoTitleProvider = StateProvider<String?>((ref) => null);
final isVideoPlayingProvider = StateProvider<bool>((ref) => false);

// Overlay
final overlayVisibleProvider = StateProvider<bool>((ref) => true);

// Audio settings
final audioPresetProvider = StateProvider<AudioPreset>((ref) => AudioPreset.roomMic);
final audioEffectProvider = StateProvider<AudioEffect>((ref) => AudioEffect.none);
final pitchShiftProvider = StateProvider<int>((ref) => 0);

// Scoring (placeholder for Phase 3)
final currentScoreProvider = StateProvider<int>((ref) => 0);
