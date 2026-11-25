import 'dart:async';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'courses_service.dart';
import 'activities_service.dart';
import 'apns_readiness.dart';

// No Firebase Auth account is created for public users. Each installation has
// a random private key only to update FCM delivery and check its own statuses.
// This is NOT a device hardware ID, a person's identity or a GPS tracker.
final GlobalKey<ScaffoldMessengerState> courseMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class CourseNotificationsService {
  CourseNotificationsService._();
  static final CourseNotificationsService instance =
      CourseNotificationsService._();

  static const _deviceKeyPref = 'course_installation_key_v1';
  Future<String>? _cachedKey;
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;

  Future<String> deviceKey() => _cachedKey ??= _readOrCreateKey();

  Future<String?> existingDeviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKeyPref);
    if (existing == null || existing.length != 64) return null;
    return existing;
  }

  Future<String> _readOrCreateKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKeyPref);
    if (existing != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(existing)) {
      return existing;
    }
    final random = Random.secure();
    final key = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_deviceKeyPref, key);
    return key;
  }

  Future<void> initialize() async {
    // ignore: deprecated_member_use
    _refreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(_syncIfRegistered(token)),
      onError: (Object error) {},
    );
    _messageSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] != 'course_decision' &&
          message.data['type'] != 'activity_decision') {
        return;
      }
      final text = message.notification?.title ?? 'تحديث بخصوص تسجيلك';
      courseMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(text)),
      );
    });
    try {
      final key = await existingDeviceKey();
      if (key != null) {
        final token = await _safeCurrentToken();
        if (token != null) {
          await _syncBoth(key, token);
        }
      }
    } catch (_) {
      // No need to interrupt the public app when notifications are unavailable.
    }
  }

  Future<void> _syncIfRegistered(String token) async {
    try {
      final key = await existingDeviceKey();
      if (key != null) {
        await _syncBoth(key, token);
      }
    } catch (_) {
      // A subsequent app launch will retry the sync.
    }
  }

  Future<void> _syncBoth(String key, String token) async {
    try {
      await CoursesService.syncToken(deviceKey: key, token: token);
    } catch (_) {
      // Course token update failure must not block activity notification sync.
    }
    try {
      await ActivitiesService.syncToken(key, token);
    } catch (_) {
      // Both are retried at the next launch or token rotation.
    }
  }

  Future<String?> _safeCurrentToken() async {
    try {
      if (!await waitForApnsToken()) return null;
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<String?> requestToken() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied ||
          settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        return null;
      }
      return await _safeCurrentToken();
    } catch (_) {
      return null;
    }
  }
}
