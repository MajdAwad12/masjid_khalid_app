import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/courses_service.dart';
import '../widgets/course_status_badge.dart';

class CourseRegistrationsPage extends StatefulWidget {
  final Course course;

  const CourseRegistrationsPage({super.key, required this.course});

  @override
  State<CourseRegistrationsPage> createState() =>
      _CourseRegistrationsPageState();
}

class _CourseRegistrationsPageState extends State<CourseRegistrationsPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  String? _busyId;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('course_registrations')
        .where('courseId', isEqualTo: widget.course.id)
        .snapshots();
    // Upgrade counters in legacy courses from the actual registration records.
    if (widget.course.rejectedCount == 0) {
      _ensureCounts();
    }
  }

  Future<void> _ensureCounts() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('courses')
          .doc(widget.course.id)
          .get();
      if (doc.exists && !(doc.data()?.containsKey('rejectedCount') ?? false)) {
        await CoursesService.reconcileCounts(widget.course.id);
      }
    } catch (_) {
      // List still loads. An admin can trigger reconciliation separately.
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addParticipant() async {
    if (_busyId != null) return;
    // The dialog owns its TextEditingControllers. Disposing them as soon as
    // showDialog resolves is too early: the closing transition can still use
    // its text fields while the route is animating out.
    final entry = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _ManualCourseParticipantDialog(),
    );
    if (entry == null || !mounted) return;
    setState(() => _busyId = '__adding__');
    try {
      await CoursesService.addParticipant(
        courseId: widget.course.id,
        fullName: entry['name']!,
        phone: entry['phone'],
      );
      _notice('تمت إضافة المشارك بنجاح');
    } catch (error) {
      _notice(CoursesService.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _decide(String registrationId, String decision) async {
    if (_busyId != null) return;
    final accept = decision == 'accepted';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(accept ? 'الموافقة على التسجيل' : 'رفض التسجيل'),
        content: Text(
          accept
              ? 'هل تريد قبول أو إعادة قبول طلب التسجيل؟'
              : 'هل تريد رفض الطلب وتحديث حالة صاحبه إلى مرفوض؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = registrationId);
    try {
      final notified = await CoursesService.decide(
        courseId: widget.course.id,
        registrationId: registrationId,
        decision: decision,
      );
      _notice(
        notified
            ? 'تم حفظ القرار وطلب إرسال الإشعار'
            : 'تم حفظ القرار، لكن تعذر إرسال الإشعار. '
                  'يمكن للمستفيد مراجعة حالة الطلب من التطبيق.',
      );
    } catch (error) {
      _notice(CoursesService.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _resend(String registrationId) async {
    if (_busyId != null) return;
    setState(() => _busyId = registrationId);
    try {
      final notified = await CoursesService.resend(
        courseId: widget.course.id,
        registrationId: registrationId,
      );
      _notice(
        notified
            ? 'تم طلب إرسال الإشعار مجددًا'
            : 'تعذر إرسال الإشعار، تحقق من إعدادات جهاز المستفيد.',
      );
    } catch (error) {
      _notice(CoursesService.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Widget _filterChip(String filter, String label, int count) {
    final selected = _statusFilter == filter;
    final color = filter == 'accepted'
        ? CourseStatusBadge.accepted(context)
        : filter == 'rejected'
        ? CourseStatusBadge.rejected(context)
        : CourseStatusBadge.pending(context);
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      selectedColor: color.withValues(alpha: 0.11),
      onSelected: (_) => setState(() => _statusFilter = filter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المسجلين')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          final registrations = snapshot.data?.docs.toList() ?? [];
          registrations.sort((a, b) {
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];
            final aMillis = aTime is Timestamp
                ? aTime.millisecondsSinceEpoch
                : 0;
            final bMillis = bTime is Timestamp
                ? bTime.millisecondsSinceEpoch
                : 0;
            return bMillis.compareTo(aMillis);
          });
          int count(String status) => registrations
              .where((doc) => doc.data()['status'] == status)
              .length;
          final visibleRegistrations = _statusFilter == 'all'
              ? registrations
              : registrations
                    .where((doc) => doc.data()['status'] == _statusFilter)
                    .toList();
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: [
                  Text(
                    widget.course.title,
                    style: TextStyle(
                      fontSize: 21,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'عدد الطلبات: ${registrations.length}  ·  '
                    'المقبولون: ${count('accepted')}  ·  '
                    'المرفوضون: ${count('rejected')}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 15),
                  FilledButton.icon(
                    onPressed: _busyId == null ? _addParticipant : null,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('إضافة مشارك يدويًا'),
                  ),
                  const SizedBox(height: 16),
                  // Everyone with admin permissions sees the same records
                  // from Firestore, independently of which admin added them.
                  if (snapshot.hasData && !snapshot.hasError) ...[
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _filterChip('all', 'الكل', registrations.length),
                        _filterChip('accepted', 'المقبولون', count('accepted')),
                        _filterChip(
                          'pending',
                          'قيد الانتظار',
                          count('pending'),
                        ),
                        _filterChip('rejected', 'المرفوضون', count('rejected')),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (snapshot.hasError)
                    const Center(child: Text('تعذر تحميل قائمة المسجلين'))
                  else if (!snapshot.hasData)
                    const Center(child: CircularProgressIndicator())
                  else if (visibleRegistrations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          registrations.isEmpty
                              ? 'لا توجد تسجيلات لهذه الدورة'
                              : 'لا توجد تسجيلات في هذا القسم',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    ...visibleRegistrations.map((doc) {
                      final data = doc.data();
                      final name = (data['fullName'] ?? '').toString();
                      final phone = (data['phone'] ?? '').toString();
                      final status = (data['status'] ?? 'pending').toString();
                      final notificationState =
                          (data['notificationState'] ?? '').toString();
                      final manual = data['source'] == 'admin';
                      final busy = _busyId == doc.id;
                      final statusColor = status == 'accepted'
                          ? CourseStatusBadge.accepted(context)
                          : status == 'rejected'
                          ? CourseStatusBadge.rejected(context)
                          : CourseStatusBadge.pending(context);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF252B27)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF404A42)
                                : const Color(0xFFE9DFC9),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.0 : 0.035,
                              ),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
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
                              const SizedBox(height: 11),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  CourseStatusBadge(
                                    label: status == 'accepted'
                                        ? 'تم قبول الطلب'
                                        : status == 'rejected'
                                        ? 'تم رفض الطلب'
                                        : 'بانتظار الموافقة',
                                    color: statusColor,
                                    icon: status == 'accepted'
                                        ? Icons.check_circle_outline
                                        : status == 'rejected'
                                        ? Icons.cancel_outlined
                                        : Icons.schedule_outlined,
                                  ),
                                  if (manual)
                                    CourseStatusBadge(
                                      label: 'إضافة يدوية',
                                      color: CourseStatusBadge.pending(context),
                                      icon: Icons.person_add_alt_outlined,
                                    ),
                                ],
                              ),
                              if (status != 'pending') ...[
                                const SizedBox(height: 9),
                                Text(
                                  manual &&
                                          (data['fcmToken'] == null ||
                                              data['fcmToken'] == '')
                                      ? 'أُضيف يدويًا دون إشعار تلقائي'
                                      : notificationState == 'sent'
                                      ? 'تم طلب إرسال الإشعار'
                                      : 'لم يتم تأكيد إرسال الإشعار',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 13),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (status != 'accepted')
                                    FilledButton.icon(
                                      onPressed: _busyId == null
                                          ? () => _decide(doc.id, 'accepted')
                                          : null,
                                      icon: const Icon(Icons.check_outlined),
                                      label: const Text('قبول'),
                                    ),
                                  if (status != 'rejected')
                                    OutlinedButton.icon(
                                      onPressed: _busyId == null
                                          ? () => _decide(doc.id, 'rejected')
                                          : null,
                                      icon: const Icon(Icons.close_outlined),
                                      label: const Text('رفض'),
                                    ),
                                  if (status != 'pending' &&
                                      data['fcmToken'] is String &&
                                      (data['fcmToken'] as String).isNotEmpty)
                                    TextButton.icon(
                                      onPressed: _busyId == null
                                          ? () => _resend(doc.id)
                                          : null,
                                      icon: const Icon(
                                        Icons.notifications_outlined,
                                      ),
                                      label: const Text('إعادة إرسال الإشعار'),
                                    ),
                                ],
                              ),
                              if (busy)
                                const LinearProgressIndicator(minHeight: 2),
                            ],
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
}

/// The editing controllers must outlive the dialog's reverse pop animation.
/// Owning them in the dialog State ensures they are disposed only when its
/// widget is actually removed from the tree.
class _ManualCourseParticipantDialog extends StatefulWidget {
  const _ManualCourseParticipantDialog();

  @override
  State<_ManualCourseParticipantDialog> createState() =>
      _ManualCourseParticipantDialogState();
}

class _ManualCourseParticipantDialogState
    extends State<_ManualCourseParticipantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(<String, String>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text('إضافة مشارك يدويًا'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'يمكن للمسؤول إضافة مشارك حتى لو اكتمل العدد أو أُغلق التسجيل.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'أدخل اسم المشارك'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phone,
                  maxLength: 20,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) return null;
                    final digits = raw.replaceAll(RegExp(r'\D'), '');
                    return digits.length >= 8 && digits.length <= 15
                        ? null
                        : 'أدخل رقم هاتف صحيحًا';
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('إضافة'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
