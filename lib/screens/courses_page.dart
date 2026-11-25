import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/course_notifications_service.dart';
import '../services/courses_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/course_status_badge.dart';
import '../widgets/masjid_section_style.dart';
import 'course_editor_dialog.dart';
import 'course_registration_dialog.dart';
import 'course_registrations_page.dart';

class CoursesPage extends StatefulWidget {
  final bool isAdmin;

  const CoursesPage({super.key, required this.isAdmin});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  Timer? _clockRefresh;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _stream = widget.isAdmin
        ? FirebaseFirestore.instance
              .collection('courses')
              .orderBy('startAt')
              .snapshots()
        : FirebaseFirestore.instance
              .collection('courses')
              .where('isVisible', isEqualTo: true)
              .snapshots();
    if (widget.isAdmin) {
      _initializeLegacyVisibility();
    }
    _clockRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializeLegacyVisibility() async {
    try {
      final updated = await CoursesService.initializeCourseVisibility();
      if (updated > 0) {
        _notice('تم تجهيز $updated من الدورات القديمة للعرض');
      }
    } catch (error) {
      _notice(
        'تعذر تهيئة الدورات القديمة: ${CoursesService.errorMessage(error)}',
      );
    }
  }

  @override
  void dispose() {
    _clockRefresh?.cancel();
    super.dispose();
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openEditor([Course? course]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CourseEditorDialog(existing: course),
    );
    if (saved == true) {
      _notice(course == null ? 'تم نشر الدورة بنجاح' : 'تم تعديل الدورة بنجاح');
    }
  }

