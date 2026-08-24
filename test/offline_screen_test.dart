import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/screens/offline_screen.dart';
import 'package:beeware_app/services/connectivity_service.dart';

void main() {
  group('Connectivity & Offline Screen Tests', () {
    test('ConnectivityService formatting works correctly', () {
      final service = ConnectivityService();
      expect(service.lastSyncedFormatted, isNotEmpty);
      service.recordSyncEvent();
      expect(service.lastSyncedFormatted, equals('Just now'));
    });

    testWidgets('OfflineScreen renders cloud icon, title, and Reconnect button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OfflineScreen(),
        ),
      );

      // Verify UI elements
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.text('You are offline'), findsOneWidget);
      expect(find.text('Unable to fetch data.'), findsOneWidget);
      expect(find.textContaining('Last Synced:'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });
}
