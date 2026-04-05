import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
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
  int _lastInjectedScore = -1;
  bool _overlayInjected = false;

  @override
  void initState() {
    super.initState();
    _controller = LinuxWebViewController();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(_onEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _createWebView());
  }

  Future<void> _createWebView() async {
    await _controller.create(url: widget.initialUrl);
    _created = true;
    // Full screen — no bottom inset needed anymore.
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;
    final data = event['data'];

    switch (type) {
      case 'onLoadStop':
        final url = data is Map ? data['url'] as String? : null;
        if (url != null) _onUrlChange(url);
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

    // Automatically start scoring when a video plays.
    _startScoring();
  }

  Future<void> _startScoring() async {
    await _stopScoring();

    final mic = ref.read(micCaptureServiceProvider);
    final preset = ref.read(audioPresetProvider);

    _scoringSession = ScoringSession(mic: mic, preset: preset);
    final started = await _scoringSession!.start();

    if (!started) {
      debugPrint('Scoring: mic unavailable, overlay only');
      _scoringSession = null;
    }

    // Inject overlay regardless of mic (shows song info even without scoring).
    if (_created) {
      final title = ref.read(currentVideoTitleProvider) ?? '';
      await _controller.evaluateJavascript(
        source: WebviewOverlay.injectOverlayJs(singerName: title),
      );
      _overlayInjected = true;
      _lastInjectedScore = -1;
    }

    _scoreSub = _scoringSession?.scoreStream.listen(_onScoreUpdate);
  }

  void _onScoreUpdate(ScoringUpdate update) {
    if (!_created || !_overlayInjected) return;

    if (update.totalScore != _lastInjectedScore) {
      _lastInjectedScore = update.totalScore;
      _controller.evaluateJavascript(
        source: WebviewOverlay.updateScoreJs(update.totalScore),
      );
      ref.read(currentScoreProvider.notifier).state = update.totalScore;
    }

    if (update.singerPitchHz > 0) {
      final normalized =
          ((update.singerPitchHz - 80) / 720).clamp(0.0, 1.0);
      _controller.evaluateJavascript(
        source: WebviewOverlay.updatePitchJs(normalized),
      );
    }
  }

  Future<void> _stopScoring() async {
    await _scoreSub?.cancel();
    _scoreSub = null;

    if (_scoringSession != null) {
      await _scoringSession!.stop();
      _scoringSession = null;
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
    _controller.evaluateJavascript(
      source: WebviewOverlay.injectOverlayJs(singerName: title),
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
