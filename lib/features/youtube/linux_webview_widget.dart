import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'linux_webview_controller.dart';
import 'youtube_sync_service.dart';
import 'youtube_url_parser.dart';

/// Linux WebView widget backed by native WebKitGTK.
///
/// The native webview is overlaid on the GTK window via GtkOverlay.
/// When a video is detected, it triggers audio extraction and playback
/// via the sync service, and mutes the webview's own audio.
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
    await _controller.setFrame(bottom: 80);
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;
    final data = event['data'];

    switch (type) {
      case 'onLoadStop':
        final url = data is Map ? data['url'] as String? : null;
        if (url != null) _onUrlChange(url);
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
      // Navigated away from a video
      ref.read(currentVideoIdProvider.notifier).state = null;
      ref.read(isVideoPlayingProvider.notifier).state = false;
    }
  }

  Future<void> _onVideoDetected(String videoId) async {
    final syncService = ref.read(syncServiceProvider);

    ref.read(isAudioSyncingProvider.notifier).state = true;

    // Fetch video title
    final audioService = ref.read(youtubeAudioServiceProvider);
    final title = await audioService.getVideoTitle(videoId);
    if (mounted) {
      ref.read(currentVideoTitleProvider.notifier).state = title;
    }

    // Start audio extraction and playback
    await syncService.onVideoDetected(videoId);

    if (mounted) {
      ref.read(isAudioSyncingProvider.notifier).state = false;
      ref.read(isVideoPlayingProvider.notifier).state = true;
    }

    // On Android, mute the webview so audio comes from just_audio.
    // On Linux, the webview handles audio directly.
    if (_created && syncService.shouldMuteWebview) {
      await _controller.evaluateJavascript(
        source: YouTubeSyncService.muteVideoJs,
      );
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_created) {
      _controller.destroy();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentTabProvider);
    if (_created) {
      _controller.setVisible(currentTab == 0);
    }
    return const SizedBox.expand();
  }
}
