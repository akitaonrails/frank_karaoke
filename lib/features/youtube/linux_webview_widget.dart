import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio_preset.dart';
import '../../core/constants.dart';
import '../../core/scoring_mode.dart';
import '../../state/providers.dart';
import '../audio/reference_audio_analyzer.dart';
import '../overlay/webview_overlay.dart';
import '../scoring/scoring_session.dart';
import 'linux_webview_controller.dart';
import 'youtube_sync_service.dart';
import 'youtube_url_parser.dart';

class LinuxWebViewWidget extends ConsumerStatefulWidget {
  const LinuxWebViewWidget({super.key, required this.initialUrl});

  final String initialUrl;

  @override
  ConsumerState<LinuxWebViewWidget> createState() => _LinuxWebViewWidgetState();
}

class _LinuxWebViewWidgetState extends ConsumerState<LinuxWebViewWidget> {
  static const _eventChannel = EventChannel('frank_karaoke/webview_events');

  late final LinuxWebViewController _controller;
  StreamSubscription<dynamic>? _eventSub;
  bool _created = false;

  ScoringSession? _scoringSession;
  StreamSubscription<ScoringUpdate>? _scoreSub;
  ReferenceAudioAnalyzer? _refAnalyzer;
  int _lastInjectedScore = -1;
  bool _overlayInjected = false;
  Timer? _videoEndTimer;
  bool _celebrationShown = false;

