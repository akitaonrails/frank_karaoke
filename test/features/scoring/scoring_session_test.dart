import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScoringSession resetScore', () {
    test('clears reference-side contour and interval state', () {
      final source = File(
        'lib/features/scoring/scoring_session.dart',
      ).readAsStringSync();
      final resetBody = RegExp(
        r'void resetScore\(\) \{(?<body>.*?)^  \}',
        multiLine: true,
        dotAll: true,
      ).firstMatch(source)?.namedGroup('body');

      expect(resetBody, isNotNull);
      expect(resetBody, contains('_refContour.clear();'));
      expect(resetBody, contains('_prevRefMidi = 0;'));
      expect(resetBody, contains('_prevRefPitch = 0;'));
    });
  });
}
