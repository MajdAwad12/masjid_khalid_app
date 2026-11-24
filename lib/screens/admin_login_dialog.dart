import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_service.dart';
import '../widgets/app_theme.dart';
import 'forgot_password_page.dart';

/// Admin-only sign-in, reached from public Settings (not an app entry gate).
class AdminLoginDialog extends StatefulWidget {
  const AdminLoginDialog({super.key});

  @override
  State<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<AdminLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  static const _cooldownStorageKey = 'admin_login_blocked_until_ms';

  bool _busy = false;
  bool _showPassword = false;
  bool _restoringCooldown = true;
  String? _error;
  DateTime? _blockedUntil;
  Timer? _cooldownTimer;

  int get _remainingSeconds {
    final blockedUntil = _blockedUntil;
    if (blockedUntil == null) return 0;
    final difference = blockedUntil.difference(DateTime.now()).inMilliseconds;
    return difference > 0 ? (difference + 999) ~/ 1000 : 0;
  }

  bool get _blocked => _remainingSeconds > 0;

  String get _remainingTimeLabel {
    final seconds = _remainingSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainder = seconds % 60;
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(hours)}:${pad(minutes)}:${pad(remainder)}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCooldown());
  }

  Future<void> _restoreCooldown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cooldownStorageKey);
      if (!mounted) return;
      if (timestamp != null &&
          timestamp > DateTime.now().millisecondsSinceEpoch) {
        _activateCooldown(DateTime.fromMillisecondsSinceEpoch(timestamp));
      } else if (timestamp != null) {
        await prefs.remove(_cooldownStorageKey);
      }
    } catch (_) {
      // Local storage is only for UI continuity; server rules are authoritative.
    } finally {
      if (mounted) setState(() => _restoringCooldown = false);
    }
  }

  Future<void> _saveCooldown(DateTime until) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cooldownStorageKey, until.millisecondsSinceEpoch);
    } catch (_) {
      // The server enforces the cooldown even if local storage fails.
    }
  }

  Future<void> _clearSavedCooldown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cooldownStorageKey);
    } catch (_) {
      // No need to block further use of the UI on storage failure.
    }
  }

  void _activateCooldown(DateTime until) {
    _cooldownTimer?.cancel();
    setState(() {
      _blockedUntil = until;
      _error = null;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds == 0) {
        timer.cancel();
        setState(() {
          _blockedUntil = null;
          _error = null;
        });
        unawaited(_clearSavedCooldown());
      } else {
        setState(() {});
      }
    });
  }

  void _handleLoginError(Object error) {
    if (!mounted) return;
    if (error is FirebaseFunctionsException &&
        error.code == 'resource-exhausted') {
      final details = error.details;
      if (details is Map && details['waitSeconds'] is num) {
        final seconds = (details['waitSeconds'] as num).ceil();
        if (seconds > 0) {
          final until = DateTime.now().add(Duration(seconds: seconds));
          _activateCooldown(until);
          unawaited(_saveCooldown(until));
          return;
        }
      }
    }
    setState(() => _error = AuthService.errorMessage(error));
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy ||
        _blocked ||
        _restoringCooldown ||
        _formKey.currentState?.validate() != true) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.signInAdmin(
        username: _username.text,
        password: _password.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      _handleLoginError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: AppColors.gold),
          SizedBox(width: 9),
          Expanded(child: Text('دخول المسؤول')),
        ],
      ),
      content: SizedBox(
        width: 390,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _username,
                  enabled: !_busy && !_blocked && !_restoringCooldown,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    final username = value?.trim() ?? '';
                    if (username.isEmpty) return 'أدخل اسم المستخدم';
                    if (username.length > 128) return 'اسم المستخدم طويل جدًا';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  enabled: !_busy && !_blocked && !_restoringCooldown,
                  textDirection: TextDirection.ltr,
                  obscureText: !_showPassword,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'إخفاء' : 'إظهار',
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: (_busy || _blocked || _restoringCooldown)
                          ? null
                          : () =>
                                setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (value) =>
                      (value?.isNotEmpty ?? false) ? null : 'أدخل كلمة المرور',
                ),
                if (_blocked) ...[
                  const SizedBox(height: 12),
                  Text(
                    'تم إيقاف تسجيل الدخول مؤقتًا. الوقت المتبقي: $_remainingTimeLabel',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          final navigator = Navigator.of(
                            context,
                            rootNavigator: true,
                          );
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ForgotPasswordPage(),
                            ),
                          );
                        },
                  child: const Text('نسيت كلمة المرور؟'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: (_busy || _blocked || _restoringCooldown) ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 19,
                  width: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('دخول'),
        ),
      ],
    );
  }
}
