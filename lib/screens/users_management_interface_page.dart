import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../services/admin_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/app_text_field.dart';

// User management screen, accessible to administrators only.
class UsersManagementInterfacePage extends StatefulWidget {
  const UsersManagementInterfacePage({super.key});

  @override
  State<UsersManagementInterfacePage> createState() =>
      _UsersManagementInterfacePageState();
}

class _UsersManagementInterfacePageState
    extends State<UsersManagementInterfacePage> {
  late final Future<bool> _adminCheck;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  _cooldownsSubscription;

  String _searchText = '';
  String? _busyUid;

  // The server writes lastAttemptAtMs for each target user. Reading these
  // values restores the countdown after leaving or restarting the app.
  final Map<String, DateTime> _serverResetAvailableAt = {};
  final Map<String, DateTime> _localResetAvailableAt = {};
  bool _cooldownsLoaded = false;
  bool _cooldownsFailed = false;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldownsSubscription.cancel();
    super.dispose();
  }

  int _remainingCooldownSeconds(String uid) {
    final serverDeadline = _serverResetAvailableAt[uid];
    final localDeadline = _localResetAvailableAt[uid];
    DateTime? deadline = serverDeadline;

    // Keep the button disabled immediately after a successful reset,
    // even before the Firestore listener receives the new timestamp.
    if (localDeadline != null &&
        (deadline == null || localDeadline.isAfter(deadline))) {
      deadline = localDeadline;
    }

    if (deadline == null) return 0;

    final remainingMs = deadline.difference(DateTime.now()).inMilliseconds;
    return remainingMs > 0 ? (remainingMs + 999) ~/ 1000 : 0;
  }

  void _startResetCooldown(String uid) {
    if (!mounted) return;

    setState(() {
      _localResetAvailableAt[uid] = DateTime.now().add(
        const Duration(seconds: 60),
      );
    });
  }

  void _subscribeToServerCooldowns() {
    _cooldownsSubscription = FirebaseFirestore.instance
        .collection('security_password_reset_limits')
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            final deadlines = <String, DateTime>{};
            final now = DateTime.now();
            for (final doc in snapshot.docs) {
              final raw = doc.data()['lastAttemptAtMs'];
              if (raw is num) {
                final deadline = DateTime.fromMillisecondsSinceEpoch(
                  raw.toInt() + 60000,
                );
                if (deadline.isAfter(now)) deadlines[doc.id] = deadline;
              }
            }

            setState(() {
              _serverResetAvailableAt
                ..clear()
                ..addAll(deadlines);
              _cooldownsLoaded = true;
              _cooldownsFailed = false;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _cooldownsFailed = true;
              _cooldownsLoaded = false;
            });
          },
        );
  }

  @override
  void initState() {
    super.initState();

    _adminCheck = _verifyAdmin();

    _usersStream = FirebaseFirestore.instance.collection('users').snapshots();
    _subscribeToServerCooldowns();

    // Repaint the countdown every second without making network requests.
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final hasDeadlines =
          _localResetAvailableAt.isNotEmpty ||
          _serverResetAvailableAt.isNotEmpty;
      if (!hasDeadlines) return;

      setState(() {
        _localResetAvailableAt.removeWhere(
          (_, deadline) => !deadline.isAfter(now),
        );
        _serverResetAvailableAt.removeWhere(
          (_, deadline) => !deadline.isAfter(now),
        );
      });
    });
  }

  // Check admin permissions from Firebase Authentication.
  Future<bool> _verifyAdmin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return false;

    // Do not force a token refresh during navigation.
    final token = await user.getIdTokenResult();

    return token.claims?['admin'] == true;
  }

  String _value(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  String _fullName(Map<String, dynamic> data) {
    final firstName = data['firstName']?.toString() ?? '';
    final lastName = data['lastName']?.toString() ?? '';

    final name = '$firstName $lastName'.trim();

    return name.isEmpty ? 'مستخدم' : name;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  // Change role through the secure Firebase Cloud Function.
  Future<void> _changeRole({
    required String targetUid,
    required String name,
    required String currentRole,
  }) async {
    if (_busyUid != null) return;

    if (currentRole != 'user' && currentRole != 'admin') {
      _showMessage('تعذر تحديد الدور الحالي للمستخدم');
      return;
    }

    final newRole = currentRole == 'admin' ? 'user' : 'admin';

    // Prevent the current admin from removing their own role.
    if (targetUid == FirebaseAuth.instance.currentUser?.uid &&
        newRole == 'user') {
      _showMessage('لا يمكنك إزالة صلاحيات المسؤول عن حسابك');
      return;
    }

    final promoting = newRole == 'admin';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          promoting ? 'ترقية المستخدم إلى مسؤول' : 'إزالة صلاحيات المسؤول',
        ),
        content: Text(
          promoting
              ? 'هل تريد منح $name صلاحيات مسؤول النظام؟'
              : 'هل تريد إعادة $name إلى مستخدم عادي؟',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _busyUid = targetUid;
    });

    try {
      await AdminService.changeUserRole(targetUid: targetUid, role: newRole);

      _showMessage(
        promoting
            ? 'تم منح صلاحيات المسؤول بنجاح'
            : 'تم تحويل الحساب إلى مستخدم عادي بنجاح',
      );
    } catch (error) {
      _showMessage(AdminService.errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _busyUid = null;
        });
      }
    }
  }

  // Reset password through the secure Firebase Cloud Function.
  Future<void> _resetPassword({
    required String targetUid,
    required String name,
    required String role,
  }) async {
    // Do not open the reset dialog while this user's cooldown is active.
    if (_busyUid != null ||
        !_cooldownsLoaded ||
        _cooldownsFailed ||
        _remainingCooldownSeconds(targetUid) > 0) {
      return;
    }

    // Admin accounts use a separate recovery procedure.
    if (role == 'admin') {
      _showMessage('إعادة تعيين كلمة مرور المسؤول تتطلب إجراء استرداد منفصل');
      return;
    }

    // Collect a new password after identity verification.
    final newPassword = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordResetDialog(userName: name),
    );

    if (!mounted || newPassword == null) return;

    setState(() {
      _busyUid = targetUid;
    });

    try {
      await AdminService.resetUserPassword(
        targetUid: targetUid,
        newPassword: newPassword,
        identityVerified: true,
      );

      // Disable this user's reset button until the cooldown expires.
      _startResetCooldown(targetUid);
      _showMessage('تم تغيير كلمة المرور بنجاح');
    } catch (error) {
      _showMessage(AdminService.errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _busyUid = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المستخدمين')),
      body: FutureBuilder<bool>(
        future: _adminCheck,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Text('تعذر التحقق من صلاحيات الحساب'));
          }

          if (snapshot.data != true) {
            return const Center(
              child: Text(
                'ليس لديك صلاحية الوصول إلى هذه الصفحة',
                textAlign: TextAlign.center,
              ),
            );
          }

          return _buildUsersContent();
        },
      ),
    );
  }

  Widget _buildUsersContent() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.manage_accounts_outlined,
                  color: AppColors.gold,
                  size: 48,
                ),

                const SizedBox(height: 12),

                const Text(
                  'حسابات المستخدمين',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.dark,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 18),

                // Search for users.
                TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchText = value.trim().toLowerCase();
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'البحث عن مستخدم',
                    hintText: 'الاسم أو اسم المستخدم',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _usersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'تعذر تحميل المستخدمين. تحقق من صلاحيات Firestore.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Filter users using their names and usernames.
                final users = snapshot.data!.docs.where((doc) {
                  final data = doc.data();

                  final searchValue =
                      '${_fullName(data)} ${_value(data['username'])}'
                          .toLowerCase();

                  return searchValue.contains(_searchText);
                }).toList();

                if (users.isEmpty) {
                  return const Center(
                    child: Text('لا يوجد مستخدمون مطابقون للبحث'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final userDoc = users[index];
                    final data = userDoc.data();

                    final uid = userDoc.id;
                    final name = _fullName(data);
                    final role = data['role']?.toString() ?? '';

                    final roleText = role == 'admin'
                        ? 'مسؤول'
                        : role == 'user'
                        ? 'مستخدم'
                        : 'غير محدد';

                    final isCurrentUser =
                        uid == FirebaseAuth.instance.currentUser?.uid;

                    final isBusy = _busyUid == uid;
                    final actionsDisabled = _busyUid != null;
                    final resetCooldownSeconds = _remainingCooldownSeconds(uid);

                    return Card(
                      color: AppColors.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: AppColors.paleGold,
                                child: Icon(
                                  Icons.person_outline,
                                  color: AppColors.gold,
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  color: AppColors.dark,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'اسم المستخدم: ${_value(data['username'])}\n'
                                'الدور المسجل: $roleText',
                              ),
                              isThreeLine: true,
                            ),

                            if (isBusy)
                              const Center(child: CircularProgressIndicator())
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed:
                                        actionsDisabled ||
                                            (isCurrentUser &&
                                                role == 'admin') ||
                                            (role != 'user' && role != 'admin')
                                        ? null
                                        : () => _changeRole(
                                            targetUid: uid,
                                            name: name,
                                            currentRole: role,
                                          ),
                                    icon: const Icon(
                                      Icons.admin_panel_settings_outlined,
                                    ),
                                    label: Text(
                                      role == 'admin'
                                          ? 'إزالة صلاحية المسؤول'
                                          : 'ترقية إلى مسؤول',
                                    ),
                                  ),

                                  OutlinedButton.icon(
                                    onPressed:
                                        actionsDisabled ||
                                            role != 'user' ||
                                            !_cooldownsLoaded ||
                                            _cooldownsFailed ||
                                            resetCooldownSeconds > 0
                                        ? null
                                        : () => _resetPassword(
                                            targetUid: uid,
                                            name: name,
                                            role: role,
                                          ),
                                    icon: const Icon(Icons.lock_reset_outlined),
                                    label: Text(
                                      _cooldownsFailed
                                          ? 'تعذر التحقق من مدة الانتظار'
                                          : !_cooldownsLoaded
                                          ? 'جارٍ التحقق من مدة الانتظار'
                                          : resetCooldownSeconds > 0
                                          ? 'انتظر $resetCooldownSeconds ثانية'
                                          : 'إعادة تعيين كلمة المرور',
                                    ),
                                  ),
                                ],
                              ),

                            if (isCurrentUser && role == 'admin')
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'لا يمكنك إزالة صلاحيات حسابك الحالي.',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'تُعرض الأدوار المسجلة في Firestore. '
              'أما الصلاحيات الفعلية فتُحدد بواسطة Firebase Custom Claims.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// Password reset dialog with identity verification confirmation.
