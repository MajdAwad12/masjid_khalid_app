import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import '../screens/welcome_page.dart';

/// One shared entry point; both admins and users sign in the same way.
class AuthGate extends StatelessWidget {
  final Widget Function(bool isAdmin) appBuilder;

  const AuthGate({
    super.key,
    required this.appBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingPage();
        }

        final user = authSnapshot.data;
        if (user == null) return const WelcomePage();

        return FutureBuilder<IdTokenResult>(
          key: ValueKey(user.uid),
          future: user.getIdTokenResult(true),
          builder: (context, tokenSnapshot) {
            if (!tokenSnapshot.hasData) {
              if (tokenSnapshot.hasError) {
                return const _AuthErrorPage();
              }
              return const _LoadingPage();
            }

            final isAdmin = tokenSnapshot.data!.claims?['admin'] == true;
            return appBuilder(isAdmin);
          },
        );
      },
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

class _AuthErrorPage extends StatelessWidget {
  const _AuthErrorPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('تعذر التحقق من الصلاحيات. تحقق من الإنترنت.'),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('العودة إلى تسجيل الدخول'),
                ),
              ],
            ),
          ),
        ),
      );
}
