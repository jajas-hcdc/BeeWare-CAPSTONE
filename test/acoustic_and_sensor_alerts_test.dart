import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/models/hive_data.dart';
import 'package:beeware_app/services/alert_service.dart';
import 'package:beeware_app/services/audio_processor.dart';
import 'package:beeware_app/services/hive_service.dart';
import 'package:beeware_app/services/notification_service.dart';
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

    test('updateFromBackendTelemetry does not add stale/unplugged node to unpairedNodes', () {
      hiveService.clearDiscoveredNodes();
      final staleEpoch = DateTime.now().subtract(const Duration(minutes: 25)).millisecondsSinceEpoch;

      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-UNPLUGGED-99',
          'temperature': 28.3,
          'humidity': 77.0,
          'frequency': 86,
          'power_source': 'Plugged In',
          'last_audio_epoch': staleEpoch,
          'timestamp': '01:43:04 AM',
        }
      ]);

      expect(hiveService.unpairedNodes.any((n) => n.deviceId == 'BW-UNPLUGGED-99'), isFalse);
    });

    test('updateFromBackendTelemetry adds actively transmitting node to unpairedNodes and clears on empty', () {
      hiveService.clearDiscoveredNodes();
      final liveEpoch = DateTime.now().subtract(const Duration(seconds: 45)).millisecondsSinceEpoch;

      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-LIVE-101',
          'temperature': 34.2,
          'humidity': 65.0,
          'frequency': 185,
          'power_source': 'Plugged In',
          'last_audio_epoch': liveEpoch,
          'timestamp': 'Just now',
        }
      ]);

      expect(hiveService.unpairedNodes.any((n) => n.deviceId == 'BW-LIVE-101'), isTrue);

      // When telemetry is refreshed and empty (e.g., deleted in Firebase or device offline), unpairedNodes clears
      hiveService.updateFromBackendTelemetry([]);
      expect(hiveService.unpairedNodes.isEmpty, isTrue);
    });

    test('Only one notification is dispatched per device anomaly without duplicate 0 Hz alerts', () async {
      final triggered = <String>[];
      final sub = alertService.onAlertTriggered.listen((a) => triggered.add(a.id));

      final liveEpoch = DateTime.now().subtract(const Duration(seconds: 20)).millisecondsSinceEpoch;
      hiveService.addHive(
        HiveData(
          id: 'hive_bw_08266c',
          name: 'Hive BW-08266C',
          deviceId: 'BW-08266C',
          conditionLabel: 'Queen Present',
          confidence: 0,
          healthScore: 30,
          temperature: '34.2',
          humidity: '60',
          acoustic: '0 Hz',
          acousticStatus: 'Not Detected (0 Hz)',
          updated: 'Just now',
          isAlert: true,
          alertSeverity: 'Critical',
          alertLabel: '⚠️ Acoustic Signal Not Detected (0 Hz)',
          alertMessage: 'Acoustic microphone on Hive BW-08266C is detecting 0 Hz (silent or disconnected).',
          lastAudioCreatedAt: liveEpoch,
        ),
      );

      alertService.refreshFromCloud();
      alertService.refreshFromCloud();
      await Future.delayed(Duration.zero);

      // Should not create duplicate hive_alert_hive_bw_08266c alongside sensor_acoustic_not_detected_hive_bw_08266c
      final bwAlerts = alertService.alerts.where((a) => a.hiveId == 'Hive BW-08266C').toList();
      expect(bwAlerts.length, 1);
      expect(triggered.length, 1);

      // NotificationService recognizes both local 0 Hz alert and cloud SENSOR ALERT as same device + category
      final key1 = NotificationService.extractDeviceKey(
        payload: 'BW-08266C',
        title: '⚠️ Acoustic Signal Not Detected (0 Hz)',
        body: 'Acoustic microphone on Hive BW-08266C is detecting 0 Hz.',
      );
      final key2 = NotificationService.extractDeviceKey(
        payload: null,
        title: '⚠️ SENSOR ALERT: BW-08266C',
        body: 'Sensor(s) not detected: Acoustics (0 Hz). Please inspect node wiring.',
      );
      expect(key1, 'BW-08266C');
      expect(key2, 'BW-08266C');

      final cat1 = NotificationService.classifyAnomalyCategory(
        '⚠️ Acoustic Signal Not Detected (0 Hz)',
        'Acoustic microphone on Hive BW-08266C is detecting 0 Hz.',
      );
      final cat2 = NotificationService.classifyAnomalyCategory(
        '⚠️ SENSOR ALERT: BW-08266C',
        'Sensor(s) not detected: Acoustics (0 Hz). Please inspect node wiring.',
      );
      expect(cat1, 'sensor_not_detected');
      expect(cat2, 'sensor_not_detected');

      // Simulate repeated Home screen pull-to-refresh cycles while the anomaly remains active
      for (int i = 0; i < 3; i++) {
        await hiveService.refreshFromCloud();
        hiveService.updateFromBackendTelemetry([
          {
            'device_id': 'BW-08266C',
            'temperature': 34.2,
            'humidity': 60.0,
            'frequency': 0,
            'frequency_hz': 0,
            'last_audio_epoch': DateTime.now().millisecondsSinceEpoch,
            'timestamp': 'Just now',
          }
        ]);
        await alertService.refreshFromCloud();
      }
      await Future.delayed(const Duration(milliseconds: 100));

      // Must still have dispatched only 1 notification total across all refreshes
      expect(triggered.length, 1);

      await sub.cancel();
    });

    test('AudioProcessor extracts 128x128x1 mel-spectrogram from WAV bytes and HiveService applies TFLite prediction', () async {
      // Build a minimal valid 44-byte RIFF WAV header + 4096 bytes of 16-bit PCM samples
      const int pcmLen = 4096;
      final wav = Uint8List(44 + pcmLen);
      final view = ByteData.view(wav.buffer);
      wav[0] = 0x52; wav[1] = 0x49; wav[2] = 0x46; wav[3] = 0x46; // "RIFF"
      view.setUint32(4, 36 + pcmLen, Endian.little);
      wav[8] = 0x57; wav[9] = 0x41; wav[10] = 0x56; wav[11] = 0x45; // "WAVE"
      wav[12] = 0x66; wav[13] = 0x6D; wav[14] = 0x74; wav[15] = 0x20; // "fmt "
      view.setUint32(16, 16, Endian.little);
      view.setUint16(20, 1, Endian.little); // PCM
      view.setUint16(22, 1, Endian.little); // 1 channel
      view.setUint32(24, 16000, Endian.little);
      view.setUint32(28, 32000, Endian.little);
      view.setUint16(32, 2, Endian.little);
      view.setUint16(34, 16, Endian.little);
      wav[36] = 0x64; wav[37] = 0x61; wav[38] = 0x74; wav[39] = 0x61; // "data"
      view.setUint32(40, pcmLen, Endian.little);

      final tensor = await AudioProcessor.extractMelSpectrogramFromBytes(wav);
      expect(tensor.length, 128);
      expect(tensor.first.length, 128);
      expect(tensor.first.first.length, 1);

      // Verify HiveService applies TFLite prediction and retains it across telemetry polls
      final epochNow = DateTime.now().millisecondsSinceEpoch;
      hiveService.addHive(
        HiveData(
          id: 'hive_ai_test',
          name: 'AI Test Hive',
          deviceId: 'BW-AI-TEST',
          conditionLabel: 'Queen Present',
          confidence: 90,
          healthScore: 90,
          temperature: '34.0',
          humidity: '60',
          acoustic: '195 Hz',
          acousticStatus: 'Normal',
          updated: 'Just now',
          isAlert: false,
          alertLabel: 'Normal',
          alertMessage: 'Active',
          lastAudioCreatedAt: epochNow,
        ),
      );

      hiveService.applyAiModelPrediction(
        deviceId: 'BW-AI-TEST',
        recordingEpoch: epochNow,
        prediction: 'Queen Accepted',
        confidence: 93,
        frequencyHz: 195,
      );

      final afterAi = hiveService.getHiveById('hive_ai_test');
      expect(afterAi?.conditionLabel, 'Queen Accepted');
      expect(afterAi?.confidence, 93);
      expect(afterAi?.queenAcceptedDetected, isTrue);
      expect(afterAi?.explanation, contains('TFLite Model'));

      // Verify that frequencies in Mel Bands 0-3 (0-89 Hz) classify as No Buzz Detected
      // while preserving and displaying the received Hz value
      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-AI-TEST',
          'temperature': 34.0,
          'humidity': 60.0,
          'frequency': 65,
          'frequency_hz': 65,
        }
      ]);
      final lowRumble = hiveService.getHiveById('hive_ai_test')!;
      expect(lowRumble.conditionLabel, 'No Buzz Detected');
      expect(lowRumble.acoustic, '65 Hz');
      expect(lowRumble.acousticStatus, 'No Buzz (65 Hz)');
      expect(lowRumble.isLowFreqNoBuzz, isTrue);
      expect(lowRumble.isAcousticNotDetected, isFalse);
      expect(lowRumble.isNoBuzzDetected, isTrue);
    });

    testWidgets('AcousticSignalVisualizer displays received Hz when 1-89 Hz classifies as No Buzz Detected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AcousticSignalVisualizer(
              acoustic: '65 Hz',
              acousticStatus: 'No Buzz (65 Hz)',
              conditionLabel: 'No Buzz Detected',
            ),
          ),
        ),
      );
      expect(find.text('65 Hz • No Buzz'), findsOneWidget);
    });

    test('Microphone disconnect (0 Hz) triggers push notification even after recovery to 1-89 Hz or normal', () async {
      final triggeredTitles = <String>[];
      final sub = alertService.onAlertTriggered.listen((a) => triggeredTitles.add(a.title));

      hiveService.addHive(
        HiveData(
          id: 'hive_mic_test',
          name: 'Hive Mic Test',
          deviceId: 'BW-MIC-99',
          conditionLabel: 'Queen Present',
          confidence: 95,
          healthScore: 95,
          temperature: '34.0',
          humidity: '60',
          acoustic: '195 Hz',
          acousticStatus: 'Normal',
          updated: 'Just now',
          wifiStatus: 'Connected',
          isAlert: false,
          alertLabel: 'Normal',
          alertMessage: 'Active',
        ),
      );
      alertService.refreshFromCloud();
      await Future.delayed(Duration.zero);
      expect(triggeredTitles, isEmpty);

      // 1. Microphone disconnected -> 0 Hz
      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-MIC-99',
          'temperature': 34.0,
          'humidity': 60.0,
          'frequency': 0,
          'frequency_hz': 0,
        }
      ]);
      alertService.refreshFromCloud();
      await Future.delayed(Duration.zero);
      expect(triggeredTitles.length, 1);
      expect(triggeredTitles.last, contains('0 Hz'));

      // 2. Microphone reconnected -> detects 65 Hz (No Buzz Detected, > 0 Hz)
      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-MIC-99',
          'temperature': 34.0,
          'humidity': 60.0,
          'frequency': 65,
          'frequency_hz': 65,
        }
      ]);
      alertService.refreshFromCloud();
      await Future.delayed(Duration.zero);

      // 3. Microphone disconnected again -> 0 Hz must immediately push notify again!
      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-MIC-99',
          'temperature': 34.0,
          'humidity': 60.0,
          'frequency': 0,
          'frequency_hz': 0,
        }
      ]);
      alertService.refreshFromCloud();
      await Future.delayed(Duration.zero);
      expect(triggeredTitles.length, 2);
      expect(triggeredTitles.last, contains('0 Hz'));

      // 4. Inactive IoT device (> 10 min old epoch or no active telemetry) must NOT send notifications
      final staleEpoch = DateTime.now().subtract(const Duration(minutes: 25)).millisecondsSinceEpoch;
      hiveService.addHive(
        HiveData(
          id: 'hive_inactive_iot',
          name: 'Hive Inactive IoT',
          deviceId: 'BW-INACTIVE-01',
          conditionLabel: 'No Buzz Detected',
          confidence: 0,
          healthScore: 0,
          temperature: '0.0',
          humidity: '0',
          acoustic: '0 Hz',
          acousticStatus: 'Not Detected (0 Hz)',
          updated: 'Just now',
          wifiStatus: 'Connected',
          isAlert: true,
          alertSeverity: 'Critical',
          alertLabel: '⚠️ Acoustic Signal Not Detected (0 Hz)',
          alertMessage: 'Acoustic microphone on Hive Inactive IoT is detecting 0 Hz.',
          lastAudioCreatedAt: staleEpoch,
        ),
      );
      alertService.refreshFromCloud();
      await Future.delayed(Duration.zero);
      // Count must remain 2 — no notification sent for inactive IoT device
      expect(triggeredTitles.length, 2);

      await sub.cancel();
    });

    testWidgets('Verified TFLite prediction is preserved over unverified ESP32 spike and shows Offline badge when node is offline', (tester) async {
      final staleEpoch = DateTime.now().subtract(const Duration(minutes: 45)).millisecondsSinceEpoch;
      hiveService.addHive(
        HiveData(
          id: 'hive_field_test',
          name: 'Hive (Field Test)',
          deviceId: 'BW-013230',
          conditionLabel: 'Queen Present',
          confidence: 92,
          healthScore: 88,
          temperature: '28.0',
          humidity: '82',
          acoustic: '262 Hz',
          acousticStatus: 'Normal',
          updated: 'Offline',
          wifiStatus: 'Offline',
          isAlert: false,
          alertLabel: 'Queen Present',
          alertMessage: 'Colony is queenright and stable.',
          lastAudioRecordedTime: '09:20:07 PM',
          lastAudioCreatedAt: staleEpoch,
        ),
      );

      // Apply verified TFLite prediction from Clip #1 (09:20:07 PM, 262 Hz, Queen Present)
      hiveService.applyAiModelPrediction(
        deviceId: 'BW-013230',
        recordingEpoch: staleEpoch,
        prediction: 'Queen Present',
        confidence: 92,
        frequencyHz: 262,
        recordedTime: '09:20:07 PM',
      );

      // Simulate unverified ESP32 telemetry spike (532 Hz, Queen Absent) without a newer audio clip
      hiveService.updateFromBackendTelemetry([
        {
          'device_id': 'BW-013230',
          'temperature': 27.6,
          'humidity': 82.2,
          'frequency': 532,
          'frequency_hz': 532,
          'conditionLabel': 'Queen Absent',
          'last_audio_recorded_time': '11:26:02 PM',
          'status': 'Offline',
        }
      ]);

      final updated = hiveService.getHiveById('hive_field_test')!;
      expect(updated.conditionLabel, 'Queen Present');
      expect(updated.acoustic, '262 Hz');
      expect(updated.lastAudioRecordedTime, '09:20:07 PM');
      expect(updated.isSensorOffline, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AcousticSignalVisualizer(
              acoustic: updated.acoustic,
              acousticStatus: updated.acousticStatus,
              conditionLabel: updated.conditionLabel,
              isOffline: updated.isSensorOffline,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('262 Hz • Offline'), findsOneWidget);
      expect(find.text('262 Hz • Active'), findsNothing);
    });
  });
}
