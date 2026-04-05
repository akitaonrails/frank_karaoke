import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../state/providers.dart';
import '../widgets/big_button.dart';

class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = ref.watch(participantsProvider);
    final sessionActive = ref.watch(sessionActiveProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tonight\'s Singers',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                if (sessionActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(40),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green, width: 1),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            Expanded(
              child: participants.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_add, size: 80,
                              color: kPrimaryColor.withAlpha(128)),
                          const SizedBox(height: 16),
                          Text('Add singers to start tracking scores',
                              style: Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: participants.length,
                      itemBuilder: (context, index) {
                        final name = participants[index];
                        return Card(
                          color: kSurfaceDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _colorForIndex(index),
                              child: Text(
                                name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(name, style: const TextStyle(fontSize: 18)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () {
                                ref.read(participantsProvider.notifier)
                                    .update((state) => [...state]..removeAt(index));
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),

            BigButton(
              label: 'Add Singer',
              icon: Icons.person_add,
              onPressed: () => _showAddSingerDialog(context, ref),
            ),
            const SizedBox(height: 12),
            BigButton(
              label: sessionActive ? 'End Session' : 'Start Session',
              icon: sessionActive ? Icons.stop : Icons.play_arrow,
              color: sessionActive ? Colors.red : kSecondaryColor,
              onPressed: participants.isEmpty
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Add at least one singer first')),
                      );
                    }
                  : () {
                      ref.read(sessionActiveProvider.notifier).state = !sessionActive;
                      if (!sessionActive) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Session started! Go sing!')),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSingerDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kSurfaceDark,
        title: const Text('Add Singer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref.read(participantsProvider.notifier)
                  .update((state) => [...state, value.trim()]);
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(participantsProvider.notifier)
                    .update((state) => [...state, name]);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Color _colorForIndex(int index) {
    const colors = [
      kPrimaryColor, kSecondaryColor, kAccentGlow,
      Colors.orange, Colors.teal, Colors.amber,
      Colors.indigo, Colors.pink,
    ];
    return colors[index % colors.length];
  }
}
