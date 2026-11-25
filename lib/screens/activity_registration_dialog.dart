import '../widgets/registration_privacy_actions.dart';

import 'package:material_ui/material_ui.dart';

import '../models/activity_item.dart';
import '../services/activities_service.dart';
import '../services/course_notifications_service.dart';

class ActivityRegistrationDialog extends StatefulWidget {
  final ActivityItem activity;
  const ActivityRegistrationDialog({super.key, required this.activity});

  @override
  State<ActivityRegistrationDialog> createState() =>
      _ActivityRegistrationDialogState();
}

class _ActivityRegistrationDialogState
    extends State<ActivityRegistrationDialog> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final notifications = CourseNotificationsService.instance;
      final token = await notifications.requestToken();
      if (!mounted) return;
      if (token == null) {
        final agree = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تعذر تفعيل الإشعارات'),
            content: const Text(
              'يمكنك التسجيل دون إشعارات، ثم متابعة'
              ' حالة كل شخص من «تسجيلاتي» على هذا الجهاز.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('رجوع'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('متابعة'),
              ),
            ],
          ),
        );
        if (!mounted || agree != true) return;
      }
      final key = await notifications.deviceKey();
      await ActivitiesService.register(
        activityId: widget.activity.id,
        fullName: _name.text,
        phone: _phone.text,
        deviceKey: key,
        fcmToken: token,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ActivitiesService.error(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    title: const Text('📝 التسجيل للمشاركة'),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.activity.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'لا تحتاج إلى حساب. يمكنك تسجيل نفسك أو أحد أفراد أسرتك.',
              ),
              const SizedBox(height: 16),
              const Text(guardianNotice),
              TextFormField(
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v?.trim().length ?? 0) < 3 ? 'أدخل الاسم الكامل' : null,
              ),
              const SizedBox(height: 7),
              TextFormField(
                controller: _phone,
                maxLength: 20,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return digits.length >= 8 && digits.length <= 15
                      ? null
                      : 'أدخل رقم هاتف صحيحًا';
                },
              ),
              const SizedBox(height: 8),
              Text(
                'تُستخدم البيانات لإدارة التسجيل فقط، وسنطلب الإذن '
                'قبل إرسال الإشعارات.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'جارٍ التسجيل...' : 'تأكيد التسجيل'),
      ),
    ],
  );
}