  @override
  void initState() {
    super.initState();
    _controller = LinuxWebViewController();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(_onEvent);
    _loadSavedSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _createWebView());
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPreset = prefs.getString('audio_preset');
    if (savedPreset != null) {
      final preset = AudioPreset.values.where((p) => p.name == savedPreset).firstOrNull;
      if (preset != null) {
        ref.read(audioPresetProvider.notifier).state = preset;
      }
    }
    final savedMode = prefs.getString('scoring_mode');
    if (savedMode != null) {
      final mode = ScoringMode.values.where((m) => m.name == savedMode).firstOrNull;
      if (mode != null) {
        ref.read(scoringModeProvider.notifier).state = mode;
      }
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _createWebView() async {
    await _controller.create(url: widget.initialUrl);
    _created = true;

    _controller.addJavaScriptHandler(
      handlerName: 'FrankPreset',
      callback: (args) => _onPresetChange(args.isNotEmpty ? args[0] : ''),
    );
    _controller.addJavaScriptHandler(
      handlerName: 'FrankPitch',
      callback: (args) => _onPitchChange(args.isNotEmpty ? args[0] : ''),
    );
    _controller.addJavaScriptHandler(
      handlerName: 'FrankMode',
      callback: (args) => _onModeChange(args.isNotEmpty ? args[0] : ''),
    );
    _controller.addJavaScriptHandler(
      handlerName: 'FrankRestart',
      callback: (_) => _restartScoring(),
    );
  }

  void _onPresetChange(dynamic presetId) {
    final preset = AudioPreset.values.where((p) => p.name == presetId).firstOrNull;
    if (preset == null) return;
    ref.read(audioPresetProvider.notifier).state = preset;
    _saveSetting('audio_preset', preset.name);
    if (_created && _overlayInjected) {
      _controller.evaluateJavascript(
        source: WebviewOverlay.updatePresetJs(preset.name),
      );
    }
    if (_scoringSession != null) {
      _restartScoring();
    }
  }

  void _onModeChange(dynamic modeId) {
    final mode = ScoringMode.values.where((m) => m.name == modeId).firstOrNull;
    if (mode == null) return;
    ref.read(scoringModeProvider.notifier).state = mode;
    _saveSetting('scoring_mode', mode.name);
    if (_created && _overlayInjected) {
      _controller.evaluateJavascript(
        source: WebviewOverlay.updateModeJs(mode.name),
      );
    }
    // Changing scoring mode restarts the song.
    if (_scoringSession != null) {
      _restartScoring();
    }
  }

  void _onPitchChange(dynamic direction) {
    final current = ref.read(pitchShiftProvider);
    final next = direction == 'up'
        ? (current + 1).clamp(kPitchShiftMin, kPitchShiftMax)
        : (current - 1).clamp(kPitchShiftMin, kPitchShiftMax);
    ref.read(pitchShiftProvider.notifier).state = next;
    if (_created && _overlayInjected) {
      _controller.evaluateJavascript(
        source: WebviewOverlay.updatePitchShiftJs(next),
      );
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;
    final data = event['data'];

    switch (type) {
      case 'onLoadStop':
        final url = data is Map ? data['url'] as String? : null;
        if (url != null) _onUrlChange(url);
        if (_created) {
          _controller.evaluateJavascript(source: _cleanYouTubeUiJs);
        }
        if (_overlayInjected) _reinjectOverlay();
      case 'onUpdateVisitedHistory':
        final url = data is Map ? data['url'] as String? : null;
        if (url != null) _onUrlChange(url);
      case 'onJavaScriptHandler':
        if (data is Map) {
          final name = data['name'] as String? ?? '';
          final args = data['args'] as String? ?? '[]';
          _controller.dispatchHandler(name, args);
        }
    }
  }

  static const _cleanYouTubeUiJs = '''
    (function() {
      var style = document.createElement('style');
      style.id = 'fk-yt-cleanup';
      if (document.getElementById('fk-yt-cleanup')) return;
      style.textContent = [
        '#secondary { display: none !important; }',
        '#comments { display: none !important; }',
        '#related { display: none !important; }',
        'ytd-watch-next-secondary-results-renderer { display: none !important; }',
      ].join('\\n');
      document.head.appendChild(style);
    })();
  ''';

  void _onUrlChange(String url) {
    final videoId = extractVideoId(url);
    final currentId = ref.read(currentVideoIdProvider);

    if (videoId != null && videoId != currentId) {
      ref.read(currentVideoIdProvider.notifier).state = videoId;
      _onVideoDetected(videoId);
    } else if (videoId == null && currentId != null) {
      ref.read(currentVideoIdProvider.notifier).state = null;
      ref.read(isVideoPlayingProvider.notifier).state = false;
      _stopScoring();
    }
  }

  Future<void> _onVideoDetected(String videoId) async {
    final syncService = ref.read(syncServiceProvider);

    ref.read(isAudioSyncingProvider.notifier).state = true;

    // Get title and audio stream URL.
    final audioService = ref.read(youtubeAudioServiceProvider);
    final title = await audioService.getVideoTitle(videoId);
    if (mounted) {
      ref.read(currentVideoTitleProvider.notifier).state = title;
    }

    await syncService.onVideoDetected(videoId);

    if (mounted) {
      ref.read(isAudioSyncingProvider.notifier).state = false;
      ref.read(isVideoPlayingProvider.notifier).state = true;
    }

    if (_created && syncService.shouldMuteWebview) {
      await _controller.evaluateJavascript(
        source: YouTubeSyncService.muteVideoJs,
      );
    }

    // Start reference audio analysis (ffmpeg decode + pitch detection).
    final streamInfo = await audioService.getAudioStreamInfo(videoId);
    String? refAudioUrl;
    if (streamInfo != null) {
      refAudioUrl = streamInfo.url.toString();
    }

    _startScoring(refAudioUrl: refAudioUrl);
  }

  Future<void> _startScoring({String? refAudioUrl}) async {
    await _stopScoring();

    final mic = ref.read(micCaptureServiceProvider);
    final preset = ref.read(audioPresetProvider);

    final mode = ref.read(scoringModeProvider);
    _scoringSession = ScoringSession(mic: mic, preset: preset, mode: mode);

    // Start reference audio analyzer if we have a URL.
    if (refAudioUrl != null) {
      _refAnalyzer = ReferenceAudioAnalyzer();
      final refStarted = await _refAnalyzer!.start(refAudioUrl);
      if (refStarted) {
        _scoringSession!.connectReferenceAnalyzer(_refAnalyzer!);
        debugPrint('Scoring: reference audio analyzer connected');
      } else {
        debugPrint('Scoring: reference analyzer failed, using fallback');
        await _refAnalyzer!.dispose();
        _refAnalyzer = null;
      }
    }

    final started = await _scoringSession!.start();
    if (!started) {
      debugPrint('Scoring: mic unavailable');
      _scoringSession = null;
    }

    if (_created) {
      final title = ref.read(currentVideoTitleProvider) ?? '';
      final pitchShift = ref.read(pitchShiftProvider);
      try {
        await _controller.evaluateJavascript(
          source: WebviewOverlay.injectOverlayJs(
            singerName: title,
            activePreset: preset.name,
            activeScoringMode: mode.name,
            pitchShift: pitchShift,
          ),
        );
        _overlayInjected = true;
        _lastInjectedScore = -1;
      } catch (e) {
        debugPrint('Overlay: injection failed: $e');
      }
    }

    _scoreSub = _scoringSession?.scoreStream.listen(_onScoreUpdate);

    _celebrationShown = false;
    _videoEndTimer?.cancel();
    _videoEndTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkVideoEnd();
    });
  }

