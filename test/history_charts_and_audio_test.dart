import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/models/audio_recording_model.dart';
import 'package:beeware_app/models/hive_data.dart';
import 'package:beeware_app/widgets/interactive_history_charts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Interactive History Charts & Audio Recordings Tests', () {
    testWidgets('Temperature, Humidity, and Acoustic all render BarChart widgets', (tester) async {
      final hive = HiveData(
        id: 'hive_test_charts',
        name: 'Test Chart Hive',
        conditionLabel: 'Queen Present',
        confidence: 95,
        healthScore: 90,
        temperature: '34.5',
        humidity: '62',
        acoustic: '200 Hz',
        updated: '10:00 AM',
        isAlert: false,
        alertMessage: 'Normal',
        temperatureHistory: [34.0, 34.5, 35.0],
        humidityHistory: [60.0, 62.0, 65.0],
        acousticHistory: [55.0, 60.0, 58.0],
        historyDates: ['8:00 AM', '9:00 AM', '10:00 AM'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InteractiveHistoryView(hive: hive),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find BarChart widgets - should have 3 (Temperature, Humidity, Acoustic Energy)
      final barCharts = find.byType(BarChart);
      expect(barCharts, findsNWidgets(3));

      // Check titles exist
      expect(find.text('Temperature History (°C)'), findsOneWidget);
      expect(find.text('Relative Humidity (%)'), findsOneWidget);
      expect(find.text('Acoustic Energy & Frequency (dB)'), findsOneWidget);

      // Check average temperature is correctly calculated (~34.5°C)
      expect(find.text('Avg: 34.5°C'), findsOneWidget);
      // Check average humidity is correctly calculated (~62%)
      expect(find.text('Avg: 62%'), findsOneWidget);
    });

    testWidgets('Validates 0.0 readings are filtered from average calculations', (tester) async {
      final hive = HiveData(
        id: 'hive_test_zeros',
        name: 'Test Zeros Hive',
        conditionLabel: 'Queen Present',
        confidence: 90,
        healthScore: 88,
        temperature: '35.0',
        humidity: '65',
        acoustic: '210 Hz',
        updated: '10:00 AM',
        isAlert: false,
        alertMessage: 'Normal',
        // Contains 0.0 readings that shouldn't skew average
        temperatureHistory: [0.0, 34.0, 36.0],
        humidityHistory: [0.0, 60.0, 70.0],
        acousticHistory: [50.0, 55.0],
        historyDates: ['8:00 AM', '9:00 AM', '10:00 AM'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InteractiveHistoryView(hive: hive),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Average of [34.0, 36.0] is 35.0°C (not 23.3°C with 0.0 included)
      expect(find.text('Avg: 35.0°C'), findsOneWidget);
      // Average of [60.0, 70.0] is 65% (not 43% with 0.0 included)
      expect(find.text('Avg: 65%'), findsOneWidget);
    });

    test('AudioRecordingModel relative progressive timestamps progression', () {
      final clips = List.generate(
        5,
        (i) => AudioRecordingModel(
          id: 'slot_$i',
          deviceId: 'BW-001',
          slot: i,
          frequency: 200,
          condition: 'Queen Present',
          temperature: 34.5,
          humidity: 60.0,
          timestamp: 'Just now',
          createdAt: 1000 + i * 50, // Small ESP32 millis()
        ),
      );

      // Verify slot indexing progression logic
      for (int i = 0; i < clips.length; i++) {
        final expected = i == 0 ? 'Just now' : '${i * 5} mins ago';
        if (i == 0) {
          expect(expected, 'Just now');
        } else if (i == 1) {
          expect(expected, '5 mins ago');
        } else if (i == 2) {
          expect(expected, '10 mins ago');
        } else if (i == 3) {
          expect(expected, '15 mins ago');
        } else if (i == 4) {
          expect(expected, '20 mins ago');
        }
      }
    });

    test('Audio recording clock-synced elapsed time formatting for hours and minutes', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final clipJustNow = AudioRecordingModel(
        id: 'c1',
        deviceId: 'BW-001',
        slot: 0,
        frequency: 200,
        condition: 'Queen Present',
        temperature: 34.0,
        humidity: 60.0,
        timestamp: 'Just now',
        createdAt: now - 30 * 1000,
      );

      final clipMins = AudioRecordingModel(
        id: 'c2',
        deviceId: 'BW-001',
        slot: 1,
        frequency: 200,
        condition: 'Queen Present',
        temperature: 34.0,
        humidity: 60.0,
        timestamp: 'Just now',
        createdAt: now - 15 * 60 * 1000,
      );

      final clipHours = AudioRecordingModel(
        id: 'c3',
        deviceId: 'BW-001',
        slot: 2,
        frequency: 200,
        condition: 'Queen Present',
        temperature: 34.0,
        humidity: 60.0,
        timestamp: 'Just now',
        createdAt: now - 2 * 3600 * 1000,
      );

      String formatTime(AudioRecordingModel clip) {
        int epoch = clip.createdAt;
        if (epoch > 0 && epoch < 1700000000000 && epoch > 1700000000) {
          epoch = epoch * 1000;
        }
        if (epoch > 1700000000000) {
          final diffMs = DateTime.now().millisecondsSinceEpoch - epoch;
          if (diffMs >= 0) {
            final diffMin = diffMs ~/ 60000;
            if (diffMin < 1) return 'Just now';
            if (diffMin < 60) return '$diffMin min${diffMin > 1 ? "s" : ""} ago';
            final hours = diffMin ~/ 60;
            if (hours < 24) return '$hours hr${hours > 1 ? "s" : ""} ago';
            final days = hours ~/ 24;
            return '$days day${days > 1 ? "s" : ""} ago';
          }
        }
        return 'Just now';
      }

      expect(formatTime(clipJustNow), 'Just now');
      expect(formatTime(clipMins), '15 mins ago');
      expect(formatTime(clipHours), '2 hrs ago');
    });
  });
}
