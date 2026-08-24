import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/models/hive_data.dart';
import 'package:beeware_app/services/hive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HiveService Tests', () {
    late HiveService hiveService;

    setUp(() {
      hiveService = HiveService();
    });

    test('HiveService initializes with samples', () {
      expect(hiveService.hives.isNotEmpty, true);
    });

    test('HiveService adds a new hive and notifies listeners', () {
      final initialCount = hiveService.hives.length;
      bool notified = false;

      hiveService.addListener(() {
        notified = true;
      });

      final newHive = HiveData(
        id: 'test_hive_123',
        name: 'Unit Test Hive',
        conditionLabel: 'Queen Present',
        confidence: 99,
        healthScore: 99,
        temperature: '34.5',
        humidity: '62',
        acoustic: 'Normal',
        updated: 'Now',
        isAlert: false,
        alertLabel: 'Normal',
        alertMessage: 'Stable',
      );

      hiveService.addHive(newHive);

      expect(hiveService.hives.length, initialCount + 1);
      expect(hiveService.getHiveById('test_hive_123')?.name, 'Unit Test Hive');
      expect(notified, true);
    });

    test('HiveService updates an existing hive', () {
      final target = hiveService.hives.first;
      final updated = target.copyWith(name: 'Updated Name ABC', confidence: 100);

      hiveService.updateHive(updated);

      final found = hiveService.getHiveById(target.id);
      expect(found?.name, 'Updated Name ABC');
      expect(found?.confidence, 100);
    });

    test('HiveService deletes a hive', () {
      final initialCount = hiveService.hives.length;
      final targetId = hiveService.hives.first.id;

      hiveService.deleteHive(targetId);

      expect(hiveService.hives.length, initialCount - 1);
      expect(hiveService.getHiveById(targetId), isNull);
    });
  });
}
