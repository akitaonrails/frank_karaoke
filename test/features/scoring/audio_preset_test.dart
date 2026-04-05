import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/core/audio_preset.dart';

void main() {
  group('AudioPreset', () {
    test('all presets have positive pitch tolerance', () {
      for (final preset in AudioPreset.values) {
        expect(preset.pitchTolerance, greaterThan(0));
      }
    });

    test('external mic has strictest tolerance', () {
      expect(
        AudioPreset.externalMic.pitchTolerance,
        lessThan(AudioPreset.roomMic.pitchTolerance),
      );
      expect(
        AudioPreset.roomMic.pitchTolerance,
        lessThan(AudioPreset.partyMode.pitchTolerance),
      );
    });

    test('room mic and party mode use spectral subtraction', () {
      expect(AudioPreset.roomMic.useSpectralSubtraction, true);
      expect(AudioPreset.partyMode.useSpectralSubtraction, true);
    });

    test('external mic does not use spectral subtraction', () {
      expect(AudioPreset.externalMic.useSpectralSubtraction, false);
    });

    test('noisier presets have higher noise gate thresholds', () {
      expect(
        AudioPreset.externalMic.noiseGateThreshold,
        lessThan(AudioPreset.roomMic.noiseGateThreshold),
      );
      expect(
        AudioPreset.roomMic.noiseGateThreshold,
        lessThan(AudioPreset.partyMode.noiseGateThreshold),
      );
    });
  });

  group('AudioEffect', () {
    test('has three options', () {
      expect(AudioEffect.values.length, 3);
    });

    test('all effects have labels', () {
      for (final effect in AudioEffect.values) {
        expect(effect.label, isNotEmpty);
      }
    });
  });
}
