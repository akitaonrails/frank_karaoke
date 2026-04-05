import 'package:flutter/material.dart';

import '../../features/youtube/youtube_webview.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: const YouTubeWebView(),
      ),
    );
  }
}
