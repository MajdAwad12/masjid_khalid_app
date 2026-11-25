import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || password.text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await AuthService.deleteOwnAccount(password.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = AuthService.errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('حذف حسابي نهائياً'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ستفقد صلاحية الإدارة فوراً وسيُحذف حسابك وبريد الاسترداد. تبقى منشورات المسجد. إذا كنت المسؤول الوحيد، عيّن مسؤولاً آخر أولاً لضمان استمرار الإدارة. أدخل كلمة المرور لتأكيد الحذف.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: password,
            obscureText: true,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: 'كلمة المرور الحالية',
              errorText: error,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? 'جارٍ الحذف…' : 'تأكيد الحذف النهائي'),
      ),
    ],
  );
}
