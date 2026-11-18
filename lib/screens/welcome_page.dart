import 'package:material_ui/material_ui.dart';

import '../widgets/app_theme.dart';
import '../widgets/app_button.dart';
import 'login_page.dart';
import 'register_page.dart';

// Welcome screen for guests and signed-out users.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Mosque logo.
                  Image.asset(
                    'assets/images/mosque_home.png',
                    height: 225,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.mosque,
                      size: 96,
                      color: AppColors.gold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Mosque name.
                  const Text(
                    'مسجد خالد بن الوليد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.dark,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  const Text(
                    'دار القرآن الكريم',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.gold, fontSize: 16),
                  ),

                  const SizedBox(height: 25),

                  const Text(
                    'أهلاً وسهلاً بك في تطبيق المسجد',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.dark, fontSize: 16),
                  ),

                  const SizedBox(height: 30),

                  // Create a new account.
                  AppButton(
                    text: 'إنشاء حساب جديد',
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RegisterPage(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  // Sign in to an existing account.
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('تسجيل الدخول'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gold,
                      side: const BorderSide(color: AppColors.gold),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Both users and admins use the same sign-in page.
                  const Text(
                    'للمستخدمين والمسؤولين',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
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
