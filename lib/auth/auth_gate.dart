import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/welcome_page.dart';

// Decides which screen to display according to Firebase Auth.
class AuthGate extends StatelessWidget {
  final Widget Function(bool isAdmin) appBuilder;

  const AuthGate({super.key, required this.appBuilder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.idTokenChanges(),
      builder: (context, authSnapshot) {
        // Firebase is checking the authentication state.
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingPage();
        }

        // Authentication error.
        if (authSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('تعذر التحقق من الحساب')),
          );
        }

        final user = authSnapshot.data;

        // No authenticated user.
        if (user == null) {
          return const WelcomePage();
        }

        // Check admin permission using Firebase Custom Claims.
        return FutureBuilder<IdTokenResult>(
          future: user.getIdTokenResult(),
          builder: (context, tokenSnapshot) {
            if (tokenSnapshot.connectionState != ConnectionState.done) {
              return const _LoadingPage();
            }

            if (tokenSnapshot.hasError || !tokenSnapshot.hasData) {
              return const Scaffold(
                body: Center(child: Text('تعذر التحقق من الصلاحيات')),
              );
            }

            // Only users with admin:true are administrators.
            final isAdmin = tokenSnapshot.data!.claims?['admin'] == true;

            // Open the app with the correct permissions.
            return appBuilder(isAdmin);
          },
        );
      },
    );
  }
}

// Loading indicator.
class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
