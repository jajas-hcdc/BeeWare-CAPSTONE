import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/models/hive_data.dart';
import 'package:beeware_app/services/alert_service.dart';
import 'package:beeware_app/services/hive_service.dart';
import 'package:beeware_app/widgets/sensor_visualizers.dart';
import 'package:beeware_app/screens/hive_detail_screen.dart';
import 'package:beeware_app/screens/hives_screen.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Acoustic Signal Hz & Missing Sensor Alerts Tests', () {
    late HiveService hiveService;
    late AlertService alertService;

    setUp(() {
      hiveService = HiveService();
      alertService = AlertService();
    });

    test('updateFromBackendTelemetry updates acoustic to Hz format when frequency > 0', () {
      final testHive = HiveData(
        id: 'test_node_hz_1',
        name: 'Hz Test Hive',
        deviceId: 'BW-HZ-001',
        conditionLabel: 'Queen Present',
        confidence: 95,
        healthScore: 92,
        temperature: '34.5',
        humidity: '60',
        acoustic: '0 Hz',
        acousticStatus: 'Connecting',
        updated: 'Just now',
        isAlert: false,
        alertLabel: 'Normal',
        alertMessage: 'Active',
      );
      hiveService.addHive(testHive);

      // Ingest telemetry with frequency = 245 Hz
      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-HZ-001',
          'temperature': 34.8,
          'humidity': 62.0,
          'battery_level': 90,
          'wifi_rssi': -62,
          'frequency': 245,
          'frequency_hz': 245,
        }
      ]);

      final updated = hiveService.getHiveById('test_node_hz_1');
      expect(updated, isNotNull);
      expect(updated?.acoustic, '245 Hz');
      expect(updated?.acousticStatus, 'Normal');
    });

    test('updateFromBackendTelemetry sets 0 Hz and Not Detected when frequency is 0', () {
      final testHive = HiveData(
        id: 'test_node_hz_zero',
        name: 'Zero Hz Hive',
        deviceId: 'BW-HZ-ZERO',
        conditionLabel: 'Queen Present',
        confidence: 90,
        healthScore: 85,
        temperature: '34.0',
        humidity: '58',
        acoustic: '200 Hz',
        acousticStatus: 'Normal',
        updated: 'Just now',
        isAlert: false,
        alertLabel: 'Normal',
        alertMessage: 'Active',
      );
      hiveService.addHive(testHive);

      // Ingest telemetry with frequency = 0 (disconnected or silent)
      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-HZ-ZERO',
          'temperature': 34.0,
          'humidity': 58.0,
          'battery_level': 88,
          'wifi_rssi': -65,
          'frequency': 0,
          'frequency_hz': 0,
        }
      ]);

      final updated = hiveService.getHiveById('test_node_hz_zero');
      expect(updated, isNotNull);
      expect(updated?.acoustic, '0 Hz');
      expect(updated?.acousticStatus, 'Not Detected (0 Hz)');
    });

    test('AlertService automatically generates notifications when sensors return 0 or are not detected', () {
      final missingSensorsHive = HiveData(
        id: 'hive_missing_all',
        name: 'Disconnected Sensors Hive',
        deviceId: 'BW-DISCONNECT',
        conditionLabel: 'Queen Present',
        confidence: 50,
        healthScore: 40,
        temperature: '0.0', // Temperature not detected
        humidity: '0',     // Humidity not detected
        acoustic: '0 Hz',  // Acoustic signal not detected
        acousticStatus: 'Not Detected (0 Hz)',
        updated: 'Just now',
        isAlert: false,
        alertLabel: 'Normal',
        alertMessage: 'Sensors missing',
      );
      hiveService.addHive(missingSensorsHive);

      // Trigger alerts computation
      alertService.refreshFromCloud();

      final alerts = alertService.alerts;

      // 1. Verify Temperature not detected alert
      final tempAlert = alerts.firstWhere(
        (a) => a.id.contains('sensor_temp_not_detected_hive_missing_all'),
        orElse: () => throw Exception('Temperature missing alert not found'),
      );
      expect(tempAlert.title, contains('Temperature Sensor Not Detected'));
      expect(tempAlert.severity, 'Critical');
      expect(tempAlert.recommendation, contains('GPIO 4'));

      // 2. Verify Humidity not detected alert
      final humAlert = alerts.firstWhere(
        (a) => a.id.contains('sensor_hum_not_detected_hive_missing_all'),
        orElse: () => throw Exception('Humidity missing alert not found'),
      );
      expect(humAlert.title, contains('Humidity Sensor Not Detected'));
      expect(humAlert.severity, 'Warning');
      expect(humAlert.recommendation, contains('GPIO 4'));

      // 3. Verify Acoustic Signal not detected alert
      final acousticAlert = alerts.firstWhere(
        (a) => a.id.contains('sensor_acoustic_not_detected_hive_missing_all'),
        orElse: () => throw Exception('Acoustic missing alert not found'),
      );
      expect(acousticAlert.title, contains('Acoustic Signal Not Detected (0 Hz)'));
      expect(acousticAlert.severity, 'Critical');
      expect(acousticAlert.recommendation, contains('INMP441'));
    });

    testWidgets('AcousticSignalVisualizer renders 0 Hz Not Detected state cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AcousticSignalVisualizer(
              conditionLabel: 'Queen Present',
              acousticStatus: 'Not Detected (0 Hz)',
              acoustic: '0 Hz',
            ),
          ),
        ),
      );

      expect(find.text('0 Hz • Not Detected'), findsOneWidget);
    });

    testWidgets('HiveDetailScreen sets gauge to 0%, removes Queen Present, and displays No Buzz Detected when acoustic is 0 Hz', (tester) async {
      final silentHive = HiveData(
        id: 'silent_hive_test_zero',
        name: 'Silent Test Hive',
        deviceId: 'BW-SILENT-0',
        conditionLabel: 'Queen Present',
        confidence: 90,
        healthScore: 90,
        temperature: '32.0',
        humidity: '65',
        acoustic: '0 Hz',
        acousticStatus: 'Not Detected (0 Hz)',
        updated: 'Just now',
        isAlert: false,
        alertLabel: 'Normal',
        alertMessage: 'Active',
      );

      // Test Overview tab (initialTab: 0)
      await tester.pumpWidget(
        MaterialApp(
          home: HiveDetailScreen(hive: silentHive, initialTab: 0),
        ),
      );
      await tester.pump();

      // CircularGauge must show 0%
      expect(find.text('0%'), findsOneWidget);

      // Title must say "No Buzz Detected" and NOT "Queen Present • No Buzz" or "Queen Present"
      expect(find.text('No Buzz Detected'), findsWidgets);
      expect(find.text('Queen Present • No Buzz'), findsNothing);

      // Confidence must show 0%
      expect(find.text('Confidence: 0%'), findsOneWidget);

      // Red badge
      expect(find.text('No Buzz Detected (0 Hz)'), findsOneWidget);
    });

    testWidgets('HiveDetailScreen greys out conditions and shows separated acoustic card when 0 Hz in AI Analysis tab', (tester) async {
      final silentHive = HiveData(
        id: 'silent_hive_test_tab2',
        name: 'Silent Test Hive',
        deviceId: 'BW-SILENT-2',
        conditionLabel: 'Queen Present',
        confidence: 90,
        healthScore: 90,
        temperature: '32.0',
        humidity: '65',
        acoustic: '0 Hz',
        acousticStatus: 'Not Detected (0 Hz)',
        updated: 'Just now',
        isAlert: false,
        alertLabel: 'Normal',
        alertMessage: 'Active',
      );

      // Test AI analysis tab (initialTab: 2)
      await tester.pumpWidget(
        MaterialApp(
          home: HiveDetailScreen(hive: silentHive, initialTab: 2),
        ),
      );
      await tester.pump();

      // Check for the "Offline / Inactive" badge in Detected Colony Conditions
      expect(find.text('Offline / Inactive'), findsOneWidget);

      // Check for separated Colony Acoustic Buzz row showing No Buzz Detected
      expect(find.text('Colony Acoustic Buzz'), findsOneWidget);
      expect(find.text('No Buzz\nDetected'), findsOneWidget);

      // Badge in AI Analysis tab shows No Buzz Detected
      expect(find.text('No Buzz Detected'), findsOneWidget);
      expect(find.text('Queen Present • No Buzz'), findsNothing);
    });

    testWidgets('HivesScreen displays No Buzz Detected and 0% confidence on hive card when acoustic is 0 Hz', (tester) async {
      hiveService.addHive(
        HiveData(
          id: 'silent_hive_hives_screen',
          name: 'Silent Hives Screen Hive',
          deviceId: 'BW-SILENT-HS',
          conditionLabel: 'Queen Present',
          confidence: 90,
          healthScore: 90,
          temperature: '32.0',
          humidity: '65',
          acoustic: '0 Hz',
          acousticStatus: 'Not Detected (0 Hz)',
          updated: 'Just now',
          isAlert: false,
          alertLabel: 'Normal',
          alertMessage: 'Active',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: HivesScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('No Buzz Detected'), findsWidgets);
      expect(find.text('0%'), findsWidgets);
    });
  });
}
