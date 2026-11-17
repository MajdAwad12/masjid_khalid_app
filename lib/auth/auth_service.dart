import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// DEVELOPMENT-ONLY username adapter.
/// Firebase email/password does not directly support usernames.
/// These synthetic addresses cannot receive password-reset emails.
/// Replace this with a verified account-recovery strategy before release.
class AuthService {
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

  static Future<void> signIn({
    required String usernameOrEmail,
    required String password,
  }) async {
    final text = usernameOrEmail.trim();
    // Existing administrator created with a real email can use it here.
    // New users use only the username.
    final email = text.contains('@') ? text : usernameToEmail(text);
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _auth.currentUser?.getIdTokenResult(true);
  }

  static Future<void> register({
    required String firstName,
    required String lastName,
    required String phone,
    required int age,
    required String city,
    required String username,
    required String password,
  }) async {
    final canonicalName = username.trim().toLowerCase();
    final email = usernameToEmail(canonicalName);

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw StateError('لم يتم إنشاء الحساب');
    }

    try {
      await _db.collection('users').doc(user.uid).set({
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'username': canonicalName,
        'phone': phone.trim(),
        'age': age,
        'city': city.trim(),
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Don't leave a sign-inable incomplete profile if Firestore fails.
      try {
        await user.delete();
      } catch (_) {
        await _auth.signOut();
      }
      rethrow;
    }
  }

  static Future<void> signOut() => _auth.signOut();

  static String errorMessage(Object error) {
    if (error is FormatException) return error.message;
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'اسم المستخدم مستخدم بالفعل';
        case 'weak-password':
          return 'اختر كلمة مرور أقوى';
        case 'invalid-email':
          return 'اسم المستخدم أو البريد الإلكتروني غير صحيح';
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
          return 'اسم المستخدم أو كلمة المرور غير صحيحة';
        case 'too-many-requests':
          return 'محاولات كثيرة، حاول مرة أخرى لاحقًا';
        case 'network-request-failed':
          return 'تحقق من الاتصال بالإنترنت';
      }
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'تعذر حفظ الملف الشخصي. تأكد من نشر قواعد Firestore';
    }
    return 'حدث خطأ غير متوقع، حاول مرة أخرى';
  }
}
