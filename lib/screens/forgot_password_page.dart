import 'package:cloud_functions/cloud_functions.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../widgets/app_theme.dart';

/// Only administrators have accounts; preserve the verified-email recovery flow.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  bool _sending = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _formKey.currentState?.validate() != true) return;
    setState(() {
      _sending = true;
      _submitted = false;
      _error = null;
    });
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('requestAdminPasswordRecovery')
          .call({'username': _username.text.trim().toLowerCase()});
      if (mounted) setState(() => _submitted = true);
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'resource-exhausted'
              ? 'طلبات كثيرة، حاول لاحقًا'
              : 'تعذر إرسال الطلب الآن',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر الاتصال، حاول لاحقًا');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('استعادة حساب المسؤول')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_reset, color: AppColors.gold, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'استعادة كلمة مرور المسؤول',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'سيُرسل رابط الاستعادة إلى بريد الاسترداد المؤكد للحساب، إن وُجد.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _username,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                  validator: (v) =>
                      AuthService.usernamePattern.hasMatch(
                        v?.trim().toLowerCase() ?? '',
                      )
                      ? null
                      : 'اسم مستخدم غير صحيح',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: Text(
                    _sending ? 'جارٍ الإرسال...' : 'إرسال رابط الاستعادة',
                  ),
                ),
                if (_submitted) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'إذا كان الحساب مؤهلًا للاستعادة، فستصل رسالة إلى بريد الاسترداد المؤكد.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
