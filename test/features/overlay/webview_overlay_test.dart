import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/features/overlay/webview_overlay.dart';
import 'package:frank_karaoke/core/logo_assets.dart';

void main() {
  group('WebviewOverlay', () {
    group('logo replacement', () {
      test('injectOverlayJs creates overlay with required elements', () {
        final js = WebviewOverlay.injectOverlayJs(
          singerName: 'Test Song',
          activePreset: 'roomMic',
          pitchShift: 0,
        );
        expect(js, contains('fk-overlay'));
        expect(js, contains('fk-gear'));
        expect(js, contains('fk-score'));
        expect(js, contains('fk-pitch-canvas'));
      });

      test('welcomeOverlayJs uses dark logo', () {
        final js = WebviewOverlay.welcomeOverlayJs;
        expect(js, contains(kLogoDarkBase64.substring(0, 50)));
        expect(js, contains('fk-welcome'));
      });
    });

    group('YouTube cleanup CSS', () {
      test('injectOverlayJs removes processing overlay', () {
        final js = WebviewOverlay.injectOverlayJs(
          singerName: 'Test',
          activePreset: 'roomMic',
          pitchShift: 0,
        );
        expect(js, contains('fk-processing'));
        expect(js, contains('remove()'));
      });
    });

    group('score display', () {
      test('updateScoreJs returns valid JS for all score ranges', () {
        for (var score = 0; score <= 100; score += 10) {
          final js = WebviewOverlay.updateScoreJs(score, score ~/ 2);
          expect(js, contains('fk-score-value'));
          expect(js, contains('$score'));
        }
      });

      test('updateScoreJs shows streak messages only in streak mode', () {
        final streakJs = WebviewOverlay.updateScoreJs(50, 50,
            streakCount: 20, modeName: 'Streak');
        expect(streakJs, contains('COMBO'));

        final pitchJs = WebviewOverlay.updateScoreJs(50, 50,
            streakCount: 20, modeName: 'Pitch Match');
        expect(pitchJs, isNot(contains('COMBO')));
        expect(pitchJs, isNot(contains('Streak broken')));
      });

      test('updateScoreJs shows appropriate feedback per range', () {
        expect(
          WebviewOverlay.updateScoreJs(95, 95),
          contains('PERFECT'),
        );
        expect(
          WebviewOverlay.updateScoreJs(85, 85),
          contains('Incredible'),
        );
        expect(
          WebviewOverlay.updateScoreJs(75, 75),
          contains('Nailing'),
        );
        expect(
          WebviewOverlay.updateScoreJs(50, 50),
          contains('Keep going'),
        );
        expect(
          WebviewOverlay.updateScoreJs(20, 20),
          contains('Sing louder'),
        );
      });
    });

    group('score info overlay', () {
      test('scoreInfoOverlayJs contains all 4 modes', () {
        final js = WebviewOverlay.scoreInfoOverlayJs('pitchClass');
        expect(js, contains('Pitch Match'));
        expect(js, contains('Contour'));
        expect(js, contains('Intervals'));
        expect(js, contains('Streak'));
      });

      test('scoreInfoOverlayJs highlights active mode', () {
        final js = WebviewOverlay.scoreInfoOverlayJs('contour');
        expect(js, contains("m.id === 'contour'"));
      });

      test('scoreInfoOverlayJs mode buttons send FrankMode messages', () {
        final js = WebviewOverlay.scoreInfoOverlayJs('pitchClass');
        expect(js, contains('FrankMode.postMessage'));
      });

      test('scoreInfoOverlayJs is toggleable (removes existing)', () {
        final js = WebviewOverlay.scoreInfoOverlayJs('pitchClass');
        expect(js, contains('fk-score-info'));
        expect(js, contains('remove()'));
      });
    });

    group('processing overlay', () {
      test('processingOverlayJs shows when true', () {
        final js = WebviewOverlay.processingOverlayJs(true,
            message: 'Loading...');
        expect(js, contains('fk-processing'));
        expect(js, contains('Loading...'));
        expect(js, contains('true'));
      });

      test('processingOverlayJs removes when false', () {
        final js = WebviewOverlay.processingOverlayJs(false);
        expect(js, contains('remove()'));
      });
    });

    group('pitch trail', () {
      test('updatePitchTrailJs handles edge values', () {
        // Should not throw for any input values.
        expect(
          WebviewOverlay.updatePitchTrailJs(0.0, 0.0),
          contains('fk-pitch-canvas'),
        );
        expect(
          WebviewOverlay.updatePitchTrailJs(1.0, 1.0),
          contains('fk-pitch-canvas'),
        );
        expect(
          WebviewOverlay.updatePitchTrailJs(-0.5, 1.5),
          contains('0.000'), // clamped
        );
      });
    });

    group('calibration', () {
      test('updateCalibrateJs shows active state', () {
        final js = WebviewOverlay.updateCalibrateJs('Testing...', active: true);
        expect(js, contains('Testing...'));
        expect(js, contains('true'));
        expect(js, contains('fk-calibrate-btn'));
      });
    });

    group('removeOverlayJs', () {
      test('removes all overlay elements', () {
        expect(WebviewOverlay.removeOverlayJs, contains('fk-overlay'));
        expect(WebviewOverlay.removeOverlayJs, contains('remove()'));
      });
    });

    group('note and RMS display', () {
      test('updateNoteAndRmsJs handles note names', () {
        final js = WebviewOverlay.updateNoteAndRmsJs('C4', 0.5);
        expect(js, contains('C4'));
        expect(js, contains('fk-note-label'));
        expect(js, contains('fk-mic-dot'));
      });

      test('updateNoteAndRmsJs clamps RMS', () {
        final js = WebviewOverlay.updateNoteAndRmsJs('--', 2.0);
        expect(js, contains('100')); // clamped to 100%
      });
    });
  });
}
