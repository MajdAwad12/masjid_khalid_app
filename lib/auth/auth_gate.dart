import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

/// Always renders the public application. Admin privileges are granted only
/// after Firebase Custom Claims and the Firestore profile both verify them.
class AuthGate extends StatefulWidget {
  final Widget Function(bool isAdmin) appBuilder;

  const AuthGate({super.key, required this.appBuilder});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileSubscription;
  bool _isAdmin = false;
  int _authCheck = 0;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.idTokenChanges().listen(
      _onAuthChanged,
      onError: (Object error) => _onAuthChanged(null),
    );
  }

  Future<void> _onAuthChanged(User? user) async {
    final check = ++_authCheck;
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    if (!mounted || check != _authCheck) return;

    // Revoke privileged UI immediately; the public app remains mounted.
    if (_isAdmin) setState(() => _isAdmin = false);
    if (user == null) return;

    try {
      final token = await user.getIdTokenResult();
      if (!mounted ||
          check != _authCheck ||
          FirebaseAuth.instance.currentUser?.uid != user.uid ||
          token.claims?['admin'] != true) {
        return;
      }

      _profileSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
            (snapshot) {
              if (!mounted ||
                  check != _authCheck ||
                  FirebaseAuth.instance.currentUser?.uid != user.uid) {
                return;
              }
              final allowed = snapshot.data()?['role'] == 'admin';
              if (_isAdmin != allowed) {
                setState(() => _isAdmin = allowed);
              }
            },
            onError: (Object error) {
              if (mounted && check == _authCheck && _isAdmin) {
                setState(() => _isAdmin = false);
              }
            },
          );
    } catch (_) {
      // If credentials/profile cannot be verified, stay in public mode.
    }
  }

  @override
  void dispose() {
    ++_authCheck;
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.appBuilder(_isAdmin);
}
