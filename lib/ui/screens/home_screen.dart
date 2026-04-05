import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants.dart';
import '../../features/youtube/linux_webview_widget.dart';
import '../../features/youtube/youtube_webview.dart';
import '../../state/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlayVisible = ref.watch(overlayVisibleProvider);
    final videoId = ref.watch(currentVideoIdProvider);
    final score = ref.watch(currentScoreProvider);

    return Scaffold(
      body: Stack(
        children: [
          _buildWebView(),

          // Overlay toggle button (always visible)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: _OverlayToggle(
              visible: overlayVisible,
              onToggle: () {
                ref.read(overlayVisibleProvider.notifier).state = !overlayVisible;
              },
            ),
          ),

          // Scoring overlay
          if (overlayVisible && videoId != null) ...[
            // Top banner: current song
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 64,
              child: _SongBanner(videoId: videoId),
            ),

            // Score display (bottom right)
            Positioned(
              bottom: 24,
              right: 24,
              child: _ScoreDisplay(score: score),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (kIsWeb) return const _WebViewUnsupported();
    if (Platform.isLinux) {
      return const LinuxWebViewWidget(initialUrl: kYouTubeDesktopUrl);
    }
    if (Platform.isAndroid && WebViewPlatform.instance != null) {
      return const YouTubeWebView();
    }
    return const _WebViewUnsupported();
  }
}

class _WebViewUnsupported extends StatelessWidget {
  const _WebViewUnsupported();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 64, color: Colors.amber),
          SizedBox(height: 16),
          Text(
            'WebView not supported on this platform.\n'
            'Use Android or Linux desktop.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OverlayToggle extends StatelessWidget {
  const _OverlayToggle({required this.visible, required this.onToggle});

  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(
          visible ? Icons.visibility : Icons.visibility_off,
          color: visible ? kAccentGlow : Colors.white54,
        ),
        onPressed: onToggle,
        tooltip: visible ? 'Hide overlay' : 'Show overlay',
        iconSize: 28,
      ),
    );
  }
}

class _SongBanner extends StatelessWidget {
  const _SongBanner({required this.videoId});

  final String videoId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Playing: $videoId',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ScoreDisplay extends StatelessWidget {
  const _ScoreDisplay({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kAccentGlow.withAlpha(128), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SCORE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          Text(
            '$score',
            style: const TextStyle(
              color: kAccentGlow,
              fontSize: kScoreFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
