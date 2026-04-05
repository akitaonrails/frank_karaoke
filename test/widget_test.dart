import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/ui/screens/settings_screen.dart';
import 'package:frank_karaoke/ui/widgets/big_button.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('renders audio presets', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Audio Input'), findsOneWidget);
      expect(find.text('External Mic'), findsOneWidget);
      expect(find.text('Room Mic'), findsOneWidget);
      expect(find.text('Party Mode'), findsOneWidget);
      expect(find.text('Effects'), findsOneWidget);
      expect(find.text('Pitch Shift'), findsOneWidget);
    });

    testWidgets('can select audio preset', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Party Mode'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('BigButton', () {
    testWidgets('renders label and handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BigButton(
              label: 'Test',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Test'), findsOneWidget);
      await tester.tap(find.text('Test'));
      expect(tapped, true);
    });

    testWidgets('renders with icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BigButton(
              label: 'With Icon',
              icon: Icons.play_arrow,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.text('With Icon'), findsOneWidget);
    });
  });
}
