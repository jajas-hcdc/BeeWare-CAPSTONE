import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beeware_app/services/user_profile_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserProfileService Account-Scoped Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with default values when no user logged in', () async {
      final service = UserProfileService();
      await service.initialize();

      expect(service.nickname, equals('Beekeeper'));
      expect(service.selectedAvatar, equals('default'));
      expect(service.customImagePath, isNull);
      expect(service.selectedGender, equals('MALE'));
      expect(service.selectedDob, equals(DateTime(1999, 1, 1)));
    });

    test('Updating profile attributes updates service state and notifies listeners', () {
      final service = UserProfileService();
      bool notified = false;
      service.addListener(() {
        notified = true;
      });

      service.setNickname('QueenBeeMaster');
      expect(service.nickname, equals('QueenBeeMaster'));
      expect(notified, isTrue);

      service.setGender('FEMALE');
      expect(service.selectedGender, equals('FEMALE'));

      final newDob = DateTime(2001, 5, 20);
      service.setDob(newDob);
      expect(service.selectedDob, equals(newDob));

      service.setCustomImage('/path/to/custom.jpg');
      expect(service.selectedAvatar, equals('custom'));
      expect(service.customImagePath, equals('/path/to/custom.jpg'));
    });
  });
}
