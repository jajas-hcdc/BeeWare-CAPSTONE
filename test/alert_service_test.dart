import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/services/alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlertService Synchronization Tests', () {
    test('AlertService initializes and provides synchronized alerts', () {
      final service = AlertService();
      final allAlerts = service.alerts;
      final recentAlerts = service.recentAlerts;

      expect(allAlerts, isNotEmpty);
      expect(recentAlerts, isNotEmpty);

      // Verify that every alert in Recent Alerts is present in All Alerts (Alerts tab)
      for (final r in recentAlerts) {
        final match = allAlerts.any((a) => a.id == r.id && a.hiveId == r.hiveId);
        expect(match, isTrue, reason: 'Recent alert ${r.title} for ${r.hiveId} must exist in Alerts screen list');
      }
    });

    test('Recent alerts contains up to 4 items and preserves descending timestamp order', () {
      final service = AlertService();
      final recent = service.recentAlerts;

      expect(recent.length, lessThanOrEqualTo(4));
      if (recent.length > 1) {
        for (int i = 0; i < recent.length - 1; i++) {
          expect(
            recent[i].timestamp.isAfter(recent[i + 1].timestamp) ||
                recent[i].timestamp.isAtSameMomentAs(recent[i + 1].timestamp),
            isTrue,
          );
        }
      }
    });
  });
}
