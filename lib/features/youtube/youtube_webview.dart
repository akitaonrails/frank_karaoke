import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' show AudioStreamInfo;

import '../../core/audio_preset.dart';
import '../../core/logo_assets.dart';
import '../../core/constants.dart';
import '../../core/scoring_mode.dart';
import '../../core/strings.dart';
import '../../state/providers.dart';
import '../overlay/webview_overlay.dart';
import '../scoring/scoring_session.dart';
import 'youtube_url_parser.dart';

class YouTubeWebView extends ConsumerStatefulWidget {
  const YouTubeWebView({super.key});

  @override
  ConsumerState<YouTubeWebView> createState() => _YouTubeWebViewState();
}

class _YouTubeWebViewState extends ConsumerState<YouTubeWebView> {
  late final WebViewController _controller;
  bool _isReady = false;

  ScoringSession? _scoringSession;
  StreamSubscription<ScoringUpdate>? _scoreSub;
  int _lastInjectedScore = -1;
  bool _overlayInjected = false;
  Timer? _videoEndTimer;
  bool _celebrationShown = false;
  bool _welcomeShown = false;
  bool _welcomeDismissedPermanently = false;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
    _initWebView();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPreset = prefs.getString('audio_preset');
    if (savedPreset != null) {
      final preset = AudioPreset.values.where((p) => p.name == savedPreset).firstOrNull;
      if (preset != null) ref.read(audioPresetProvider.notifier).state = preset;
    }
    final savedMode = prefs.getString('scoring_mode');
    if (savedMode != null) {
      final mode = ScoringMode.values.where((m) => m.name == savedMode).firstOrNull;
      if (mode != null) ref.read(scoringModeProvider.notifier).state = mode;
    }
    _welcomeDismissedPermanently = prefs.getBool('welcome_dismissed') ?? false;
    // Don't load saved calibration — it may be from a different device/mic.
    // User should recalibrate on each device via the settings panel.
  }

  Future<void> _saveSetting(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
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
      ..addJavaScriptChannel('FrankKaraoke', onMessageReceived: _onJsMessage)
      ..addJavaScriptChannel('FrankPreset', onMessageReceived: (m) => _onPresetChange(m.message))
      ..addJavaScriptChannel('FrankMode', onMessageReceived: (m) => _onModeChange(m.message))
      ..addJavaScriptChannel('FrankPitch', onMessageReceived: (m) => _onPitchChange(m.message))
      ..addJavaScriptChannel('FrankRestart', onMessageReceived: (_) => _restartScoring())
      ..addJavaScriptChannel('FrankCalibrate', onMessageReceived: (_) => _calibrateMic())
      ..addJavaScriptChannel('FrankDismissWelcome', onMessageReceived: (_) => _dismissWelcome())
      ..addJavaScriptChannel('FrankScoreInfo', onMessageReceived: (_) => _showScoreInfo())
      ..loadRequest(Uri.parse(kYouTubeDesktopUrl));
  }

  void _onPageLoaded() {
    if (!mounted) return;
    setState(() => _isReady = true);
    _injectBridge();
    _runJs(_cleanYouTubeUiJs);
    _runJs(_replaceLogoJs);
    // Block auto-play: intercept the video element whenever it appears.
    // YouTube dynamically creates/replaces video elements, so we use
    // MutationObserver to catch them all. Every video gets a play listener
    // that pauses unless _fkAllowPlay is true.
    _runJs('''
      (function() {
        window._fkAllowPlay = false;
        function guardVideo(v) {
          if (v._fkGuarded) return;
          v._fkGuarded = true;
          v.addEventListener('play', function() {
            if (!window._fkAllowPlay) { v.pause(); }
          });
          v.addEventListener('playing', function() {
            if (!window._fkAllowPlay) { v.pause(); }
          });
          if (!v.paused) v.pause();
        }
        // Guard any existing video.
        document.querySelectorAll('video').forEach(guardVideo);
        // Watch for new video elements.
        new MutationObserver(function() {
          document.querySelectorAll('video').forEach(guardVideo);
        }).observe(document.body || document.documentElement, {childList:true, subtree:true});
        // Also retry every 500ms for 10 seconds as a safety net.
        var attempts = 0;
        var timer = setInterval(function() {
          document.querySelectorAll('video').forEach(guardVideo);
          if (++attempts > 20) clearInterval(timer);
        }, 500);
      })();
    ''');
    if (!_welcomeShown && !_welcomeDismissedPermanently) {
      _welcomeShown = true;
      _runJs(WebviewOverlay.welcomeOverlayJs);
    }
    if (_overlayInjected) _reinjectOverlay();
  }

  void _injectBridge() {
    _runJs('''
      (function() {
        let lastUrl = location.href;
        const observer = new MutationObserver(() => {
          if (location.href !== lastUrl) {
            lastUrl = location.href;
            FrankKaraoke.postMessage(JSON.stringify({type:'urlChange',url:lastUrl}));
          }
        });
        observer.observe(document.body, {childList:true,subtree:true});

        // Monitor video play/pause/seek for scoring sync.
        // Uses MutationObserver to re-attach when YouTube replaces the video element.
        function guardVideo(v) {
          if (v._fkBridged) return;
          v._fkBridged = true;
          v.addEventListener('play', function() {
            FrankKaraoke.postMessage(JSON.stringify({type:'play'}));
          });
          v.addEventListener('pause', function() {
            FrankKaraoke.postMessage(JSON.stringify({type:'pause'}));
          });
          v.addEventListener('seeked', function() {
            FrankKaraoke.postMessage(JSON.stringify({
              type:'seeked', time: v.currentTime
            }));
          });
        }
        document.querySelectorAll('video').forEach(guardVideo);
        new MutationObserver(function() {
          document.querySelectorAll('video').forEach(guardVideo);
        }).observe(document.body || document.documentElement, {childList:true, subtree:true});
      })();
    ''');
  }

  static const _cleanYouTubeUiJs = '''
    (function() {
      if (document.getElementById('fk-yt-cleanup')) return;
      var s = document.createElement('style');
      s.id = 'fk-yt-cleanup';
      s.textContent = '#secondary{display:none!important}'
        + '#comments{display:none!important}'
        + '#related{display:none!important}'
        + 'ytd-watch-next-secondary-results-renderer{display:none!important}'
        + 'ytd-mealbar-promo-renderer{display:none!important}'
        + 'tp-yt-paper-dialog{display:none!important}'
        + 'ytm-promoted-sparkles-web-renderer{display:none!important}'
        + '.c3-module-companion{display:none!important}';
      document.head.appendChild(s);
    })();
  ''';

  static String get _replaceLogoJs => '''
    (function() {
      var logoDataUri = 'data:image/png;base64,$kLogoDarkBase64';
      function replaceLogo() {
        // CSS-based replacement using exact selectors from the live DOM.
        // YouTube mobile uses: ytm-home-logo > button > c3-icon.mobile-topbar-logo > svg
        // YouTube desktop uses: ytd-topbar-logo-renderer > a > yt-icon > svg
        var styleId = 'fk-logo-style';
        if (!document.getElementById(styleId)) {
          var st = document.createElement('style');
          st.id = styleId;
          st.textContent = ''
            // Hide YouTube's SVG logos.
            + 'c3-icon.mobile-topbar-logo svg,'
            + 'c3-icon#home-icon svg,'
            + 'ytm-home-logo svg,'
            + 'ytd-topbar-logo-renderer svg,'
            + 'ytd-topbar-logo-renderer yt-icon'
            + '{ display:none!important; }'
            // Show our logo via ::after on the button/link that contains it.
            + 'ytm-home-logo .mobile-topbar-header-endpoint::before,'
            + 'ytd-topbar-logo-renderer a::before'
            + '{ content:"";display:inline-block;width:120px;height:22px;'
            + 'background:url("' + logoDataUri + '") no-repeat left center/contain;'
            + 'vertical-align:middle; }';
          document.head.appendChild(st);
        }
      }
      replaceLogo();
      setTimeout(replaceLogo, 1000);
      setTimeout(replaceLogo, 3000);
      setTimeout(replaceLogo, 6000);

      // Hide "Open App" / "Open" button in YouTube's top bar.
      function hideOpenApp() {
        var header = document.querySelector('header, #masthead, ytm-mobile-topbar-renderer');
        if (!header) return;
        header.querySelectorAll('a, button').forEach(function(el) {
          var t = (el.textContent || '').trim();
          if (/^(open|open app|get app|use app)\$/i.test(t)) {
            el.style.display = 'none';
          }
        });
      }
      hideOpenApp();
      setTimeout(hideOpenApp, 2000);
      setTimeout(hideOpenApp, 5000);
    })();
  ''';

  void _onUrlChange(String? url) {
    if (url == null) return;
    final videoId = extractVideoId(url);
    final currentId = ref.read(currentVideoIdProvider);

    if (videoId != null && videoId != currentId) {
      // New video detected.
      ref.read(currentVideoIdProvider.notifier).state = videoId;
      _onVideoDetected(videoId);
    }
    // Don't stop scoring when videoId == currentId (seeking within same video)
    // or when URL briefly has no videoId (YouTube SPA transition).
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message);
      if (data is! Map) return;
      switch (data['type']) {
        case 'urlChange':
          _onUrlChange(data['url'] as String?);
        case 'play':
          _onVideoPlay();
        case 'pause':
          _onVideoPause();
        case 'seeked':
          _onVideoSeeked();
      }
    } catch (_) {}
  }

  void _onVideoPlay() {
    debugPrint('Video: play');
    if (_scoringSession != null && !_scoringSession!.isActive) {
      // Resume scoring after a short delay.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _scoringSession != null) {
          _scoringSession!.resume();
          debugPrint('Scoring: resumed');
        }
      });
    }
  }

  void _onVideoPause() {
    debugPrint('Video: pause');
    _scoringSession?.pause();
  }

  void _onVideoSeeked() {
    debugPrint('Video: seeked — resetting score');
    if (_scoringSession != null) {
      _scoringSession!.resetScore();
    }
  }

  Future<void> _onVideoDetected(String videoId) async {
    // Pause video and show loading overlay immediately.
    _runJs('''(function(){var v=document.querySelector('video');if(v)v.pause();})();''');
    _runJs(WebviewOverlay.processingOverlayJs(true, message: S.processingLoading));

    ref.read(isAudioSyncingProvider.notifier).state = true;

    final audioService = ref.read(youtubeAudioServiceProvider);
    final title = await audioService.getVideoTitle(videoId);
    if (mounted) ref.read(currentVideoTitleProvider.notifier).state = title;

    debugPrint('Video detected: $videoId');

    if (mounted) {
      ref.read(isAudioSyncingProvider.notifier).state = false;
      ref.read(isVideoPlayingProvider.notifier).state = true;
    }


    final streamInfo = await audioService.getAudioStreamInfo(videoId);

    // Start scoring, then allow and resume video playback.
    if (mounted) {
      _startScoring();
      _runJs('''(function(){window._fkAllowPlay=true;var v=document.querySelector('video');if(v){v.currentTime=0;v.play();}})();''');
    }

    // Build pitch oracle in the background.
    if (streamInfo != null) {
      _buildOracleInBackground(videoId, streamInfo);
    } else {
      debugPrint('PitchOracle: no stream info for $videoId');
    }
  }

  Future<void> _buildOracleInBackground(String videoId, AudioStreamInfo streamInfo) async {
    _runJs(WebviewOverlay.processingOverlayJs(true,
        message: S.processingLoadingSong));
    try {
      final oracle = ref.read(pitchOracleProvider);
      final built = await oracle.buildForVideo(videoId, streamInfo);
      debugPrint('PitchOracle: ${built ? "ready (${oracle.entryCount} entries)" : "failed"}');

      if (built && mounted && _scoringSession != null) {
        _scoringSession!.setOracle(oracle);
      }
    } catch (e) {
      debugPrint('PitchOracle: error: $e');
    } finally {
      // Always dismiss, even on timeout/failure/unmount.
      _runJs(WebviewOverlay.processingOverlayJs(false));
    }
  }

  // --- Scoring ---

  Future<void> _startScoring() async {
    await _stopScoring();

    final mic = ref.read(micCaptureServiceProvider);
    final preset = ref.read(audioPresetProvider);
    final mode = ref.read(scoringModeProvider);
    final calGate = ref.read(calibratedNoiseGateProvider);
    final calSinging = ref.read(calibratedSingingThresholdProvider);

    final oracle = ref.read(pitchOracleProvider);
    _scoringSession = ScoringSession(
      mic: mic,
      preset: preset,
      mode: mode,
      oracle: oracle.isReady ? oracle : null,
      calibratedNoiseGate: calGate,
      calibratedSingingThreshold: calSinging,
    );

    final started = await _scoringSession!.start();
    if (!started) {
      _scoringSession = null;
    }

    // Resume video if mic capture stole audio focus and paused it.
    await Future.delayed(const Duration(milliseconds: 500));
    _runJs('''(function(){var v=document.querySelector('video');if(v&&v.paused)v.play();})();''');

    // Inject overlay
    final title = ref.read(currentVideoTitleProvider) ?? '';
    final pitchShift = ref.read(pitchShiftProvider);
    try {
      await _runJs(WebviewOverlay.injectOverlayJs(
        singerName: title,
        activePreset: preset.name,
        pitchShift: pitchShift,
      ));
      _overlayInjected = true;
      _lastInjectedScore = -1;
      await _runJs(WebviewOverlay.updateScoreJs(0, 0));
    } catch (e) {
      debugPrint('Overlay: injection failed: $e');
    }

    ref.read(currentScoreProvider.notifier).state = 0;
    _scoreSub = _scoringSession?.scoreStream.listen(_onScoreUpdate);

    _celebrationShown = false;
    _videoEndTimer?.cancel();
    _videoEndTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkVideoEnd());
  }

  void _onScoreUpdate(ScoringUpdate update) {
    if (!_overlayInjected) return;

    if (update.totalScore != _lastInjectedScore ||
        _scoringSession?.mode == ScoringMode.streak) {
      _lastInjectedScore = update.totalScore;
      _runJs(WebviewOverlay.updateScoreJs(
        update.totalScore,
        update.overallScore,
        streakCount: update.streakCount,
        modeName: _scoringSession?.mode.label ?? '',
      ));
      ref.read(currentScoreProvider.notifier).state = update.totalScore;
    }

    final normalizedPitch = update.singerPitchHz > 0
        ? _logNormalize(update.singerPitchHz, 100, 800)
        : 0.0;
    _runJs(WebviewOverlay.updatePitchTrailJs(normalizedPitch, update.frameScore));

    final normalizedRms = (update.rmsEnergy * 100).clamp(0.0, 1.0);
    _runJs(WebviewOverlay.updateNoteAndRmsJs(update.noteName, normalizedRms));

    _runJs(WebviewOverlay.updateDebugJs(
      primaryScore: update.primaryScore,
      confidence: update.confidence,
      stability: update.stabilityScore,
      frameScore: update.frameScore,
      rms: update.rmsEnergy,
      pitchHz: update.singerPitchHz,
      streak: update.streakCount,
    ));
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
    if (_overlayInjected) {
      _runJs(WebviewOverlay.removeOverlayJs);
      _overlayInjected = false;
    }
  }

  Future<void> _restartScoring() async {
    _runJs('''(function(){var v=document.querySelector('video');if(v){v.currentTime=0;v.play();}})();''');
    await _stopScoring();
    _startScoring();
  }

  void _reinjectOverlay() {
    if (!_overlayInjected) return;
    final title = ref.read(currentVideoTitleProvider) ?? '';
    final preset = ref.read(audioPresetProvider);
    final pitchShift = ref.read(pitchShiftProvider);
    _runJs(WebviewOverlay.injectOverlayJs(
      singerName: title,
      activePreset: preset.name,
      pitchShift: pitchShift,
    ));
  }

  Future<void> _checkVideoEnd() async {
    if (_celebrationShown) return;
    try {
      final result = await _controller.runJavaScriptReturningResult('''
        (function(){var v=document.querySelector('video');
        if(!v||!v.duration||v.duration===Infinity)return'-1';
        return v.currentTime+'|'+v.duration;})();
      ''');
      final str = result is String ? result : result.toString();
      if (str.contains('|')) {
        final parts = str.replaceAll('"', '').split('|');
        final current = double.tryParse(parts[0]) ?? 0;
        final duration = double.tryParse(parts[1]) ?? 0;
        if (duration > 30 && current > 10 && (duration - current) < 5) {
          _celebrationShown = true;
          _videoEndTimer?.cancel();
          _runJs(WebviewOverlay.celebrationJs(
            _scoringSession?.finalScore ?? _lastInjectedScore,
          ));
        }
      }
    } catch (_) {}
  }

  // --- Settings handlers ---

  void _onPresetChange(String presetId) {
    final preset = AudioPreset.values.where((p) => p.name == presetId).firstOrNull;
    if (preset == null) return;
    ref.read(audioPresetProvider.notifier).state = preset;
    _saveSetting('audio_preset', preset.name);
    if (_overlayInjected) _runJs(WebviewOverlay.updatePresetJs(preset.name));
    if (_scoringSession != null) _restartScoring();
  }

  void _onModeChange(String modeId) {
    final mode = ScoringMode.values.where((m) => m.name == modeId).firstOrNull;
    if (mode == null) return;
    ref.read(scoringModeProvider.notifier).state = mode;
    _saveSetting('scoring_mode', mode.name);
    if (_scoringSession != null) _restartScoring();
  }

  void _onPitchChange(String direction) {
    final current = ref.read(pitchShiftProvider);
    final next = direction == 'up'
        ? (current + 1).clamp(kPitchShiftMin, kPitchShiftMax)
        : (current - 1).clamp(kPitchShiftMin, kPitchShiftMax);
    ref.read(pitchShiftProvider.notifier).state = next;
    if (_overlayInjected) _runJs(WebviewOverlay.updatePitchShiftJs(next));
  }

  Future<void> _calibrateMic() async {
    _runJs(WebviewOverlay.updateCalibrateJs(S.calibCountdown(3), active: true));

    final mic = ref.read(micCaptureServiceProvider);
    final wasRecording = mic.isRecording;
    if (!wasRecording) {
      final started = await mic.start();
      if (!started) {
        _runJs(WebviewOverlay.updateCalibrateJs(S.calibMicUnavailable));
        return;
      }
    }

    final rmsValues = <double>[];
    final sub = mic.pcmStream.listen((frame) {
      rmsValues.add(frame.rawPeak);
    });

    for (var i = 2; i >= 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (i > 0) _runJs(WebviewOverlay.updateCalibrateJs(S.calibCountdown(i), active: true));
    }

    await sub.cancel();
    if (!wasRecording) await mic.stop();

    if (rmsValues.isEmpty) {
      _runJs(WebviewOverlay.updateCalibrateJs(S.calibNoData));
      return;
    }

    rmsValues.sort();
    final p90 = rmsValues[(rmsValues.length * 0.9).floor()];
    final noiseGate = p90 * 2.0;
    final singingThreshold = p90 * 4.0;

    ref.read(calibratedNoiseGateProvider.notifier).state = noiseGate;
    ref.read(calibratedSingingThresholdProvider.notifier).state = singingThreshold;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('calibrated_noise_gate', noiseGate);
    await prefs.setDouble('calibrated_singing_threshold', singingThreshold);

    _runJs(WebviewOverlay.updateCalibrateJs(S.calibDone));
    if (_scoringSession != null) _restartScoring();
  }

  void _showScoreInfo() {
    final mode = ref.read(scoringModeProvider);
    _runJs(WebviewOverlay.scoreInfoOverlayJs(mode.name));
  }

  Future<void> _dismissWelcome() async {
    _welcomeDismissedPermanently = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('welcome_dismissed', true);
  }

  // --- Helpers ---

  Future<void> _runJs(String source) {
    return _controller.runJavaScript(source).catchError((e) {
      debugPrint('runJs error: $e');
    });
  }

  double _logNormalize(double hz, double minHz, double maxHz) {
    if (hz <= minHz) return 0;
    if (hz >= maxHz) return 1;
    return (math.log(hz / minHz) / math.log(maxHz / minHz)).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _stopScoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (!_isReady)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