class _PasswordResetDialog extends StatefulWidget {
  final String userName;

  const _PasswordResetDialog({required this.userName});

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final _formKey = GlobalKey<FormState>();

  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _identityVerified = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_identityVerified) return;

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('إعادة تعيين كلمة المرور'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'المستخدم: ${widget.userName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              const Text(
                'يجب التحقق من هوية صاحب الحساب قبل تغيير كلمة المرور.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),

              const SizedBox(height: 18),

              AppTextField(
                controller: _password,
                label: 'كلمة المرور الجديدة',
                prefixIcon: Icons.lock_outline,
                textDirection: TextDirection.ltr,
                isPassword: true,
                validator: (value) {
                  if (value == null ||
                      value.length < 12 ||
                      value.length > 128) {
                    return 'كلمة المرور يجب أن تتكون من 12-128 حرفًا';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 14),

              AppTextField(
                controller: _confirmPassword,
                label: 'تأكيد كلمة المرور',
                prefixIcon: Icons.verified_user_outlined,
                textDirection: TextDirection.ltr,
                isPassword: true,
                validator: (value) {
                  if (value != _password.text) {
                    return 'كلمتا المرور غير متطابقتين';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 12),

              CheckboxListTile(
                value: _identityVerified,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'أؤكد أنني تحققت من هوية صاحب الحساب',
                  style: TextStyle(fontSize: 13),
                ),
                onChanged: (value) {
                  setState(() {
                    _identityVerified = value ?? false;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('إلغاء'),
        ),

        FilledButton(
          onPressed: _identityVerified ? _confirm : null,
          child: const Text('تأكيد التغيير'),
        ),
      ],
    );
  }
}
