import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/ui/widgets/big_button.dart';

void main() {
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
