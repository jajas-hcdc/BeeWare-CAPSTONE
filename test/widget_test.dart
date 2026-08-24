import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/screens/home_screen.dart';
import 'package:beeware_app/screens/alerts_screen.dart';

void main() {
  testWidgets('HomeScreen smoke test renders brand and sections', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeScreen()));

    expect(find.text('BEEWARE'), findsWidgets);
    expect(find.textContaining('Beekeeper'), findsOneWidget);
    expect(find.text('Hive Condition Summary'), findsOneWidget);
    expect(find.text('AI Colony Health Assessment'), findsOneWidget);
  });

  testWidgets('HomeScreen contains pull-to-refresh RefreshIndicator', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('AlertsScreen contains slideable PageView', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AlertsScreen()));

    expect(find.byType(PageView), findsOneWidget);
  });
}
