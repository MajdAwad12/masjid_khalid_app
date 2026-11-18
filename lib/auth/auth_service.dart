import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  // Internal domain for username-based authentication.
  static const String internalDomain = 'accounts.masjid-khalid.example';

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Allowed username: 3-20 characters.
  static final RegExp usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  // Convert username into an internal Firebase email.
  static String usernameToEmail(String value) {
    final username = value.trim().toLowerCase();

    if (!usernamePattern.hasMatch(username)) {
      throw const FormatException('اسم المستخدم غير صحيح');
    }

    return '$username@$internalDomain';
  }

  // Sign in using username and password.
  static Future<void> signIn({
    required String usernameOrEmail,
    required String password,
  }) async {
    final email = usernameToEmail(usernameOrEmail);

    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }


  // Register a new regular user.
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

    if (password.length < 8) {
      throw const FormatException('كلمة المرور يجب ألا تقل عن 8 أحرف');
    }

    // Create an account in Firebase Authentication.
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw StateError('لم يتم إنشاء الحساب');
    }

    try {
      // Save user profile in Firestore.
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
      // Attempt to remove the Auth account if
      // the Firestore profile could not be created.
      try {
        await user.delete();
      } catch (_) {
        await _auth.signOut();
      }

      rethrow;
    }
  }

  // Sign out the current user.
  static Future<void> signOut() {
    return _auth.signOut();
  }

  // Convert authentication errors into Arabic messages.
  static String errorMessage(Object error) {
    if (error is FormatException) {
      return error.message;
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
      }
    }

    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'تعذر حفظ الملف الشخصي';
    }

    return 'حدث خطأ غير متوقع، حاول مرة أخرى';
  }
}
