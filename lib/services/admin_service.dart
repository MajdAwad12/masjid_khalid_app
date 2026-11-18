import 'package:cloud_functions/cloud_functions.dart';

// Communicates with secure Firebase Cloud Functions.
// Only authorized admins can perform management operations.
class AdminService {
  AdminService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  // Change a user's real role in Firebase Authentication
  // and synchronize it with Cloud Firestore.
  static Future<void> changeUserRole({
    required String targetUid,
    required String role,
  }) async {
    if (targetUid.trim().isEmpty || (role != 'admin' && role != 'user')) {
      throw ArgumentError('Invalid user or role');
    }

    await _functions.httpsCallable('changeUserRole').call({
      'targetUid': targetUid,
      'role': role,
    });
  }

  // Reset a regular user's password.
  // The admin must verify the user's identity first.
  static Future<void> resetUserPassword({
    required String targetUid,
    required String newPassword,
    required bool identityVerified,
  }) async {
    if (targetUid.trim().isEmpty ||
        newPassword.length < 12 ||
        newPassword.length > 128 ||
        !identityVerified) {
      throw ArgumentError('Invalid password reset request');
    }

    await _functions.httpsCallable('resetUserPassword').call({
      'targetUid': targetUid,
      'newPassword': newPassword,
      'identityVerified': identityVerified,
    });
  }

  // Display user-friendly Arabic error messages.
  static String errorMessage(Object error) {
    if (error is ArgumentError) {
      return 'تحقق من صحة البيانات المدخلة';
    }

    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return 'يرجى تسجيل الدخول أولاً';

        case 'permission-denied':
          return 'ليس لديك صلاحية تنفيذ هذه العملية';

        case 'not-found':
          return 'لم يتم العثور على المستخدم';

        case 'invalid-argument':
          return 'البيانات المدخلة غير صحيحة';

        case 'failed-precondition':
          return 'لا يمكن تنفيذ العملية في الحالة الحالية';

        case 'unavailable':
        case 'deadline-exceeded':
          return 'تعذر الاتصال بالخادم، حاول مرة أخرى';
        case 'resource-exhausted':
          return 'يرجى الانتظار 60 ثانية قبل إعادة تعيين كلمة المرور مرة أخرى';
      }
    }

    return 'حدث خطأ غير متوقع، حاول مرة أخرى';
  }
}
