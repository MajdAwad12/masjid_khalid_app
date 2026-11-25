import '../auth/auth_gate.dart';
import '../widgets/registration_privacy_actions.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../models/activity_item.dart';
import '../services/activities_service.dart';
import '../widgets/masjid_section_style.dart';

class ActivityRegistrationsPage extends StatefulWidget {
  final ActivityItem activity;
  const ActivityRegistrationsPage({super.key, required this.activity});

  @override
  State<ActivityRegistrationsPage> createState() =>
      _ActivityRegistrationsPageState();
}

class _ActivityRegistrationsPageState extends State<ActivityRegistrationsPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  String _filter = 'all';
  String? _busy;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('activity_registrations')
        .where('activityId', isEqualTo: widget.activity.id)
        .snapshots(includeMetadataChanges: true);
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    if (_busy != null) return;
    final input = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _ActivityManualEntryDialog(),
    );
    if (input == null || !mounted) return;
    setState(() => _busy = '_adding');
    try {
      await ActivitiesService.addParticipant(
        widget.activity.id,
        input['name']!,
        input['phone'] ?? '',
      );
      _notice('تمت إضافة المشارك بنجاح');
    } catch (e) {
      _notice(ActivitiesService.error(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _decide(String id, String name, String status) async {
    if (_busy != null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'accepted' ? 'قبول التسجيل' : 'رفض التسجيل'),
        content: Text(
          'تغيير حالة طلب "$name" إلى '
          '${status == 'accepted' ? 'مقبول' : 'مرفوض'}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = id);
    try {
      final notified = await ActivitiesService.decide(
        widget.activity.id,
        id,
        status,
      );
      _notice(
        notified
            ? 'تم حفظ القرار وطلب إرسال الإشعار'
            : 'تم حفظ القرار. يمكن للمشارك مراجعة الحالة من تسجيلاتي.',
      );
    } catch (e) {
      _notice(ActivitiesService.error(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _resend(String id) async {
    if (_busy != null) return;
    setState(() => _busy = id);
    try {
      final ok = await ActivitiesService.resend(widget.activity.id, id);
      _notice(
        ok
            ? 'تم طلب إرسال الإشعار'
            : 'تعذر إرسال الإشعار. تأكد من صلاحية الإشعارات في الجهاز.',
      );
    } catch (e) {
      _notice(ActivitiesService.error(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => AuthGate(
    appBuilder: (isAdmin) => isAdmin
        ? _roster(context)
        : Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text(
                'يلزم اتصال بالخادم وصلاحية إدارة نشطة لعرض القائمة.',
              ),
            ),
          ),
  );

  Widget _roster(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المسجلين')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasData &&
              !serverConfirmedStaffData(
                fromCache: snapshot.data!.metadata.isFromCache,
                pendingWrites: snapshot.data!.metadata.hasPendingWrites,
              )) {
            return const Center(
              child: Text('يلزم اتصال بالخادم لعرض بيانات المشاركين.'),
            );
          }
          final docs = [...?snapshot.data?.docs];
          docs.sort((a, b) {
            final x = a.data()['createdAt'];
            final y = b.data()['createdAt'];
            return (y is Timestamp ? y.millisecondsSinceEpoch : 0).compareTo(
              x is Timestamp ? x.millisecondsSinceEpoch : 0,
            );
          });
          int count(String status) =>
              docs.where((d) => d.data()['status'] == status).length;
          final visible = _filter == 'all'
              ? docs
              : docs.where((d) => d.data()['status'] == _filter).toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    widget.activity.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'المقبولون: ${count('accepted')}  ·  '
                    'قيد الانتظار: ${count('pending')}  ·  '
                    'المرفوضون: ${count('rejected')}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy == null ? _add : null,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('إضافة مشارك يدويًا'),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip('all', 'الكل', docs.length),
                      _chip('pending', 'قيد الانتظار', count('pending')),
                      _chip('accepted', 'المقبولون', count('accepted')),
                      _chip('rejected', 'المرفوضون', count('rejected')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.hasError)
                    const Center(child: Text('تعذر تحميل قائمة المسجلين'))
                  else if (!snapshot.hasData)
                    const Center(child: CircularProgressIndicator())
                  else if (visible.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('لا توجد تسجيلات في هذا القسم'),
                      ),
                    )
                  else
                    ...visible.map((doc) {
                      final d = doc.data();
                      final name = (d['fullName'] ?? '').toString();
                      final phone = (d['phone'] ?? '').toString();
                      final status = (d['status'] ?? 'pending').toString();
                      final color = status == 'accepted'
                          ? Colors.green
                          : status == 'rejected'
                          ? Colors.red
                          : Colors.blueGrey;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: MosqueCardShell(
                          accent: MosquePalette.emerald,
                          child: Padding(
                            padding: const EdgeInsets.all(17),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  SelectableText('رقم الهاتف: $phone'),
                                ],
                                const SizedBox(height: 10),
                                MosqueTag(
                                  text: status == 'unverified'
                                      ? 'بانتظار التحقق'
                                      : status == 'withdrawn'
                                      ? 'منسحب'
                                      : status == 'accepted'
                                      ? 'تم قبول الطلب'
                                      : status == 'rejected'
                                      ? 'تم رفض الطلب'
                                      : 'بانتظار الموافقة',
                                  color: color,
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 9,
                                  runSpacing: 7,
                                  children: [
                                    RegistrationPrivacyActions(
                                      key: ValueKey(doc.id),
                                      course: false,
                                      parentId: widget.activity.id,
                                      registrationId: doc.id,
                                      name: name,
                                      needsVerification:
                                          d['deviceKeyHash'] != null &&
                                          d['deviceVerified'] != true,
                                      withdrawn: status == 'withdrawn',
                                    ),
                                    if (status != 'accepted' &&
                                        status != 'unverified' &&
                                        status != 'withdrawn')
                                      FilledButton.icon(
                                        onPressed: _busy == null
                                            ? () => _decide(
                                                doc.id,
                                                name,
                                                'accepted',
                                              )
                                            : null,
                                        icon: const Icon(Icons.check_outlined),
                                        label: const Text('قبول'),
                                      ),
                                    if (status != 'rejected' &&
                                        status != 'unverified' &&
                                        status != 'withdrawn')
                                      OutlinedButton.icon(
                                        onPressed: _busy == null
                                            ? () => _decide(
                                                doc.id,
                                                name,
                                                'rejected',
                                              )
                                            : null,
                                        icon: const Icon(Icons.close_outlined),
                                        label: const Text('رفض'),
                                      ),
                                    if ([
                                          'accepted',
                                          'rejected',
                                          'withdrawn',
                                        ].contains(status) &&
                                        d['notificationState'] != 'sent' &&
                                        (d['fcmToken'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                      TextButton.icon(
                                        onPressed: _busy == null
                                            ? () => _resend(doc.id)
                                            : null,
                                        icon: const Icon(
                                          Icons.notifications_outlined,
                                        ),
                                        label: const Text(
                                          'إعادة إرسال الإشعار',
                                        ),
                                      ),
                                  ],
                                ),
                                if (_busy == doc.id) ...[
                                  const SizedBox(height: 10),
                                  const LinearProgressIndicator(minHeight: 2),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String key, String label, int count) => ChoiceChip(
    selected: _filter == key,
    label: Text('$label ($count)'),
    onSelected: (_) => setState(() => _filter = key),
  );
}

class _ActivityManualEntryDialog extends StatefulWidget {
  const _ActivityManualEntryDialog();
  @override
  State<_ActivityManualEntryDialog> createState() =>
      _ActivityManualEntryDialogState();
}

class _ActivityManualEntryDialogState
    extends State<_ActivityManualEntryDialog> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('إضافة مشارك يدويًا'),
    content: SizedBox(
      width: 430,
      child: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(guardianNotice),
            TextFormField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'أدخل الاسم الكامل' : null,
            ),
            TextFormField(
              controller: _phone,
              maxLength: 20,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.isEmpty ||
                        digits.length >= 8 && digits.length <= 15
                    ? null
                    : 'أدخل رقم هاتف صحيحًا';
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          Navigator.pop(context, <String, String>{
            'name': _name.text.trim(),
            'phone': _phone.text.trim(),
          });
        },
        child: const Text('إضافة'),
      ),
    ],
  );
}
