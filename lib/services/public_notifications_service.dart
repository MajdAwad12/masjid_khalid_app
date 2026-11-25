import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apns_readiness.dart';
import 'course_notifications_service.dart';

/// Public announcements, courses, activities and homework only.
/// No account is required; no private registration data is broadcast.
class PublicNotificationsService with widgets.WidgetsBindingObserver {
  PublicNotificationsService._();

  static final instance = PublicNotificationsService._();
  static const topic = 'masjid_public_updates_v1';
  static const _preference = 'masjid_public_updates_enabled_v1';

  static final ValueNotifier<int?> requestedTab = ValueNotifier<int?>(null);

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _rotationSubscription;
  Timer? _retryTimer;
  Future<bool> _serialSync = Future<bool>.value(true);
  int _retryCount = 0;
  bool _started = false;

  Future<bool> enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_preference) ?? false;
  }

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    widgets.WidgetsBinding.instance.addObserver(this);

    // iOS may display system notifications while the app is open.
    // Android continues to show a non-intrusive in-app SnackBar in foreground.
    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // A missing Apple push capability must not crash the public app.
    }

    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] != 'new_public_item' || Platform.isIOS) return;
      final title = message.notification?.title ?? 'خبر جديد من المسجد';
      final body = message.notification?.body ?? '';
      courseMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(body.isEmpty ? title : '$title — $body')),
      );
    });
    _openedSubscription ??=
        FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openMessage(initial);
    } catch (_) {
      // Malformed notifications do not block startup.
    }
    // ignore: deprecated_member_use
    _rotationSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) {
        _retryCount = 0;
        unawaited(_queueSync());
      },
      onError: (Object error) {},
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_preference)) {
        // Preserve the original app behavior: request permission once on
        // first launch, while allowing opt-out from Settings thereafter.
        await setEnabled(true);
      } else {
        await _queueSync();
      }
    } catch (_) {
      _scheduleRetry();
    }
  }

  @override
  void didChangeAppLifecycleState(widgets.AppLifecycleState state) {
    if (state == widgets.AppLifecycleState.resumed) {
      // Recovers iOS APNs readiness and offline subscribe/unsubscribe attempts.
      _retryCount = 0;
      unawaited(_queueSync());
    }
  }

  void _openMessage(RemoteMessage message) {
    if (message.data['type'] != 'new_public_item') return;
    final index = int.tryParse(message.data['section'] ?? '');
    if (index != null && index >= 1 && index <= 4) {
      requestedTab.value = index;
    }
  }

  Future<bool> _queueSync() {
    // Serial execution avoids a pending subscribe overriding an opt-out.
    final next = _serialSync.then((_) => _applyPreference());
    _serialSync = next;
    return next;
  }

  Future<bool> _applyPreference() async {
    try {
      if (!await enabled()) {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        _cancelRetry();
        return true;
      }
      final permission =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        // Keep the desired preference. It can succeed once the user grants
        // permission in system Settings and returns to the app.
        _scheduleRetry();
        return false;
      }
      if (!await waitForApnsToken(attempts: 6)) {
        _scheduleRetry();
        return false;
      }
      // Keep the same token readiness check as private decision delivery.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        _scheduleRetry();
        return false;
      }
      // An idempotent operation: re-subscribing is safe after token refresh.
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      _cancelRetry();
      return true;
    } catch (_) {
      _scheduleRetry();
      return false;
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
    final delay = seconds[_retryCount++];
    _retryTimer = Timer(Duration(seconds: delay), () {
      _retryTimer = null;
      unawaited(_queueSync());
    });
  }

  /// true means that the preference and OS permission were accepted.
  /// The FCM subscription itself may still be pending (e.g. APNs/offline).
  Future<bool> setEnabled(bool shouldEnable) async {
    final prefs = await SharedPreferences.getInstance();
    if (!shouldEnable) {
      await prefs.setBool(_preference, false);
      _retryCount = 0;
      return _queueSync();
    }
    try {
      final permission = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        await prefs.setBool(_preference, false);
        return false;
      }
      await prefs.setBool(_preference, true);
      _retryCount = 0;
      // Do not treat delayed APNs registration as an OS permission refusal.
      await _queueSync();
      return true;
    } catch (_) {
      // If the preference was already saved, preserve the opt-in so the retry
      // can recover after an intermittent network or FCM error.
      if (await enabled()) _scheduleRetry();
      return false;
    }
  }
}
