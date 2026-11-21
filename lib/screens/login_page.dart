import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import 'forgot_password_page.dart';
import '../widgets/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Login screen shared by regular users and administrators.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _working = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  // Validate credentials and sign in through Firebase.
  Future<void> _submit() async {
    if (_working || _formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await AuthService.signIn(
        usernameOrEmail: _username.text.trim(),
        password: _password.text,
      );

      if (!mounted) return;

      // Return to AuthGate, which opens the correct user screen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('LOGIN ERROR TYPE: ${error.runtimeType}');

        if (error is FirebaseAuthException) {
          debugPrint('LOGIN ERROR CODE: ${error.code}');
          debugPrint('LOGIN ERROR MESSAGE: ${error.message}');
        } else {
          debugPrint('LOGIN ERROR: $error');
        }

        debugPrintStack(stackTrace: stackTrace);
      }

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.errorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول')),

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),

              child: Form(
                key: _formKey,

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [
                    // Login icon.
                    const Icon(
                      Icons.lock_person_outlined,
                      size: 70,
                      color: AppColors.gold,
                    ),

                    const SizedBox(height: 18),

                    // Welcome title.
                    const Text(
                      'أهلاً بعودتك',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.dark,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'أدخل بيانات حسابك للمتابعة',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),

                    const SizedBox(height: 26),

                    // Username input.
                    AppTextField(
                      controller: _username,
                      label: 'اسم المستخدم',
                      hintText: 'أدخل اسم المستخدم',
                      prefixIcon: Icons.person_outline,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.next,

                      validator: (value) {
                        final username = value?.trim().toLowerCase() ?? '';

                        if (username.isEmpty) {
                          return 'يرجى إدخال اسم المستخدم';
                        }

                        if (!AuthService.usernamePattern.hasMatch(username)) {
                          return 'اسم المستخدم غير صحيح';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Password input.
                    AppTextField(
                      controller: _password,
                      label: 'كلمة المرور',
                      hintText: 'أدخل كلمة المرور',
                      prefixIcon: Icons.lock_outline,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      isPassword: true,

                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'يرجى إدخال كلمة المرور';
                        }

                        return null;
                      },

                      onFieldSubmitted: (_) {
                        _submit();
                      },
                    ),

                    const SizedBox(height: 10),

                    // Password recovery is separate for users and admins.
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: _working
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        const ForgotPasswordPage(),
                                  ),
                                );
                              },
                        child: const Text('نسيت كلمة المرور؟'),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Shared login button with loading state.
                    AppButton(
                      text: 'تسجيل الدخول',
                      icon: Icons.login_rounded,
                      isLoading: _working,
                      onPressed: _working ? null : _submit,
                    ),

                    const SizedBox(height: 16),

                    // Both account types share the same login.
                    const Text(
                      'يستخدم الجميع شاشة الدخول نفسها، وتُحدد الصلاحيات تلقائيًا.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
