import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_preset.dart';
import '../../core/constants.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(audioPresetProvider);
    final effect = ref.watch(audioEffectProvider);
    final pitchShift = ref.watch(pitchShiftProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Audio Input', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...AudioPreset.values.map((p) => _PresetTile(
                preset: p,
                selected: p == preset,
                onTap: () =>
                    ref.read(audioPresetProvider.notifier).state = p,
              )),

          const SizedBox(height: 32),
          Text('Effects', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<AudioEffect>(
            segments: AudioEffect.values
                .map((e) => ButtonSegment(value: e, label: Text(e.label)))
                .toList(),
            selected: {effect},
            onSelectionChanged: (s) =>
                ref.read(audioEffectProvider.notifier).state = s.first,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return kPrimaryColor;
                }
                return kSurfaceDark;
              }),
            ),
          ),

          const SizedBox(height: 32),
          Text('Pitch Shift', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${pitchShift > 0 ? '+' : ''}$pitchShift',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: kAccentGlow,
                ),
              ),
              const SizedBox(width: 8),
              const Text('semitones', style: TextStyle(color: Colors.white54)),
            ],
          ),
          Slider(
            value: pitchShift.toDouble(),
            min: kPitchShiftMin.toDouble(),
            max: kPitchShiftMax.toDouble(),
            divisions: kPitchShiftMax - kPitchShiftMin,
            label: '${pitchShift > 0 ? '+' : ''}$pitchShift',
            onChanged: (v) =>
                ref.read(pitchShiftProvider.notifier).state = v.round(),
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AudioPreset preset;
  final bool selected;
  final VoidCallback onTap;

  IconData get _iconData {
    return switch (preset) {
      AudioPreset.externalMic => Icons.mic_external_on,
      AudioPreset.roomMic => Icons.phone_android,
      AudioPreset.partyMode => Icons.celebration,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? kPrimaryColor.withAlpha(60) : kSurfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? const BorderSide(color: kPrimaryColor, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(_iconData, color: selected ? kAccentGlow : Colors.white54),
        title: Text(preset.label),
        subtitle: Text(preset.description),
        onTap: onTap,
        trailing: selected
            ? const Icon(Icons.check_circle, color: kAccentGlow)
            : null,
      ),
    );
  }
}
