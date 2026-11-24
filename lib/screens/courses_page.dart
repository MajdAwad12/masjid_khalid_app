import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/course_notifications_service.dart';
import '../services/courses_service.dart';
import '../widgets/app_theme.dart';
import '../widgets/course_status_badge.dart';
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
    final scheme = Theme.of(context).colorScheme;
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
                const Icon(
                  Icons.school_outlined,
                  size: 42,
                  color: AppColors.gold,
                ),
                const SizedBox(height: 10),
                Text(
                  'الدورات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'اكتشف الدورات وسجّل للمشاركة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
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
                        onEdit: () => _openEditor(course),
                        onRegistrations: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                CourseRegistrationsPage(course: course),
                          ),
                        ),
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
  final VoidCallback onEdit;
  final VoidCallback onRegistrations;

  const _CourseCard({
    required this.course,
    required this.isAdmin,
    required this.onRegister,
    required this.onEdit,
    required this.onRegistrations,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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

    // Match the white announcement cards in light mode and their dark
    // surface variant in night mode, without changing the global theme.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252B27) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF404A42) : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.0 : 0.035),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.title,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 19,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isAdmin && !course.isVisible) ...[
              const SizedBox(height: 10),
              CourseStatusBadge(
                label: 'مخفية عن المستخدمين',
                color: scheme.onSurfaceVariant,
                icon: Icons.visibility_off_outlined,
              ),
            ],
            const SizedBox(height: 11),
            CourseStatusBadge(
              label: statusText,
              color: statusColor,
              icon: isFull
                  ? Icons.people_alt_outlined
                  : isClosed
                  ? Icons.lock_outline
                  : Icons.check_circle_outline,
            ),
            if (course.description.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                course.description,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.55),
              ),
            ],
            if (details.isNotEmpty) ...[const SizedBox(height: 15), ...details],
            if (isAdmin) ...[
              const SizedBox(height: 10),
              Text(
                'بانتظار الموافقة: ${course.pendingCount}  ·  '
                'المقبولون: ${course.acceptedCount}  ·  '
                'المرفوضون: ${course.rejectedCount}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 10,
                runSpacing: 9,
                children: [
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRegistrations,
                    icon: const Icon(Icons.people_outline),
                    label: const Text('إدارة المسجلين'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 17),
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
    );
  }

  Widget _detail(IconData icon, String label, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.gold),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
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
