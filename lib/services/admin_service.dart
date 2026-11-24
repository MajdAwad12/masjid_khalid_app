import 'package:cloud_functions/cloud_functions.dart';

/// Admin-only operations run on the server with Firebase Admin SDK.
class AdminService {
  AdminService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  static Future<void> createAdmin({
    required String username,
    required String password,
  }) async {
    await _functions.httpsCallable('createAdminAccount').call({
      'username': username.trim().toLowerCase(),
      'password': password,
    });
  }

  /// Deactivates another admin's access; their audit record is retained.
  static Future<void> deactivateAdmin({required String targetUid}) async {
    await _functions.httpsCallable('deactivateAdminAccount').call({
      'targetUid': targetUid,
    });
  }

  static String errorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return 'يرجى تسجيل الدخول أولًا';
        case 'permission-denied':
          return 'ليس لديك صلاحية تنفيذ هذه العملية';
        case 'already-exists':
          return 'اسم المستخدم مستخدم بالفعل';
        case 'not-found':
          return 'لم يتم العثور على المسؤول';
        case 'invalid-argument':
          return 'تحقق من اسم المستخدم وكلمة المرور (12 حرفًا على الأقل)';
        case 'failed-precondition':
          return 'أعد تسجيل الدخول أو تحقق من حالة المسؤولين';
        case 'resource-exhausted':
          return 'عملية إدارة أخرى قيد التنفيذ. حاول بعد قليل';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'تعذر الاتصال بالخادم، حاول مجددًا';
      }
    }
    return 'تعذر تنفيذ العملية، حاول مرة أخرى';
  }
}
