import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants.dart';
import '../../state/providers.dart';
import 'youtube_url_parser.dart';

class YouTubeWebView extends ConsumerStatefulWidget {
  const YouTubeWebView({super.key});

  @override
  ConsumerState<YouTubeWebView> createState() => _YouTubeWebViewState();
}

class _YouTubeWebViewState extends ConsumerState<YouTubeWebView> {
  late final WebViewController _controller;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onPageLoaded(),
          onUrlChange: (change) => _onUrlChange(change.url),
        ),
      )
      ..addJavaScriptChannel(
        'FrankKaraoke',
        onMessageReceived: _onJsMessage,
      )
      ..loadRequest(Uri.parse(_youtubeUrl));
  }

  String get _youtubeUrl {
    // Use mobile YouTube on Android for better touch UX,
    // desktop YouTube on Linux for better mouse/keyboard UX
    if (!kIsWeb && Platform.isAndroid) {
      return kYouTubeMobileUrl;
    }
    return kYouTubeDesktopUrl;
  }

  void _onPageLoaded() {
    if (!mounted) return;
    setState(() => _isReady = true);
    _injectBridge();
  }

  void _injectBridge() {
    _controller.runJavaScript('''
      (function() {
        // Monitor URL changes for video ID extraction
        let lastUrl = location.href;
        const observer = new MutationObserver(() => {
          if (location.href !== lastUrl) {
            lastUrl = location.href;
            FrankKaraoke.postMessage(JSON.stringify({
              type: 'urlChange',
              url: lastUrl
            }));
          }
        });
        observer.observe(document.body, { childList: true, subtree: true });

        // Monitor video element for play/pause
        function watchVideo() {
          const video = document.querySelector('video');
          if (!video) {
            setTimeout(watchVideo, 1000);
            return;
          }
          video.addEventListener('play', () => {
            FrankKaraoke.postMessage(JSON.stringify({
              type: 'play',
              currentTime: video.currentTime
            }));
          });
          video.addEventListener('pause', () => {
            FrankKaraoke.postMessage(JSON.stringify({
              type: 'pause',
              currentTime: video.currentTime
            }));
          });
        }
        watchVideo();
      })();
    ''');
  }

  void _onUrlChange(String? url) {
    if (url == null) return;
    final videoId = extractVideoId(url);
    if (videoId != null) {
      ref.read(currentVideoIdProvider.notifier).state = videoId;
    }
  }

  void _onJsMessage(JavaScriptMessage message) {
    // Will be expanded in Phase 2 for audio sync
    debugPrint('JS Bridge: ${message.message}');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (!_isReady)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}
