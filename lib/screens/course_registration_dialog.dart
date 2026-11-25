import '../widgets/registration_privacy_actions.dart';

import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/course_notifications_service.dart';
import '../services/courses_service.dart';

class CourseRegistrationDialog extends StatefulWidget {
  final Course course;

  const CourseRegistrationDialog({super.key, required this.course});

  @override
  State<CourseRegistrationDialog> createState() =>
      _CourseRegistrationDialogState();
}

class _CourseRegistrationDialogState extends State<CourseRegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final notifications = CourseNotificationsService.instance;
      final token = await notifications.requestToken();
      if (!mounted) return;
      if (token == null) {
        final continueWithoutPush = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تعذر تفعيل الإشعارات'),
            content: const Text(
              'يمكنك إكمال التسجيل، لكن قد لا يصلك إشعار القبول أو الرفض. '
              'يمكنك مراجعة حالة طلبك من "تسجيلاتي" في التطبيق، '
              'أو التواصل مع إدارة المسجد.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('رجوع'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('متابعة'),
              ),
            ],
          ),
        );
        if (!mounted || continueWithoutPush != true) return;
      }
      final key = await notifications.deviceKey();
      await CoursesService.register(
        courseId: widget.course.id,
        fullName: _name.text,
        phone: _phone.text,
        deviceKey: key,
        fcmToken: token,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(CoursesService.errorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('التسجيل في الدورة'),
      content: SizedBox(
        width: 470,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.course.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'لا تحتاج إلى حساب. أدخل اسمك ورقم هاتفك الصحيح للتسجيل.',
                ),
                const SizedBox(height: 16),
                const Text(guardianNotice),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) {
                    final n = v?.trim().length ?? 0;
                    return n >= 3 && n <= 80 ? null : 'يرجى إدخال الاسم الكامل';
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
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
                  'ستستخدم بياناتك للتسجيل وإدارة الطلب فقط. '
                  'وسيطلب التطبيق إذنك لإرسال الإشعارات.',
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
          onPressed: _busy ? null : _register,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تأكيد التسجيل'),
        ),
      ],
    );
  }
}
