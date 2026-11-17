import 'package:material_ui/material_ui.dart';
import '../auth/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color gold = Color(0xFFA16602);
  static const Color background = Color(0xFFFAF8F1);

  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _working = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _working) return;
    setState(() => _working = true);
    try {
      await AuthService.signIn(
        usernameOrEmail: _username.text,
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
      appBar: AppBar(title: const Text('تسجيل الدخول')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_person_outlined, size: 70, color: gold),
                  const SizedBox(height: 18),
                  const Text(
                    'أهلاً بعودتك',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 26),
                  TextFormField(
                    controller: _username,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                      helperText: 'المسؤول الأول يمكنه الدخول ببريده الإلكتروني',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'يرجى إدخال اسم المستخدم'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidePassword,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                          () => _hidePassword = !_hidePassword,
                        ),
                      ),
                    ),
                    validator: (v) => v == null || v.isEmpty
                        ? 'يرجى إدخال كلمة المرور'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: _working ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _working
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,
                            ),
                          )
                        : const Text('تسجيل الدخول',
                            style: TextStyle(fontSize: 17)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'يستخدم الجميع شاشة الدخول نفسها، وتُحدد الصلاحيات تلقائيًا.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF756C5D)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
