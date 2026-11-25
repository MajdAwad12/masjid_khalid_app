import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_notifications_service.dart';
import 'apns_readiness.dart';

/// One public topic for new announcements, courses, activities and homework.
/// It contains public content ONLY, and does not require a user account.
class PublicNotificationsService {
  PublicNotificationsService._();

  static final instance = PublicNotificationsService._();
  static const topic = 'masjid_public_updates_v1';
  static const _preference = 'masjid_public_updates_enabled_v1';

  /// Tapping a notification navigates to the corresponding app tab.
  static final ValueNotifier<int?> requestedTab = ValueNotifier<int?>(null);

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _rotationSubscription;
  bool _started = false;
  bool _topicSubscribed = false;

  Future<bool> enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_preference) ?? false;
  }

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] != 'new_public_item') return;
      final title = message.notification?.title ?? 'خبر جديد من المسجد';
      final body = message.notification?.body ?? '';
      courseMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(body.isEmpty ? title : '$title — $body')),
      );
    });
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _openMessage,
    );
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openMessage(initial);
    } catch (_) {
      // The home screen remains available if the notification is malformed.
    }
    // ignore: deprecated_member_use
    _rotationSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => unawaited(_restoreTopic()),
      onError: (Object error) {},
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      // Ask once after installing the update; people can change the choice
      // later in Settings. A declined permission is never overridden.
      if (!prefs.containsKey(_preference)) {
        await setEnabled(true);
      } else if (prefs.getBool(_preference) == true) {
        await _restoreTopic();
      } else {
        // Retry a previously failed unsubscribe after reconnecting.
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        } catch (_) {}
      }
    } catch (_) {
      // Lack of notification support must not interrupt the application.
    }
  }

  void _openMessage(RemoteMessage message) {
    if (message.data['type'] != 'new_public_item') return;
    final index = int.tryParse(message.data['section'] ?? '');
    if (index != null && index >= 1 && index <= 4) {
      requestedTab.value = index;
    }
  }

  Future<void> _restoreTopic() async {
    if (!await enabled()) return;
    try {
      if (!await waitForApnsToken()) {
        // A one-shot retry handles a slower initial APNs registration.
        if (!_topicSubscribed) {
          _topicSubscribed = true;
          unawaited(Future<void>.delayed(
            const Duration(seconds: 12),
            () async {
              _topicSubscribed = false;
              if (!await enabled()) return;
              try {
                if (!await waitForApnsToken()) return;
                if (await enabled()) {
                  await FirebaseMessaging.instance.subscribeToTopic(topic);
                }
              } catch (_) {}
            },
          ));
        }
        return;
      }
      if (!await enabled()) return;
      await FirebaseMessaging.instance.subscribeToTopic(topic);
    } catch (_) {
      // Retry on the next launch or refreshed registration.
    }
  }

  /// Returns false if the operating system denies push permissions.
  Future<bool> setEnabled(bool shouldEnable) async {
    final prefs = await SharedPreferences.getInstance();
    if (!shouldEnable) {
      // Respect the opt-out even when network access is temporarily missing.
      await prefs.setBool(_preference, false);
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        return true;
      } catch (_) {
        // Retry on the next launch. Do not claim this unsubscribe succeeded.
        return false;
      }
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
      // Record the preference; on Apple platforms APNs readiness may lag.
      await prefs.setBool(_preference, true);
      await _restoreTopic();
      return true;
    } catch (_) {
      await prefs.setBool(_preference, false);
      return false;
    }
  }
}
