import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Authentication is exclusively for administrators. No public signup exists.
class AuthService {
  AuthService._();

  static const String internalDomain = 'accounts.masjid-khalid.example';
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final RegExp usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  static String usernameToEmail(String value) {
    final username = value.trim().toLowerCase();
    if (!usernamePattern.hasMatch(username)) {
      throw const FormatException('اسم المستخدم غير صحيح');
    }
    return '$username@$internalDomain';
  }

  static Future<void> signInAdmin({
    required String username,
    required String password,
  }) async {
    // The Cloud Function checks all submitted credentials and counts failures
    // across different usernames coming from the same network source.
    final login = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('loginAdminWithCooldown');
    try {
      final response = await login.call(<String, dynamic>{
        'username': username.trim().toLowerCase(),
        'password': password,
        'apiKey': Firebase.app().options.apiKey,
      });
      final payload = Map<String, dynamic>.from(response.data as Map);
      final customToken = payload['customToken'];
      if (customToken is! String || customToken.isEmpty) {
        throw StateError('تعذر إكمال تسجيل الدخول');
      }
      final credential = await _auth.signInWithCustomToken(customToken);
      final user = credential.user;
      if (user == null) throw StateError('لم يتم تسجيل الدخول');

      // Force fresh claims; deny legacy regular users even with valid password.
      final token = await user.getIdTokenResult(true);
      final profile = await _db.collection('users').doc(user.uid).get();
      if (token.claims?['admin'] != true ||
          profile.data()?['role'] != 'admin') {
        throw StateError('هذا الحساب غير مخول لإدارة النظام');
      }
    } catch (_) {
      // Never leave a non-admin signed in after a rejected admin login.
      await _auth.signOut();
      rethrow;
    }
  }

  static Future<void> changeAdminPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 12 || newPassword.length > 128) {
      throw const FormatException(
        'كلمة المرور يجب أن تحتوي على 12 حرفًا على الأقل',
      );
    }
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw StateError('يرجى تسجيل الدخول أولًا');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      ),
    );
    await user.updatePassword(newPassword);
  }

  static Future<void> signOut() => _auth.signOut();

  static String _cooldownMessage(int seconds) {
    if (seconds >= 3600) {
      final hours = (seconds / 3600).ceil();
      return 'تم إيقاف محاولة الدخول مؤقتًا. يرجى المحاولة بعد $hours ساعة.';
    }
    final minutes = (seconds / 60).ceil();
    return 'تم إيقاف محاولة الدخول مؤقتًا. يرجى المحاولة بعد $minutes دقيقة.';
  }

  static String errorMessage(Object error) {
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    if (error is FirebaseFunctionsException) {
      if (error.code == 'resource-exhausted') {
        final details = error.details;
        if (details is Map && details['waitSeconds'] is num) {
          return _cooldownMessage((details['waitSeconds'] as num).ceil());
        }
        return 'محاولات كثيرة، يرجى الانتظار والمحاولة لاحقًا';
      }
      if (error.code == 'permission-denied') {
        return 'اسم المستخدم أو كلمة المرور غير صحيحة';
      }
      if (error.code == 'unavailable') {
        return 'تعذر الاتصال بخدمة الدخول، حاول لاحقًا';
      }
      return 'تعذر تسجيل الدخول، حاول مرة أخرى';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'اسم المستخدم مستخدم بالفعل';
        case 'weak-password':
          return 'اختر كلمة مرور أقوى';
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
          return 'اسم المستخدم أو كلمة المرور غير صحيحة';
        case 'invalid-email':
          return 'اسم المستخدم غير صحيح';
        case 'too-many-requests':
          return 'محاولات كثيرة، حاول مرة أخرى لاحقًا';
        case 'network-request-failed':
          return 'تحقق من الاتصال بالإنترنت';
        case 'requires-recent-login':
          return 'أعد تسجيل الدخول وحاول مرة أخرى';
      }
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'ليس لديك صلاحية الوصول إلى هذه الخدمة';
    }
    return 'حدث خطأ غير متوقع، حاول مرة أخرى';
  }
}
