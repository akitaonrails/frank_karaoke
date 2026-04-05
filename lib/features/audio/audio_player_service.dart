import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Manages reference audio playback via just_audio.
/// Plays the audio stream extracted from YouTube so we have PCM access
/// for pitch detection and pitch shifting.
class AudioPlayerService {
  final _player = AudioPlayer();

  AudioPlayer get player => _player;

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Load an audio stream URL and start playing.
  Future<void> playUrl(String url) async {
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      debugPrint('AudioPlayerService: failed to play $url: $e');
    }
  }

  Future<void> pause() async => _player.pause();
  Future<void> resume() async => _player.play();
  Future<void> stop() async => _player.stop();
  Future<void> seekTo(Duration position) async => _player.seek(position);

  /// Set pitch shift in semitones (-6 to +6).
  Future<void> setPitchSemitones(int semitones) async {
    final pitch = math.pow(2, semitones / 12.0).toDouble();
    await _player.setPitch(pitch);
  }

  void dispose() {
    _player.dispose();
  }
}
