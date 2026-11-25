import 'package:material_ui/material_ui.dart';

import 'legal_page.dart';
import 'delete_account_dialog.dart';

import '../auth/auth_service.dart';
import '../services/theme_controller.dart';
import '../widgets/admin_recovery_email_card.dart';
import '../widgets/masjid_section_style.dart';
import '../widgets/public_notifications_settings_card.dart';
import 'admin_login_dialog.dart';
import 'admins_management_page.dart';
import 'change_admin_password_dialog.dart';

/// Settings for every visitor, with additional controls for authenticated admins.
class AccountSettingsPage extends StatelessWidget {
  final bool isAdmin;
  final String managerName;
  final String managerPhone;
  final String privacyUrl;

  const AccountSettingsPage({
    super.key,
    required this.isAdmin,
    required this.managerName,
    required this.managerPhone,
    this.privacyUrl = '',
  });

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService.signOut();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تسجيل الخروج، حاول مرة أخرى')),
        );
      }
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => const ChangeAdminPasswordDialog(),
    );
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    // A scrollable layout keeps sign-out accessible on smaller devices.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 44),
          children: [
            const MosqueSectionHeader(
              emoji: '⚙️',
              title: 'الإعدادات',
              subtitle: 'خيارات بسيطة تناسب الجميع',
              accent: MosquePalette.amber,
            ),
            const SizedBox(height: 26),
            const _SettingsHeading(
              'الدعم والمساعدة',
              Icons.support_agent_outlined,
            ),
            const SizedBox(height: 10),
            MosqueCardShell(
              accent: MosquePalette.amber,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'لأي استفسار أو مشكلة تقنية، يمكنك التواصل مع مسؤول المسجد.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'اسم المسؤول: $managerName',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'رقم الهاتف: $managerPhone',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            for (final privacy in [true, false]) ...[
              const SizedBox(height: 12),
              MosqueCardShell(
                accent: MosquePalette.amber,
                child: ListTile(
                  leading: Icon(
                    privacy
                        ? Icons.privacy_tip_outlined
                        : Icons.description_outlined,
                  ),
                  title: Text(privacy ? 'سياسة الخصوصية' : 'شروط الاستخدام'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LegalPage(
                        privacy: privacy,
                        contact: '$managerName · $managerPhone',
                        webUrl: privacy ? privacyUrl : '',
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const _SettingsHeading('المظهر', Icons.palette_outlined),
            const SizedBox(height: 10),
            MosqueCardShell(
              accent: MosquePalette.amber,
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeController,
                builder: (context, mode, _) => SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  secondary: Icon(
                    mode == ThemeMode.dark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    color: MosquePalette.amber,
                  ),
                  title: const Text('الوضع الليلي'),
                  subtitle: Text(
                    mode == ThemeMode.dark
                        ? 'مفعّل الآن'
                        : 'الوضع النهاري مفعّل',
                  ),
                  value: mode == ThemeMode.dark,
                  onChanged: (value) => themeController.setDarkMode(value),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SettingsHeading(
              'الإشعارات',
              Icons.notifications_active_outlined,
            ),
            const SizedBox(height: 10),
            const PublicNotificationsSettingsCard(),
            if (isAdmin) ...[
              const SizedBox(height: 24),
              const _SettingsHeading('إدارة النظام', Icons.shield_outlined),
              const SizedBox(height: 10),
              const AdminRecoveryEmailCard(),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف حسابي نهائياً'),
                onTap: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const DeleteAccountDialog(),
                ),
              ),
              const SizedBox(height: 12),
              MosqueCardShell(
                accent: MosquePalette.ocean,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  leading: const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: MosquePalette.ocean,
                  ),
                  title: const Text('إدارة المسؤولين'),
                  subtitle: const Text('إضافة مسؤول وإلغاء الصلاحيات'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminsManagementPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              MosqueCardShell(
                accent: MosquePalette.ocean,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  leading: const Icon(
                    Icons.lock_outline,
                    color: MosquePalette.ocean,
                  ),
                  title: const Text('تغيير كلمة المرور'),
                  subtitle: const Text('تحديث كلمة مرور حساب المسؤول'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _changePassword(context),
                ),
              ),
            ],
            const SizedBox(height: 28),
            if (isAdmin)
              OutlinedButton.icon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout_rounded, size: 19),
                label: const Text('تسجيل الخروج'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: .45)),
                  backgroundColor: scheme.error.withValues(
                    alpha: dark ? .11 : .045,
                  ),
                  minimumSize: const Size(0, 54),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            else
              Center(
                child: TextButton.icon(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => const AdminLoginDialog(),
                  ),
                  icon: Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  label: Text(
                    'دخول المسؤول',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeading extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SettingsHeading(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: MosquePalette.amber),
        const SizedBox(width: 9),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
