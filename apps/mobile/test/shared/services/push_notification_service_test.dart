import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crimereport/shared/services/push_notification_service.dart';

class _MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

void main() {
  late _MockFirebaseMessaging messaging;

  setUp(() {
    messaging = _MockFirebaseMessaging();
  });

  group('PushNotificationService.getDeviceToken', () {
    test('returns APNs token immediately on iOS', () async {
      when(() => messaging.getAPNSToken())
          .thenAnswer((_) async => 'apns-hex-token');

      final service = PushNotificationService(
        messaging: messaging,
        platformOverride: () => TargetPlatform.iOS,
      );

      final token = await service.getDeviceToken(
        pollInterval: const Duration(milliseconds: 1),
        maxAttempts: 3,
      );

      expect(token, 'apns-hex-token');
      verify(() => messaging.getAPNSToken()).called(1);
      verifyNever(() => messaging.getToken());
    });

    test('retries until APNs returns a token on iOS', () async {
      var calls = 0;
      when(() => messaging.getAPNSToken()).thenAnswer((_) async {
        calls++;
        if (calls < 3) return null;
        return 'apns-hex-token';
      });

      final service = PushNotificationService(
        messaging: messaging,
        platformOverride: () => TargetPlatform.iOS,
      );

      final token = await service.getDeviceToken(
        pollInterval: const Duration(milliseconds: 1),
        maxAttempts: 5,
      );

      expect(token, 'apns-hex-token');
      expect(calls, 3);
    });

    test('returns null after retries when APNs never resolves', () async {
      when(() => messaging.getAPNSToken()).thenAnswer((_) async => null);

      final service = PushNotificationService(
        messaging: messaging,
        platformOverride: () => TargetPlatform.iOS,
      );

      final token = await service.getDeviceToken(
        pollInterval: const Duration(milliseconds: 1),
        maxAttempts: 3,
      );

      expect(token, isNull);
      verify(() => messaging.getAPNSToken()).called(3);
      verifyNever(() => messaging.getToken());
    });

    test('treats empty APNs string as not-yet-available', () async {
      var calls = 0;
      when(() => messaging.getAPNSToken()).thenAnswer((_) async {
        calls++;
        return calls == 1 ? '' : 'apns-hex-token';
      });

      final service = PushNotificationService(
        messaging: messaging,
        platformOverride: () => TargetPlatform.iOS,
      );

      final token = await service.getDeviceToken(
        pollInterval: const Duration(milliseconds: 1),
        maxAttempts: 5,
      );

      expect(token, 'apns-hex-token');
      expect(calls, 2);
    });

    test('continues retrying when getAPNSToken throws', () async {
      var calls = 0;
      when(() => messaging.getAPNSToken()).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw Exception('APNs not ready');
        return 'apns-hex-token';
      });

      final service = PushNotificationService(
        messaging: messaging,
        platformOverride: () => TargetPlatform.iOS,
      );

      final token = await service.getDeviceToken(
        pollInterval: const Duration(milliseconds: 1),
        maxAttempts: 5,
      );

      expect(token, 'apns-hex-token');
      expect(calls, 2);
    });

    test('returns FCM token on Android', () async {
      when(() => messaging.getToken()).thenAnswer((_) async => 'fcm-token');

      final service = PushNotificationService(
        messaging: messaging,
        platformOverride: () => TargetPlatform.android,
      );

      final token = await service.getDeviceToken();

      expect(token, 'fcm-token');
      verify(() => messaging.getToken()).called(1);
      verifyNever(() => messaging.getAPNSToken());
    });

    test('returns FCM token on macOS (non-iOS Apple platform)', () async {
      when(() => messaging.getToken()).thenAnswer((_) async => 'fcm-token');

      final service = PushNotificationService(
        messaging: messaging,
        platformOverride: () => TargetPlatform.macOS,
      );

      final token = await service.getDeviceToken();

      expect(token, 'fcm-token');
      verify(() => messaging.getToken()).called(1);
      verifyNever(() => messaging.getAPNSToken());
    });

    test('returns null and logs when FCM token fetch throws', () async {
      when(() => messaging.getToken()).thenThrow(Exception('boom'));

      final service = PushNotificationService(
        messaging: messaging,
        platformOverride: () => TargetPlatform.android,
      );

      final token = await service.getDeviceToken();

      expect(token, isNull);
    });
  });
}
