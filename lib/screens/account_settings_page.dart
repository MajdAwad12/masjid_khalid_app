import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/admin_recovery_email_card.dart';
import 'users_management_interface_page.dart';

// Account settings for regular users and administrators.
class AccountSettingsPage extends StatelessWidget {
  final bool isAdmin;

  const AccountSettingsPage({super.key, required this.isAdmin});

  String _value(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  // Sign out through Firebase Authentication.
  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService.signOut();
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الخروج، حاول مرة أخرى')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          children: [
            // Settings header.
            const Icon(
              Icons.settings_outlined,
              color: AppColors.gold,
              size: 50,
            ),

            const SizedBox(height: 12),

            const Text(
              'إعدادات الحساب',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                color: AppColors.dark,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 25),

            // Read the current user's profile from Firestore.
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('تعذر تحميل الملف الشخصي'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final profile = snapshot.data!.data();

                if (profile == null) {
                  return const Text(
                    'لم يتم إنشاء الملف الشخصي لهذا الحساب بعد.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  );
                }

                final firstName = profile['firstName']?.toString() ?? '';
                final lastName = profile['lastName']?.toString() ?? '';

                final fullName = '$firstName $lastName'.trim();

                return Card(
                  color: AppColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName.isEmpty ? 'الملف الشخصي' : fullName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.dark,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text('اسم المستخدم: ${_value(profile['username'])}'),

                        const SizedBox(height: 7),

                        Text('المدينة: ${_value(profile['city'])}'),

                        const SizedBox(height: 7),

                        Text('رقم الهاتف: ${_value(profile['phone'])}'),

                        const SizedBox(height: 7),

                        Text('العمر: ${_value(profile['age'])}'),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 14),

            // Verified recovery email is required for each administrator.
            if (isAdmin) ...[
              const AdminRecoveryEmailCard(),
              const SizedBox(height: 25),

              const Text(
                'إدارة النظام',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.dark,
                ),
              ),

              const SizedBox(height: 12),

              Card(
                color: AppColors.surface,
                child: ListTile(
                  leading: const Icon(
                    Icons.manage_accounts_outlined,
                    color: AppColors.gold,
                  ),
                  title: const Text(
                    'إدارة المستخدمين',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'عرض الحسابات وإدارة صلاحيات المستخدمين',
                  ),
                  trailing: const Icon(
                    Icons.chevron_left,
                    color: AppColors.muted,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const UsersManagementInterfacePage(),
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 25),

            const Divider(),

            const SizedBox(height: 14),

            // Support section.
            const Text(
              'الدعم والمساعدة',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'اسم المسؤول ورقم التواصل سيُضافان بعد تأكيد البيانات.',
              style: TextStyle(color: AppColors.muted),
            ),

            const SizedBox(height: 28),

            // Logout button.
            OutlinedButton.icon(
              onPressed: () => _signOut(context),
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.gold,
                side: const BorderSide(color: AppColors.gold),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
