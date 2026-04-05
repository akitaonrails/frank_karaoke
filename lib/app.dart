import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

class FrankKaraokeApp extends StatelessWidget {
  const FrankKaraokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
