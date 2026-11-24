import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';

/// Optional: no forced rotation of admin passwords.
class ChangeAdminPasswordDialog extends StatefulWidget {
  const ChangeAdminPasswordDialog({super.key});

  @override
  State<ChangeAdminPasswordDialog> createState() =>
      _ChangeAdminPasswordDialogState();
}

class _ChangeAdminPasswordDialogState extends State<ChangeAdminPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _formKey.currentState?.validate() != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.changeAdminPassword(
        currentPassword: _old.text,
        newPassword: _new.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = AuthService.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تغيير كلمة المرور'),
    content: SizedBox(
      width: 390,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _old,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                ),
                validator: (v) =>
                    (v?.isNotEmpty ?? false) ? null : 'الحقل مطلوب',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _new,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                ),
                validator: (v) =>
                    (v?.length ?? 0) >= 12 && (v?.length ?? 0) <= 128
                    ? null
                    : 'استخدم 12–128 حرفًا',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور الجديدة',
                ),
                validator: (v) =>
                    v == _new.text ? null : 'كلمتا المرور غير متطابقتين',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ'),
      ),
    ],
  );
}
