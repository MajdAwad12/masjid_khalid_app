import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../auth/auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static const Color gold = Color(0xFFA16602);
  static const Color background = Color(0xFFFAF8F1);
  static const Color muted = Color(0xFF756C5D);

  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _age = TextEditingController();
  final _city = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _working = false;
  bool _showPassword = false;

  @override
  void dispose() {
    for (final controller in [
      _firstName, _lastName, _phone, _age, _city,
      _username, _password, _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  InputDecoration _field(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: gold),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE9DFC9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: gold, width: 1.5),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'هذا الحقل مطلوب'
      : null;

  Future<void> _submit() async {
    if (_working || !_formKey.currentState!.validate()) return;
    setState(() => _working = true);
    try {
      await AuthService.register(
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
        age: int.parse(_age.text),
        city: _city.text,
        username: _username.text,
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthService.errorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(title: const Text('إنشاء حساب جديد')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
              children: [
                const Icon(Icons.person_add_alt_1_rounded, size: 58, color: gold),
                const SizedBox(height: 12),
                const Text(
                  'أهلاً وسهلاً بك',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'أدخل بياناتك لإنشاء حساب في تطبيق المسجد',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 25),
                const _SectionLabel('المعلومات الشخصية'),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _firstName,
                  decoration: _field('الاسم الأول', Icons.person_outline),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _lastName,
                  decoration: _field('اسم العائلة', Icons.badge_outlined),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: _field('رقم الهاتف', Icons.phone_outlined,
                      hint: '05xxxxxxxx'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    return RegExp(r'^\+?[0-9]{8,15}$').hasMatch(value)
                        ? null
                        : 'أدخل رقم هاتف صحيحًا';
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: _field('العمر', Icons.cake_outlined),
                  validator: (v) {
                    final age = int.tryParse(v ?? '');
                    return age != null && age >= 1 && age <= 120
                        ? null
                        : 'أدخل عمرًا صحيحًا';
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _city,
                  decoration: _field('المدينة', Icons.location_city_outlined),
                  validator: _required,
                ),
                const SizedBox(height: 25),
                const _SectionLabel('بيانات تسجيل الدخول'),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _username,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  textDirection: TextDirection.ltr,
                  decoration: _field('اسم المستخدم', Icons.account_circle_outlined,
                      hint: 'ahmad_123'),
                  validator: (v) {
                    final name = v?.trim().toLowerCase() ?? '';
                    return AuthService.usernamePattern.hasMatch(name)
                        ? null
                        : '3-20 أحرف إنجليزية أو أرقام أو _';
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: !_showPassword,
                  textDirection: TextDirection.ltr,
                  decoration: _field('كلمة المرور', Icons.lock_outline)
                      .copyWith(
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                        () => _showPassword = !_showPassword,
                      ),
                      icon: Icon(_showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                    ),
                  ),
                  validator: (v) => v == null || v.length < 8
                      ? 'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: !_showPassword,
                  textDirection: TextDirection.ltr,
                  decoration: _field('تأكيد كلمة المرور', Icons.verified_user_outlined),
                  validator: (v) => v != _password.text
                      ? 'كلمتا المرور غير متطابقتين'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _working ? null : _submit,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: _working
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,
                          ),
                        )
                      : const Text('إنشاء الحساب',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'كل حساب جديد يبدأ بصلاحيات مستخدم عادي.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String value;
  const _SectionLabel(this.value);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 4, height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFA16602),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 9),
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      );
}