  Future<void> _checkVideoEnd() async {
    if (!_created || _celebrationShown) return;
    try {
      final result = await _controller.evaluateJavascript(
        source: '''
          (function() {
            var v = document.querySelector('video');
            if (!v || !v.duration || v.duration === Infinity) return '-1';
            return v.currentTime + '|' + v.duration;
          })();
        ''',
      );
      if (result is String && result.contains('|')) {
        final parts = result.split('|');
        final current = double.tryParse(parts[0]) ?? 0;
        final duration = double.tryParse(parts[1]) ?? 0;
        if (duration > 30 && current > 10 && (duration - current) < 5) {
          _showCelebration();
        }
      }
    } catch (_) {}
  }

  void _showCelebration() {
    if (_celebrationShown || !_created) return;
    _celebrationShown = true;
    _videoEndTimer?.cancel();

    final score = _scoringSession?.finalScore ?? _lastInjectedScore;
    _controller.evaluateJavascript(
      source: WebviewOverlay.celebrationJs(score),
    );
  }

  void _onScoreUpdate(ScoringUpdate update) {
    if (!_created || !_overlayInjected) return;

    if (update.totalScore != _lastInjectedScore) {
      _lastInjectedScore = update.totalScore;
      _controller.evaluateJavascript(
        source: WebviewOverlay.updateScoreJs(
          update.totalScore,
          update.overallScore,
        ),
      );
      ref.read(currentScoreProvider.notifier).state = update.totalScore;
    }

    final normalizedPitch = update.singerPitchHz > 0
        ? _logNormalize(update.singerPitchHz, 100, 800)
        : 0.0;
    _controller.evaluateJavascript(
      source: WebviewOverlay.updatePitchTrailJs(
        normalizedPitch,
        update.frameScore,
      ),
    );

    final normalizedRms = (update.rmsEnergy * 100).clamp(0.0, 1.0);
    _controller.evaluateJavascript(
      source: WebviewOverlay.updateNoteAndRmsJs(update.noteName, normalizedRms),
    );
  }

  double _logNormalize(double hz, double minHz, double maxHz) {
    if (hz <= minHz) return 0;
    if (hz >= maxHz) return 1;
    return (math.log(hz / minHz) / math.log(maxHz / minHz)).clamp(0.0, 1.0);
  }

  Future<void> _restartScoring() async {
    if (!_created) return;
    await _controller.evaluateJavascript(
      source: '''
        (function() {
          var v = document.querySelector('video');
          if (v) { v.currentTime = 0; v.play(); }
        })();
      ''',
    );

    // Re-fetch audio URL for reference analyzer.
    final videoId = ref.read(currentVideoIdProvider);
    String? refAudioUrl;
    if (videoId != null) {
      final audioService = ref.read(youtubeAudioServiceProvider);
      final streamInfo = await audioService.getAudioStreamInfo(videoId);
      if (streamInfo != null) {
        refAudioUrl = streamInfo.url.toString();
      }
    }

    await _stopScoring();
    _startScoring(refAudioUrl: refAudioUrl);
  }

  Future<void> _stopScoring() async {
    _videoEndTimer?.cancel();
    _videoEndTimer = null;
    await _scoreSub?.cancel();
    _scoreSub = null;

    if (_scoringSession != null) {
      await _scoringSession!.stop();
      _scoringSession = null;
    }

    if (_refAnalyzer != null) {
      await _refAnalyzer!.stop();
      await _refAnalyzer!.dispose();
      _refAnalyzer = null;
    }

    if (_created && _overlayInjected) {
      await _controller.evaluateJavascript(
        source: WebviewOverlay.removeOverlayJs,
      );
      _overlayInjected = false;
    }
  }

  void _reinjectOverlay() {
    if (!_overlayInjected || !_created) return;
    final title = ref.read(currentVideoTitleProvider) ?? '';
    final preset = ref.read(audioPresetProvider);
    final mode = ref.read(scoringModeProvider);
    final pitchShift = ref.read(pitchShiftProvider);
    _controller.evaluateJavascript(
      source: WebviewOverlay.injectOverlayJs(
        singerName: title,
        activePreset: preset.name,
        activeScoringMode: mode.name,
        pitchShift: pitchShift,
      ),
    );
  }

  @override
  void dispose() {
    _stopScoring();
    _eventSub?.cancel();
    if (_created) {
      _controller.destroy();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
