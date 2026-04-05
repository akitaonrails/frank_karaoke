import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/core/scoring_mode.dart';

void main() {
  group('ScoringMode', () {
    test('has exactly 4 modes', () {
      expect(ScoringMode.values.length, 4);
    });

    test('all modes have non-empty labels', () {
      for (final mode in ScoringMode.values) {
        expect(mode.label, isNotEmpty);
      }
    });

    test('all modes have non-empty descriptions', () {
      for (final mode in ScoringMode.values) {
        expect(mode.description, isNotEmpty);
      }
    });

    test('all modes have icons', () {
      for (final mode in ScoringMode.values) {
        expect(mode.icon, isNotEmpty);
      }
    });

    test('mode names are valid for serialization', () {
      for (final mode in ScoringMode.values) {
        // Verify name can be used for persistence.
        expect(mode.name, matches(RegExp(r'^[a-zA-Z]+$')));
        // Verify round-trip.
        final found = ScoringMode.values.where((m) => m.name == mode.name);
        expect(found.length, 1);
      }
    });
  });
}
