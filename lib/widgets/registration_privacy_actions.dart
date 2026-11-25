import 'package:material_ui/material_ui.dart';

import '../services/registration_privacy.dart';

const guardianNotice =
    'عند التسجيل نيابةً عن شخص آخر، احصل على إذنه، '
    'وعلى إذن وليّ الأمر إذا كان المشارك قاصرًا.';

class RegistrationReference extends StatelessWidget {
  const RegistrationReference(this.inbox, {super.key});
  final Future<RegistrationInbox> inbox;

  @override
  Widget build(BuildContext context) => FutureBuilder<RegistrationInbox>(
    future: inbox,
    builder: (context, snapshot) {
      final reference = snapshot.data?.reference ?? '';
      if (reference.isEmpty) return const SizedBox.shrink();
      return SelectableText(
        'مرجع هذا الجهاز للتحقق مع الإدارة: $reference',
        style: Theme.of(context).textTheme.bodySmall,
      );
    },
  );
}

Future<String?> confirmStaffRegistrationAction(
  BuildContext context, {
  required String action,
  required String label,
  required String name,
}) async {
  var checked = false;
  var reference = '';
  final verify = action == 'verify';
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text('$label — $name'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(switch (action) {
                'verify' => 'تحقق من هوية المشارك أو من صلاحية من ينوب عنه عبر وسيلة موثوقة. اطلب منه مرجع الجهاز الظاهر في «تسجيلاتي».',
                'withdraw' => 'يُلغى المقعد وتبقى بيانات التسجيل. لا تستخدم الانسحاب لتنفيذ طلب محو البيانات.',
                _ => 'تُمحى بيانات هذا التسجيل ورمز إشعاراته نهائيًا ويُحرّر المقعد. لا يمكن التراجع عن المحو.',
              }),
              if (verify)
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'مرجع جهاز مقدّم الطلب',
                  ),
                  onChanged: (v) =>
                      update(() => reference = v.trim().toLowerCase()),
                ),
              CheckboxListTile(
                value: checked,
                title: const Text(
                  'تحققت من هوية مقدم الطلب وصلاحيته لهذا الإجراء.',
                ),
                onChanged: (v) => update(() => checked = v == true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed:
                checked &&
                    (!verify || RegExp(r'^[0-9a-f]{12}$').hasMatch(reference))
                ? () => Navigator.pop(dialog, true)
                : null,
            child: Text(label),
          ),
        ],
      ),
    ),
  );
  return ok == true ? reference : null;
}

class RegistrationPrivacyActions extends StatefulWidget {
  const RegistrationPrivacyActions({
    super.key,
    required this.course,
    required this.parentId,
    required this.registrationId,
    required this.needsVerification,
    required this.withdrawn,
    required this.name,
  });
  final bool course;
  final String parentId;
  final String registrationId;
  final String name;
  final bool needsVerification;
  final bool withdrawn;

  @override
  State<RegistrationPrivacyActions> createState() =>
      _RegistrationPrivacyState();
}

class _RegistrationPrivacyState extends State<RegistrationPrivacyActions> {
  bool busy = false;

  Future<void> act(String action, String label) async {
    if (busy) return;
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final prepared = await manageRegistration(
        course: widget.course,
        parentId: widget.parentId,
        registrationId: widget.registrationId,
        action: 'prepare',
      );
      if (!mounted) return;
      final reference = await confirmStaffRegistrationAction(
        context,
        action: action,
        label: label,
        name: widget.name,
      );
      if (reference == null || !mounted) return;
      await manageRegistration(
        course: widget.course,
        parentId: widget.parentId,
        registrationId: widget.registrationId,
        action: action,
        reference: reference,
        generation: prepared['generation'] as String,
        identityChecked: true,
      );
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('تم $label')));
      }
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر إتمام الإجراء. راجع المرجع والسعة والصلاحيات ثم حدّث القائمة.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    children: [
      if (widget.needsVerification)
        TextButton(
          onPressed: busy ? null : () => act('verify', 'تأكيد التحقق'),
          child: const Text('التحقق من المشارك والجهاز'),
        ),
      if (!widget.withdrawn)
        TextButton(
          onPressed: busy ? null : () => act('withdraw', 'تسجيل الانسحاب'),
          child: const Text('تسجيل الانسحاب'),
        ),
      TextButton(
        onPressed: busy ? null : () => act('erase', 'محو بيانات التسجيل'),
        child: const Text('محو بيانات التسجيل'),
      ),
    ],
  );
}
