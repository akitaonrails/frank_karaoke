import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../features/youtube/linux_webview_widget.dart';
import '../../features/youtube/youtube_webview.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildWebView(),
    );
  }

  Widget _buildWebView() {
    if (kIsWeb) return const _WebViewUnsupported();
    if (Platform.isLinux) {
      return const LinuxWebViewWidget(initialUrl: kYouTubeDesktopUrl);
    }
    if (Platform.isAndroid) {
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
