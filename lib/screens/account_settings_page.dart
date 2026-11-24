import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../services/theme_controller.dart';
import '../widgets/admin_recovery_email_card.dart';
import '../widgets/app_theme.dart';
import 'admin_login_dialog.dart';
import 'admins_management_page.dart';
import 'change_admin_password_dialog.dart';

/// Settings for every visitor, with additional controls for authenticated admins.
class AccountSettingsPage extends StatelessWidget {
  final bool isAdmin;
  final String managerName;
  final String managerPhone;

  const AccountSettingsPage({
    super.key,
    required this.isAdmin,
    required this.managerName,
    required this.managerPhone,
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: bounds.maxHeight - 44),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.settings_outlined,
                      color: AppColors.gold,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الإعدادات',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        color: scheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'الدعم الفني',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 9),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(17),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'في حال وجود مشكلة تقنية في التطبيق، يرجى التواصل مع مسؤول المسجد.',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'اسم المسؤول: $managerName',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'رقم الهاتف: $managerPhone',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'المظهر',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 9),
                    Card(
                      child: ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeController,
                        builder: (context, mode, child) =>
                            SwitchListTile.adaptive(
                              secondary: Icon(
                                mode == ThemeMode.dark
                                    ? Icons.dark_mode_outlined
                                    : Icons.light_mode_outlined,
                                color: scheme.primary,
                              ),
                              title: const Text('الوضع الليلي'),
                              subtitle: Text(
                                mode == ThemeMode.dark
                                    ? 'مفعّل'
                                    : 'الوضع النهاري مفعّل',
                              ),
                              value: mode == ThemeMode.dark,
                              onChanged: (enabled) =>
                                  themeController.setDarkMode(enabled),
                            ),
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(height: 24),
                      Text(
                        'إدارة النظام',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 9),
                      const AdminRecoveryEmailCard(),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.admin_panel_settings_outlined,
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
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('تغيير كلمة المرور'),
                          subtitle: const Text('اختياري في أي وقت'),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => _changePassword(context),
                        ),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.center,
                      child: isAdmin
                          ? TextButton.icon(
                              onPressed: () => _signOut(context),
                              icon: const Icon(Icons.logout, size: 17),
                              label: const Text('تسجيل الخروج'),
                            )
                          : TextButton.icon(
                              onPressed: () => showDialog<bool>(
                                context: context,
                                builder: (_) => const AdminLoginDialog(),
                              ),
                              icon: Icon(
                                Icons.lock_outline,
                                size: 15,
                                color: scheme.onSurfaceVariant,
                              ),
                              label: Text(
                                'دخول المسؤول',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                minimumSize: const Size(0, 38),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
