import 'constants.dart';

enum AudioPreset {
  externalMic(
    label: 'External Mic',
    description: 'Bluetooth or wired mic connected to device',
    icon: 'mic_external_on',
    pitchTolerance: kExternalMicTolerance,
    noiseGateThreshold: 0.001,
    useSpectralSubtraction: false,
  ),
  roomMic(
    label: 'Room Mic',
    description: 'Built-in device microphone',
    icon: 'phone_android',
    pitchTolerance: kRoomMicTolerance,
    noiseGateThreshold: 0.003,
    useSpectralSubtraction: true,
  ),
  partyMode(
    label: 'Party Mode',
    description: 'Noisy environment, scoring for fun',
    icon: 'celebration',
    pitchTolerance: kPartyModeTolerance,
    noiseGateThreshold: 0.008,
    useSpectralSubtraction: true,
  );

  const AudioPreset({
    required this.label,
    required this.description,
    required this.icon,
    required this.pitchTolerance,
    required this.noiseGateThreshold,
    required this.useSpectralSubtraction,
  });

  final String label;
  final String description;
  final String icon;
  final double pitchTolerance;
  final double noiseGateThreshold;
  final bool useSpectralSubtraction;
}

