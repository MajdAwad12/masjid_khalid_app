import 'package:material_ui/material_ui.dart';

import '../services/public_notifications_service.dart';

/// Opt-out / opt-in of public mosque updates without creating an account.
class PublicNotificationsSettingsCard extends StatefulWidget {
  const PublicNotificationsSettingsCard({super.key});

  @override
  State<PublicNotificationsSettingsCard> createState() =>
      _PublicNotificationsSettingsCardState();
}

class _PublicNotificationsSettingsCardState
    extends State<PublicNotificationsSettingsCard> {
  bool _enabled = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = await PublicNotificationsService.instance.enabled();
    if (mounted) {
      setState(() {
        _enabled = current;
        _busy = false;
      });
    }
  }

  Future<void> _set(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final success = await PublicNotificationsService.instance.setEnabled(value);
    final current = await PublicNotificationsService.instance.enabled();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _enabled = current;
    });
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'لتلقي الإشعارات، اسمح بها من إعدادات الهاتف ثم حاول مجددًا.'
                : 'تعذر إلغاء الاشتراك الآن. سنحاول عند فتح التطبيق مجددًا.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: SwitchListTile.adaptive(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: const Text('إشعارات أخبار المسجد'),
      subtitle: const Text(
        'الإعلانات والدورات والأنشطة والرحلات والوظائف البيتية الجديدة',
      ),
      value: _enabled,
      onChanged: _busy ? null : _set,
    ),
  );
}
