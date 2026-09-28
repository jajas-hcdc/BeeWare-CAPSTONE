import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/models/hive_data.dart';
import 'package:beeware_app/services/hive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QR Code Direct Pairing Tests', () {
    late HiveService hiveService;

    setUp(() {
      hiveService = HiveService();
    });

    test('Parses JSON QR payload with deviceId and mac', () {
      const qrPayload = '{"deviceId":"BW-A1B2C3","mac":"24:6F:28:A1:B2:C3"}';
      final decoded = jsonDecode(qrPayload) as Map<String, dynamic>;

      final deviceId = (decoded['deviceId'] ?? decoded['device_id'] ?? '').toString();
      final mac = decoded['mac']?.toString();

      expect(deviceId, 'BW-A1B2C3');
      expect(mac, '24:6F:28:A1:B2:C3');
    });

    test('Parses snake_case JSON QR payload', () {
      const qrPayload = '{"device_id":"BW-D4E5F6","mac":"24:6F:28:D4:E5:F6"}';
      final decoded = jsonDecode(qrPayload) as Map<String, dynamic>;

      final deviceId = (decoded['deviceId'] ?? decoded['device_id'] ?? '').toString();
      expect(deviceId, 'BW-D4E5F6');
    });

    test('Handles plain text QR payload', () {
      const rawText = 'BW-998877';
      String deviceId = rawText.trim();
      String? mac;

      try {
        final map = jsonDecode(rawText) as Map<String, dynamic>;
        deviceId = (map['deviceId'] ?? map['device_id'] ?? rawText).toString();
        mac = map['mac']?.toString();
      } catch (_) {
        // Expected for plain text
      }

      expect(deviceId, 'BW-998877');
      expect(mac, isNull);
    });

    test('Directly creates and connects hive without BLE steps', () {
      final initialCount = hiveService.hives.length;
      const deviceId = 'BW-QR-TEST';

      final newHive = HiveData(
        id: 'hive_qr_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Hive ${initialCount + 1}',
        deviceId: deviceId,
        notes: 'Paired directly via QR sticker',
        conditionLabel: 'Queen Present',
        confidence: 95,
        healthScore: 94,
        temperature: '34.2',
        humidity: '61',
        acoustic: 'Real-Time Stream Active',
        acousticStatus: 'Live',
        wifiStatus: 'Connected',
        batteryLevel: '95%',
        updated: 'Just now',
        signalBars: 4,
        isAlert: false,
        alertLabel: 'Queen Present',
        alertMessage: 'Real-time telemetry stream active from $deviceId.',
      );

      hiveService.addHive(newHive);

      expect(hiveService.hives.length, initialCount + 1);
      final found = hiveService.hives.firstWhere((h) => h.deviceId == deviceId);
      expect(found.name, 'Hive ${initialCount + 1}');
      expect(found.notes, contains('QR sticker'));
    });
  });
}

