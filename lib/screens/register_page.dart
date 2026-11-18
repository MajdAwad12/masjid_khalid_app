import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_theme.dart';

// Registration screen for new mosque app users.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  // Personal information.
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _age = TextEditingController();
  final _city = TextEditingController();

  // Account credentials.
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _working = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _age.dispose();
    _city.dispose();
    _username.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  // Validate required text fields.
  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }
    return null;
  }

  // Validate the phone number.
  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';

    if (phone.isEmpty) {
      return 'يرجى إدخال رقم الهاتف';
    }

    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone)) {
      return 'أدخل رقم هاتف صحيحًا';
    }

    return null;
  }

  // Validate age.
  String? _validateAge(String? value) {
    final age = int.tryParse(value?.trim() ?? '');

    if (age == null || age < 1 || age > 120) {
      return 'أدخل عمرًا صحيحًا';
    }

    return null;
  }

  // Validate the username according to AuthService.
  String? _validateUsername(String? value) {
    final username = value?.trim().toLowerCase() ?? '';

    if (username.isEmpty) {
      return 'يرجى إدخال اسم المستخدم';
    }

    if (!AuthService.usernamePattern.hasMatch(username)) {
      return '3-20 أحرف إنجليزية أو أرقام أو _';
    }

    return null;
  }

  // Validate password length.
  String? _validatePassword(String? value) {
    if (value == null || value.length < 8) {
      return 'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل';
    }

    return null;
  }

  // Validate password confirmation.
  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'يرجى تأكيد كلمة المرور';
    }

    if (value != _password.text) {
      return 'كلمتا المرور غير متطابقتين';
    }

    return null;
  }

  // Register a new user using Firebase Authentication
  // and save the profile in Cloud Firestore.
  Future<void> _submit() async {
    if (_working || _formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await AuthService.register(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        age: int.parse(_age.text.trim()),
        city: _city.text.trim(),
        username: _username.text.trim().toLowerCase(),
        password: _password.text,
      );

      if (!mounted) return;

      // Return to AuthGate after successful registration.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
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
      appBar: AppBar(title: const Text('إنشاء حساب جديد')),

      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),

            child: Form(
              key: _formKey,

              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 22,
                ),

                children: [
                  // Registration icon.
                  const Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 58,
                    color: AppColors.gold,
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'أهلاً وسهلاً بك',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.dark,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'أدخل بياناتك لإنشاء حساب في تطبيق المسجد',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 14),
                  ),

                  const SizedBox(height: 25),

                  // Personal information section.
                  const _SectionLabel('المعلومات الشخصية'),

                  const SizedBox(height: 14),

                  AppTextField(
                    controller: _firstName,
                    label: 'الاسم الأول',
                    prefixIcon: Icons.person_outline,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),

                  const SizedBox(height: 14),

                  AppTextField(
                    controller: _lastName,
                    label: 'اسم العائلة',
                    prefixIcon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),

                  const SizedBox(height: 14),

                  AppTextField(
                    controller: _phone,
                    label: 'رقم الهاتف',
                    hintText: '05xxxxxxxx',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    validator: _validatePhone,
                  ),

                  const SizedBox(height: 14),

                  // Numeric input with digit restrictions.
                  TextFormField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'العمر',
                      prefixIcon: Icon(Icons.cake_outlined),
                    ),
                    validator: _validateAge,
                  ),

                  const SizedBox(height: 14),

                  AppTextField(
                    controller: _city,
                    label: 'المدينة',
                    prefixIcon: Icons.location_city_outlined,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),

                  const SizedBox(height: 25),

                  // Account credentials section.
                  const _SectionLabel('بيانات تسجيل الدخول'),

                  const SizedBox(height: 14),

                  AppTextField(
                    controller: _username,
                    label: 'اسم المستخدم',
                    hintText: 'ahmad_123',
                    prefixIcon: Icons.account_circle_outlined,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    validator: _validateUsername,
                  ),

                  const SizedBox(height: 14),

                  AppTextField(
                    controller: _password,
                    label: 'كلمة المرور',
                    prefixIcon: Icons.lock_outline,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    isPassword: true,
                    validator: _validatePassword,
                  ),

                  const SizedBox(height: 14),

                  AppTextField(
                    controller: _confirmPassword,
                    label: 'تأكيد كلمة المرور',
                    prefixIcon: Icons.verified_user_outlined,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    isPassword: true,
                    validator: _validateConfirmPassword,
                    onFieldSubmitted: (_) => _submit(),
                  ),

                  const SizedBox(height: 24),

                  // Register button.
                  AppButton(
                    text: 'إنشاء الحساب',
                    icon: Icons.person_add_alt_1_rounded,
                    isLoading: _working,
                    onPressed: _working ? null : _submit,
                  ),

                  const SizedBox(height: 16),

                  // New accounts always start as regular users.
                  const Text(
                    'كل حساب جديد يبدأ بصلاحيات مستخدم عادي.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),

                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Reusable section title within the registration page.
class _SectionLabel extends StatelessWidget {
  final String value;

  const _SectionLabel(this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(4),
          ),
        ),

        const SizedBox(width: 9),

        Text(
          value,
          style: const TextStyle(
            color: AppColors.dark,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
