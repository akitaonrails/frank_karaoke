import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../widgets/big_button.dart';

class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tonight\'s Singers',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),

            // Placeholder for participant list (Phase 4)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.group_add,
                      size: 80,
                      color: kPrimaryColor.withAlpha(128),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Add singers to start tracking scores',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),

            BigButton(
              label: 'Add Singer',
              icon: Icons.person_add,
              onPressed: () {
                // Phase 4: participant management
              },
            ),
            const SizedBox(height: 12),
            BigButton(
              label: 'Start New Session',
              icon: Icons.play_arrow,
              color: kSecondaryColor,
              onPressed: () {
                // Phase 4: session creation
              },
            ),
          ],
        ),
      ),
    );
  }
}
