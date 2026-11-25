import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

/// FCM on Apple platforms needs an APNs token first. iOS may provide it a
/// short time after the user accepts the system notification dialog.
/// This is a bounded wait: registrations still work without notifications.
Future<bool> waitForApnsToken({
  int attempts = 16,
  Duration interval = const Duration(milliseconds: 500),
}) async {
  if (!Platform.isIOS && !Platform.isMacOS) return true;
  for (var i = 0; i < attempts; i++) {
    try {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      if (token != null && token.isNotEmpty) return true;
    } catch (_) {
      // The plugin/OS may not be ready during the first installation.
    }
    if (i + 1 < attempts) await Future<void>.delayed(interval);
  }
  return false;
}
