import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activities_service.dart';
import 'apns_readiness.dart';
import 'courses_service.dart';

// Ordinary users do not need a Firebase Auth account. The random installation
// key only authorizes status lookup and notification-token updates.
final GlobalKey<ScaffoldMessengerState> courseMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class CourseNotificationsService with widgets.WidgetsBindingObserver {
  CourseNotificationsService._();
  static final CourseNotificationsService instance =
      CourseNotificationsService._();

  static const _deviceKeyPref = 'course_installation_key_v1';
  Future<String>? _cachedKey;
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _started = false;
  bool _syncing = false;
  bool _syncRequestedAgain = false;

  Future<String> deviceKey() => _cachedKey ??= _readOrCreateKey();

  Future<String?> existingDeviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKeyPref);
    if (existing == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(existing)) {
      return null;
    }
    return existing;
  }

  Future<String> _readOrCreateKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKeyPref);
    if (existing != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(existing)) {
      return existing;
    }
    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(_deviceKeyPref, key);
    // The user may have registered after an initial APNs delay. Recover the
    // decision delivery destination without requiring a second registration.
    _scheduleRetry();
    return key;
  }

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    widgets.WidgetsBinding.instance.addObserver(this);
    // ignore: deprecated_member_use
    _refreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        _retryCount = 0;
        unawaited(_syncIfRegistered(token));
      },
      onError: (Object error) {},
    );
    _messageSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] != 'course_decision' &&
          message.data['type'] != 'activity_decision') {
        return;
      }
      // iOS displays the system banner via foreground presentation options.
      if (Platform.isIOS) return;
      final title = message.notification?.title ?? 'تحديث بخصوص تسجيلك';
      courseMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(title)),
      );
    });
    await refreshTokenSync();
  }

  @override
  void didChangeAppLifecycleState(widgets.AppLifecycleState state) {
    if (state == widgets.AppLifecycleState.resumed) {
      _retryCount = 0;
      unawaited(refreshTokenSync());
    }
  }

  Future<void> _syncIfRegistered(String token) async {
    final key = await existingDeviceKey();
    if (key == null) return;
    await _synchronize(key, token);
  }

  Future<void> refreshTokenSync() async {
    if (_syncing) {
      _syncRequestedAgain = true;
      return;
    }
    final key = await existingDeviceKey();
    if (key == null) return;
    final token = await _safeCurrentToken();
    if (token == null) {
      _scheduleRetry();
      return;
    }
    await _synchronize(key, token);
  }

  Future<void> _synchronize(String key, String token) async {
    if (_syncing) {
      _syncRequestedAgain = true;
      return;
    }
    _syncing = true;
    bool coursesOk = false;
    bool activitiesOk = false;
    try {
      try {
        await CoursesService.syncToken(deviceKey: key, token: token);
        coursesOk = true;
      } catch (_) {
        // One failed endpoint must not prevent the other from syncing.
      }
      try {
        await ActivitiesService.syncToken(key, token);
        activitiesOk = true;
      } catch (_) {}
      if (coursesOk && activitiesOk) {
        _cancelRetry();
      } else {
        _scheduleRetry();
      }
    } finally {
      _syncing = false;
      if (_syncRequestedAgain) {
        _syncRequestedAgain = false;
        unawaited(refreshTokenSync());
      }
    }
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
  }

  void _scheduleRetry() {
    if (!_started || _retryTimer != null || _retryCount >= 6) return;
    const seconds = [5, 15, 30, 60, 120, 300];
    final secondsUntilRetry = seconds[_retryCount++];
    _retryTimer = Timer(Duration(seconds: secondsUntilRetry), () {
      _retryTimer = null;
      unawaited(refreshTokenSync());
    });
  }

  Future<String?> _safeCurrentToken() async {
    try {
      final permission =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        return null;
      }
      if (!await waitForApnsToken(attempts: 6)) return null;
      // Existing registration records and Admin SDK sends use FCM tokens.
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
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return null;
      }
      final token = await _safeCurrentToken();
      if (token == null) _scheduleRetry();
      return token;
    } catch (_) {
      _scheduleRetry();
      return null;
    }
  }
}