  Future<void> _deleteCourse(Course course) async {
    if (_deletingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الدورة'),
        content: Text(
          'هل تريد حذف «${course.title}» نهائيًا؟ '
          'سيتم حذف جميع تسجيلات المشاركين المرتبطة بها أيضًا، '
          'ولا يمكن التراجع عن الحذف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = course.id);
    try {
      await CoursesService.deleteCourse(course.id);
      _notice('تم حذف الدورة بنجاح');
    } catch (error) {
      _notice('تعذر حذف الدورة: ${CoursesService.errorMessage(error)}');
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _register(Course course) async {
    final status = await showDialog<String>(
      context: context,
      builder: (_) => CourseRegistrationDialog(course: course),
    );
    if (!mounted || status == null) return;
    if (status == 'accepted') {
      _notice('تم تسجيلك بنجاح في الدورة');
    } else {
      _notice('تم إرسال طلبك وهو بانتظار موافقة المسؤول');
    }
  }

  Future<void> _showMyRegistrations(List<Course> courses) async {
    final key = await CourseNotificationsService.instance.existingDeviceKey();
    if (!mounted) return;
    if (key == null) {
      _notice('لم تسجل في أي دورة من هذا الجهاز بعد');
      return;
    }
    final titles = {for (final course in courses) course.id: course.title};
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _MyCourseRegistrationsDialog(deviceKey: key, fallbackTitles: titles),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final all =
            snapshot.data?.docs.map(Course.fromDocument).toList() ?? <Course>[];
        final courses = all;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              children: [
                const MosqueSectionHeader(
                  emoji: '🎓',
                  title: 'الدورات',
                  subtitle: 'تعلّم، شارك، وواصل رحلتك مع المعرفة',
                  accent: MosquePalette.ocean,
                ),
                const SizedBox(height: 24),
                if (widget.isAdmin)
                  ElevatedButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('إضافة دورة جديدة'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: snapshot.hasData
                        ? () => _showMyRegistrations(all)
                        : null,
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('تسجيلاتي'),
                  ),
                const SizedBox(height: 20),
                if (snapshot.hasError)
                  const _CourseEmptyMessage(
                    icon: Icons.error_outline,
                    message: 'تعذر تحميل الدورات. تحقق من الاتصال بالإنترنت.',
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.only(top: 55),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (courses.isEmpty)
                  const _CourseEmptyMessage(
                    icon: Icons.school_outlined,
                    message: 'لا توجد دورات متاحة حاليًا',
                  )
                else
                  ...courses.map(
                    (course) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _CourseCard(
                        course: course,
                        isAdmin: widget.isAdmin,
                        onRegister: () => _register(course),
                        onEdit: _deletingId == null
                            ? () => _openEditor(course)
                            : null,
                        onDelete: _deletingId == null
                            ? () => _deleteCourse(course)
                            : null,
                        isDeleting: _deletingId == course.id,
                        onRegistrations: _deletingId == null
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CourseRegistrationsPage(course: course),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CourseEmptyMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _CourseEmptyMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52),
      child: Column(
        children: [
          Icon(icon, size: 45, color: AppColors.gold),
          const SizedBox(height: 15),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final Course course;
  final bool isAdmin;
  final VoidCallback onRegister;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRegistrations;
  final bool isDeleting;

  const _CourseCard({
    required this.course,
    required this.isAdmin,
    required this.onRegister,
    required this.onEdit,
    required this.onDelete,
    required this.onRegistrations,
    required this.isDeleting,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasEnded =
        course.startAt != null && !course.startAt!.isAfter(DateTime.now());
    final isClosed = !course.isOpen || hasEnded;
    final isFull = course.isFull;
    final canRegister = course.canRegister;
    final statusText = isFull
        ? 'الدورة مكتملة العدد'
        : isClosed
        ? 'التسجيل مغلق'
        : 'التسجيل مفتوح';
    final statusColor = isFull
        ? CourseStatusBadge.full(context)
        : isClosed
        ? CourseStatusBadge.pending(context)
        : CourseStatusBadge.accepted(context);

    final details = <Widget>[
      if (course.teacher.trim().isNotEmpty)
        _detail(Icons.person_outline, 'المحاضر: ${course.teacher}', scheme),
      if (course.startAt != null)
        _detail(
          Icons.event_outlined,
          'الموعد: ${course.formattedStart}',
          scheme,
        ),
      if (course.location.trim().isNotEmpty)
        _detail(Icons.place_outlined, 'المكان: ${course.location}', scheme),
      if (isAdmin && course.capacity != null)
        _detail(
          Icons.groups_outlined,
          'الأماكن المتبقية: ${course.remaining} من ${course.capacity}',
          scheme,
        ),
    ];

    return MosqueCardShell(
      accent: MosquePalette.ocean,
      child: IntrinsicHeight(
        child: Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: MosquePalette.ocean,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(22),
                  bottomStart: Radius.circular(22),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.title,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              CourseStatusBadge(
                                label: statusText,
                                color: statusColor,
                                icon: isFull
                                    ? Icons.people_alt_outlined
                                    : isClosed
                                    ? Icons.lock_outline
                                    : Icons.check_circle_outline,
                              ),
                              if (isAdmin && !course.isVisible)
                                CourseStatusBadge(
                                  label: 'مخفية عن المستخدمين',
                                  color: scheme.onSurfaceVariant,
                                  icon: Icons.visibility_off_outlined,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (course.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: MosquePalette.ocean.withValues(
                        alpha: dark ? .13 : .065,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      course.description,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        height: 1.65,
                      ),
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 15),
                  ...details,
                ],
                if (isAdmin) ...[
                  const SizedBox(height: 12),
                  Divider(color: scheme.outlineVariant),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      MosqueTag(
                        text: '⏳ بانتظار: ${course.pendingCount}',
                        color: MosquePalette.amber,
                      ),
                      MosqueTag(
                        text: '✓ المقبولون: ${course.acceptedCount}',
                        color: MosquePalette.emerald,
                      ),
                      MosqueTag(
                        text: 'المرفوضون: ${course.rejectedCount}',
                        color: scheme.error,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _CourseAdminAction(
                          onPressed: onEdit,
                          icon: Icons.edit_outlined,
                          label: 'تعديل',
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        flex: 5,
                        child: _CourseAdminAction(
                          onPressed: onRegistrations,
                          icon: Icons.people_outline,
                          label: 'إدارة المسجلين',
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        flex: 3,
                        child: _CourseAdminAction(
                          onPressed: onDelete,
                          icon: Icons.delete_outline,
                          label: 'حذف',
                          isLoading: isDeleting,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canRegister ? onRegister : null,
                      icon: const Icon(Icons.how_to_reg_outlined),
                      label: const Text('التسجيل في الدورة'),
                    ),
                  ),
                  if (course.registrationMode == 'approval' && canRegister)
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        'التسجيل يحتاج إلى موافقة المسؤول',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String label, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: MosquePalette.ocean),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Keeps the three course admin actions on one line on narrow phones.
class _CourseAdminAction extends StatelessWidget {
  const _CourseAdminAction({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        minimumSize: const Size(0, 44),
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading)
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 16),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Each person registered from this installation has an independent status.
/// Reopening or refreshing fetches the CURRENT decision from Cloud Functions;
/// nothing is trusted from a local admin or client cache.
class _MyCourseRegistrationsDialog extends StatefulWidget {
  final String deviceKey;
  final Map<String, String> fallbackTitles;

  const _MyCourseRegistrationsDialog({
    required this.deviceKey,
    required this.fallbackTitles,
  });

  @override
  State<_MyCourseRegistrationsDialog> createState() =>
      _MyCourseRegistrationsDialogState();
}

class _MyCourseRegistrationsDialogState
    extends State<_MyCourseRegistrationsDialog> {
  late Future<List<Map<String, dynamic>>> _entries;

  @override
  void initState() {
    super.initState();
    _entries = CoursesService.myRegistrations(widget.deviceKey);
  }

  void _refresh() {
    setState(() {
      _entries = CoursesService.myRegistrations(widget.deviceKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('تسجيلاتي')),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث الحالات',
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _entries,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(CoursesService.errorMessage(snapshot.error!));
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return const Text('لا توجد تسجيلات من هذا الجهاز');
            }
            return SizedBox(
              height: entries.length > 3 ? 360 : entries.length * 107.0,
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(height: 18),
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  final courseTitle = (entry['courseTitle'] ?? '')
                      .toString()
                      .trim();
                  final title = courseTitle.isNotEmpty
                      ? courseTitle
                      : (widget.fallbackTitles[entry['courseId']] ??
                            'دورة لم تعد متاحة');
                  final person = (entry['fullName'] ?? '').toString().trim();
                  final status = entry['status'];
                  final color = status == 'accepted'
                      ? CourseStatusBadge.accepted(context)
                      : status == 'rejected'
                      ? CourseStatusBadge.rejected(context)
                      : CourseStatusBadge.pending(context);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الدورة: $title',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (person.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            'اسم المسجل: $person',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 9),
                        CourseStatusBadge(
                          label: status == 'accepted'
                              ? 'تم قبول الطلب'
                              : status == 'rejected'
                              ? 'تم رفض الطلب'
                              : 'بانتظار موافقة المسؤول',
                          color: color,
                          icon: status == 'accepted'
                              ? Icons.check_circle_outline
                              : status == 'rejected'
                              ? Icons.cancel_outlined
                              : Icons.schedule_outlined,
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}

