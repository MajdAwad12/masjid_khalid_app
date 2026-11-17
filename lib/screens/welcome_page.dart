import 'package:material_ui/material_ui.dart';
import 'login_page.dart';
import 'register_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  static const Color gold = Color(0xFFA16602);
  static const Color dark = Color(0xFF342F27);
  static const Color background = Color(0xFFFAF8F1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/mosque_home.png',
                    height: 225,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.mosque, size: 96, color: gold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'مسجد خالد بن الوليد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: dark, fontSize: 26, fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'دار القرآن الكريم',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: gold, fontSize: 16),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'أهلاً وسهلاً بك في تطبيق المسجد',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: dark, fontSize: 16),
                  ),
                  const SizedBox(height: 30),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RegisterPage(),
                      ),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('إنشاء حساب جديد'),
                    style: FilledButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginPage(),
                      ),
                    ),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('تسجيل الدخول'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: gold,
                      side: const BorderSide(color: gold),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'للمستخدمين والمسؤولين',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF756C5D), fontSize: 12),
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
