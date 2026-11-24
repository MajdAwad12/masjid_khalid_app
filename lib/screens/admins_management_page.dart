import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../services/admin_service.dart';
import '../widgets/app_theme.dart';

/// Visible only to active admins. Firestore rules also protect the collection.
class AdminsManagementPage extends StatefulWidget {
  const AdminsManagementPage({super.key});

  @override
  State<AdminsManagementPage> createState() => _AdminsManagementPageState();
}

class _AdminsManagementPageState extends State<AdminsManagementPage> {
  String? _busyUid;

  void _message(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateAdminDialog(),
    );
    if (created == true) {
      _message('تم إنشاء حساب المسؤول بنجاح');
    }
  }

  Future<void> _deactivate(String uid, String username) async {
    if (_busyUid != null || uid == FirebaseAuth.instance.currentUser?.uid) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء صلاحية المسؤول'),
        content: Text(
          'هل تريد إلغاء صلاحية المسؤول $username؟ سيتم تعطيل حسابه ولن يتمكن من تسجيل الدخول كمسؤول.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد إلغاء الصلاحية'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    setState(() => _busyUid = uid);
    try {
      await AdminService.deactivateAdmin(targetUid: uid);
      _message('تم إلغاء صلاحية المسؤول وتعطيل حسابه');
    } catch (error) {
      _message(AdminService.errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busyUid = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة المسؤولين')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'admin')
              .snapshots(),
          builder: (context, snapshot) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'يمكن للمسؤول إنشاء حساب آخر وتحديد اسم المستخدم وكلمة المرور له.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busyUid != null ? null : _add,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('إضافة مسؤول جديد'),
                ),
                const SizedBox(height: 20),
                if (snapshot.hasError)
                  const Center(
                    child: Text('تعذر عرض المسؤولين. تحقق من الصلاحيات.'),
                  )
                else if (!snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.data!.docs.isEmpty)
                  const Center(child: Text('لا توجد حسابات مسؤولين'))
                else
                  ...snapshot.data!.docs.map((doc) {
                    final username = (doc.data()['username'] ?? '').toString();
                    final isSelf =
                        doc.id == FirebaseAuth.instance.currentUser?.uid;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              leading: const Icon(
                                Icons.admin_panel_settings_outlined,
                                color: AppColors.gold,
                              ),
                              title: Text(
                                username.isEmpty ? 'مسؤول' : username,
                              ),
                              subtitle: Text(
                                isSelf ? 'حسابك الحالي' : 'مسؤول نشط',
                              ),
                            ),
                            if (!isSelf)
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton.icon(
                                  onPressed: _busyUid != null
                                      ? null
                                      : () => _deactivate(doc.id, username),
                                  icon: const Icon(
                                    Icons.person_off_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('إلغاء صلاحية المسؤول'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _CreateAdminDialog extends StatefulWidget {
  const _CreateAdminDialog();

  @override
  State<_CreateAdminDialog> createState() => _CreateAdminDialogState();
}

class _CreateAdminDialogState extends State<_CreateAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || _formKey.currentState?.validate() != true) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminService.createAdmin(
        username: _username.text,
        password: _password.text,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = AdminService.errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('إضافة مسؤول جديد'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _username,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم',
                  helperText: '3–20 حرفًا إنجليزيًا صغيرًا أو رقمًا أو _',
                ),
                validator: (v) =>
                    AuthService.usernamePattern.hasMatch(
                      v?.trim().toLowerCase() ?? '',
                    )
                    ? null
                    : 'اسم مستخدم غير صحيح',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                textDirection: TextDirection.ltr,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور التي تختارها للمسؤول',
                  helperText: '12 حرفًا على الأقل. تغييرها لاحقًا اختياري.',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                validator: (v) =>
                    (v?.length ?? 0) >= 12 && (v?.length ?? 0) <= 128
                    ? null
                    : 'استخدم 12–128 حرفًا',
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
        onPressed: _busy ? null : _create,
        child: Text(_busy ? 'جارٍ الإنشاء...' : 'إنشاء الحساب'),
      ),
    ],
  );
}
