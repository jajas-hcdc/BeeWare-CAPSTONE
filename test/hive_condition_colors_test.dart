import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/models/hive_data.dart';
import 'package:beeware_app/screens/hive_detail_screen.dart';
import 'package:beeware_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder conditionRowFinder(String text) {
    return find.byWidgetPredicate(
      (w) => w is Text && w.data == text && w.style?.fontSize == 13,
    );
  }

  group('HiveDetailScreen Condition Colors Tests', () {
    testWidgets('Queen Present active displays green dot and detected text, greys out inactive', (tester) async {
      final hive = HiveData(
        id: 'hive_test_present',
        name: 'Test Present Hive',
        conditionLabel: 'Queen Present',
        confidence: 94,
        healthScore: 92,
        temperature: '34.5',
        humidity: '60',
        acoustic: '240 Hz',
        updated: 'Just now',
        queenPresentDetected: true,
        queenAbsentDetected: false,
        queenAcceptedDetected: false,
        queenRejectedDetected: false,
        isAlert: false,
        alertMessage: 'Normal',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HiveDetailScreen(hive: hive, initialTab: 2),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the "Queen Present" condition row text
      final queenPresentFinder = conditionRowFinder('Queen Present');
      expect(queenPresentFinder, findsOneWidget);

      final Text presentTextWidget = tester.widget(queenPresentFinder);
      expect(presentTextWidget.style?.color, Colors.black);
      expect(presentTextWidget.style?.fontWeight, FontWeight.w800);

      // Find the "Queen Absent" condition row text - should be greyed out
      final queenAbsentFinder = conditionRowFinder('Queen Absent');
      expect(queenAbsentFinder, findsOneWidget);

      final Text absentTextWidget = tester.widget(queenAbsentFinder);
      expect(absentTextWidget.style?.color, Colors.grey.shade600);
      expect(absentTextWidget.style?.fontWeight, FontWeight.w600);

      // Verify "Detected" status is present and colored green
      final detectedFinder = find.text('Detected');
      expect(detectedFinder, findsOneWidget);

      final Text detectedTextWidget = tester.widget(detectedFinder);
      expect(detectedTextWidget.style?.color, AppColors.queenPresentGreen);

      // Verify "Not\nDetected" statuses are grey
      final notDetectedFinder = find.text('Not\nDetected');
      expect(notDetectedFinder, findsNWidgets(3));

      final Text notDetectedWidget = tester.widget(notDetectedFinder.first);
      expect(notDetectedWidget.style?.color, Colors.grey.shade500);

      // Verify dot indicators
      final containers = tester.widgetList<Container>(find.byType(Container));
      final dotContainers = containers.where((c) {
        final box = c.decoration as BoxDecoration?;
        return box?.shape == BoxShape.circle && c.constraints?.maxWidth == 10;
      }).toList();

      // We expect 4 condition dots
      expect(dotContainers.length, 5);
      final presentDot = dotContainers[0].decoration as BoxDecoration;
      expect(presentDot.color, AppColors.queenPresentGreen);

      final absentDot = dotContainers[1].decoration as BoxDecoration;
      expect(absentDot.color, Colors.grey.shade400);
    });

    testWidgets('Queen Absent active displays red dot and detected text, greys out inactive', (tester) async {
      final hive = HiveData(
        id: 'hive_test_absent',
        name: 'Test Absent Hive',
        conditionLabel: 'Queen Absent',
        confidence: 88,
        healthScore: 40,
        temperature: '31.0',
        humidity: '50',
        acoustic: '380 Hz',
        updated: 'Just now',
        queenPresentDetected: false,
        queenAbsentDetected: true,
        queenAcceptedDetected: false,
        queenRejectedDetected: false,
        isAlert: true,
        alertSeverity: 'Critical',
        alertLabel: 'Queen Loss',
        alertMessage: 'Queen Absent Detected',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HiveDetailScreen(hive: hive, initialTab: 2),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find "Queen Absent" - should be black & bold
      final queenAbsentFinder = conditionRowFinder('Queen Absent');
      expect(queenAbsentFinder, findsOneWidget);
      final Text absentTextWidget = tester.widget(queenAbsentFinder);
      expect(absentTextWidget.style?.color, Colors.black);
      expect(absentTextWidget.style?.fontWeight, FontWeight.w800);

      // Find "Queen Present" - should be greyed out
      final queenPresentFinder = conditionRowFinder('Queen Present');
      expect(queenPresentFinder, findsOneWidget);
      final Text presentTextWidget = tester.widget(queenPresentFinder);
      expect(presentTextWidget.style?.color, Colors.grey.shade600);

      // Verify "Detected" is red
      final detectedFinder = find.text('Detected');
      expect(detectedFinder, findsOneWidget);
      final Text detectedTextWidget = tester.widget(detectedFinder);
      expect(detectedTextWidget.style?.color, AppColors.queenAbsentRed);

      // Verify dot indicators
      final containers = tester.widgetList<Container>(find.byType(Container));
      final dotContainers = containers.where((c) {
        final box = c.decoration as BoxDecoration?;
        return box?.shape == BoxShape.circle && c.constraints?.maxWidth == 10;
      }).toList();

      expect(dotContainers.length, 5);
      final presentDot = dotContainers[0].decoration as BoxDecoration;
      expect(presentDot.color, Colors.grey.shade400);

      final absentDot = dotContainers[1].decoration as BoxDecoration;
      expect(absentDot.color, AppColors.queenAbsentRed);
    });
  });
}

