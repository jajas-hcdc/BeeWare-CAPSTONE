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

    test('HiveService initializes in clean state', () {
      expect(hiveService.hives, isA<List<HiveData>>());
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
      final target = hiveService.getHiveById('test_hive_123') ??
          HiveData(
            id: 'test_hive_update',
            name: 'Old Name',
            conditionLabel: 'Queen Present',
            confidence: 90,
            healthScore: 90,
            temperature: '34.0',
            humidity: '60',
            acoustic: 'Normal',
            updated: 'Now',
            isAlert: false,
            alertLabel: 'Normal',
            alertMessage: 'Stable',
          );

      if (hiveService.getHiveById(target.id) == null) {
        hiveService.addHive(target);
      }

      final updated = target.copyWith(name: 'Updated Name ABC', confidence: 100);
      hiveService.updateHive(updated);

      final found = hiveService.getHiveById(target.id);
      expect(found?.name, 'Updated Name ABC');
      expect(found?.confidence, 100);
    });

    test('HiveService deletes a hive', () {
      final target = HiveData(
        id: 'test_hive_del',
        name: 'To Delete',
        conditionLabel: 'Queen Present',
        confidence: 90,
        healthScore: 90,
        temperature: '34.0',
        humidity: '60',
        acoustic: 'Normal',
        updated: 'Now',
        isAlert: false,
        alertLabel: 'Normal',
        alertMessage: 'Stable',
      );

      hiveService.addHive(target);
      expect(hiveService.getHiveById('test_hive_del'), isNotNull);

      hiveService.deleteHive('test_hive_del');
      expect(hiveService.getHiveById('test_hive_del'), isNull);
    });
  });
}
