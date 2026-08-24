import 'package:flutter_test/flutter_test.dart';
import 'package:beeware_app/models/alert_model.dart';

void main() {
  group('AlertModel Unit Tests', () {
    test('Correctly deduces severity for Queen statuses', () {
      expect(AlertModel.deduceSeverity('Queen Absent'), 'Critical');
      expect(AlertModel.deduceSeverity('Queen Rejected'), 'Warning');
      expect(AlertModel.deduceSeverity('Queen Present'), 'Info');
      expect(AlertModel.deduceSeverity('Queen Accepted'), 'Info');
    });

    test('Correctly deserializes from Map with camelCase keys', () {
      final map = {
        'id': 'alert_101',
        'hiveId': 'Hive 3',
        'queenStatus': 'Queen Absent',
        'title': 'Queen Absent Warning',
        'message': 'No queen signals detected',
        'timestamp': DateTime(2026, 8, 22, 10, 0).toIso8601String(),
        'recommendation': 'Inspect hive immediately',
      };

      final alert = AlertModel.fromMap(map, 'alert_101');

      expect(alert.id, 'alert_101');
      expect(alert.hiveId, 'Hive 3');
      expect(alert.queenStatus, 'Queen Absent');
      expect(alert.severity, 'Critical');
      expect(alert.recommendation, 'Inspect hive immediately');
    });

    test('Correctly deserializes from Map with snake_case backend keys', () {
      final map = {
        'hive_id': 'BW-002',
        'queen_status': 'Queen Rejected',
        'title': 'Queen Rejected',
        'message': 'Worker agitation detected',
      };

      final alert = AlertModel.fromMap(map);

      expect(alert.hiveId, 'BW-002');
      expect(alert.queenStatus, 'Queen Rejected');
      expect(alert.severity, 'Warning');
      expect(alert.recommendation.isNotEmpty, true);
    });

    test('toMap generates valid payload', () {
      final alert = AlertModel(
        id: 'alert_202',
        hiveId: 'Hive 1',
        queenStatus: 'Queen Present',
        title: 'Status Normal',
        message: 'Queen active',
        severity: 'Info',
        timestamp: DateTime(2026, 8, 22, 12, 0),
        recommendation: 'Continue monitoring',
        userId: 'user_xyz',
      );

      final map = alert.toMap();

      expect(map['hiveId'], 'Hive 1');
      expect(map['queenStatus'], 'Queen Present');
      expect(map['severity'], 'Info');
      expect(map['userId'], 'user_xyz');
    });
  });
}
