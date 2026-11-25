import '../services/registration_privacy.dart';
import '../widgets/registration_privacy_actions.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../models/activity_item.dart';
import '../services/activities_service.dart';
import '../services/course_notifications_service.dart';
import '../widgets/masjid_media.dart';
import '../widgets/masjid_section_style.dart';
import 'activity_editor_dialog.dart';
import 'activity_registration_dialog.dart';
import 'activity_registrations_page.dart';

class ActivitiesPage extends StatefulWidget {
  final bool isAdmin;
  const ActivitiesPage({super.key, required this.isAdmin});

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  late final _counts = FirebaseFirestore.instance
      .collection('activity_counts')
      .snapshots(includeMetadataChanges: true);
  Timer? _refreshTimer;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    final base = FirebaseFirestore.instance.collection('activities');
    _stream = widget.isAdmin
        ? base.snapshots()
        : base.where('isVisible', isEqualTo: true).snapshots();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _edit([ActivityItem? item]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ActivityEditorDialog(existing: item),
    );
    if (!mounted || result != true) return;
    _notice(item == null ? 'تم نشر النشاط بنجاح 🌿' : 'تم حفظ التعديلات بنجاح');
  }

  Future<void> _deleteActivity(ActivityItem item) async {
    if (_deletingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف النشاط أو الرحلة'),
        content: Text(
          'هل تريد حذف «${item.title}» نهائيًا؟ '
          'سيتم حذف جميع تسجيلات المشاركين والصورة المرتبطة بها أيضًا، '
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
    setState(() => _deletingId = item.id);
    try {
      await ActivitiesService.deleteActivity(item.id);
      _notice('تم حذف النشاط أو الرحلة بنجاح');
    } catch (error) {
      _notice('تعذر الحذف: ${ActivitiesService.error(error)}');
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _register(ActivityItem item) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => ActivityRegistrationDialog(activity: item),
    );
    if (!mounted || submitted != true) return;
    _notice(
      'استلمنا طلبك. هذه الرسالة لا تؤكد حجز مقعد. تظهر الحالة في «تسجيلاتي» بعد تحقق الإدارة من المشارك والجهاز.',
    );
  }

  Future<void> _showMine() async {
    final deviceKey = await CourseNotificationsService.instance
        .existingDeviceKey();
    if (!mounted) return;
    if (deviceKey == null) {
      _notice('لا توجد تسجيلات من هذا الجهاز');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _MyActivityRegistrationsDialog(deviceKey: deviceKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin) return _programs(null);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _counts,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.hasError || data == null || data.metadata.isFromCache ||
            data.metadata.hasPendingWrites) {
          return _programs(null);
        }
        return _programs({for (final doc in data.docs) doc.id: doc.data()});
      },
    );
  }

  Widget _programs(Map<String, Map<String, dynamic>>? counts) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final items =
            snapshot.data?.docs
                .map((doc) => ActivityItem.fromDocument(
                      doc,
                      counts: counts == null ? null : counts[doc.id] ?? doc.data(),
                    ))
                .where((a) => widget.isAdmin || a.isPublic)
                .toList() ??
            <ActivityItem>[];
        items.sort((a, b) {
          final x = a.departureAt;
          final y = b.departureAt;
          if (x == null && y == null) return a.title.compareTo(b.title);
          if (x == null) return 1;
          if (y == null) return -1;
          return x.compareTo(y);
        });
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 23, 18, 28),
              children: [
                const MosqueSectionHeader(
                  emoji: '🚌🌿',
                  title: 'الأنشطة والرحلات',
                  subtitle: 'لقاءات تجمعنا وذكريات تصنعها الرحلات',
                  accent: MosquePalette.emerald,
                ),
                const SizedBox(height: 24),
                if (widget.isAdmin)
                  FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('إضافة نشاط أو رحلة'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _showMine,
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('تسجيلاتي'),
                  ),
                const SizedBox(height: 24),
                if (snapshot.hasError)
                  const _ActivitiesMessage(
                    icon: Icons.error_outline,
                    message: 'تعذر تحميل الأنشطة والرحلات',
                  )
                else if (!snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (items.isEmpty)
                  const _ActivitiesMessage(
                    icon: Icons.explore_outlined,
                    message: 'لا توجد أنشطة أو رحلات منشورة حاليًا',
                  )
                else
                  ...items.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ActivityCard(
                        item: a,
                        isAdmin: widget.isAdmin,
                        showCounts: counts != null,
                        onEdit: _deletingId == null ? () => _edit(a) : null,
                        onDelete: _deletingId == null
                            ? () => _deleteActivity(a)
                            : null,
                        isDeleting: _deletingId == a.id,
                        onRegister: () => _register(a),
                        onRegistrations: _deletingId == null
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ActivityRegistrationsPage(activity: a),
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

class _ActivitiesMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  const _ActivitiesMessage({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 45),
    child: Column(
      children: [
        Icon(icon, color: MosquePalette.emerald, size: 42),
        const SizedBox(height: 11),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _ActivityCard extends StatelessWidget {
  final ActivityItem item;
  final bool isAdmin;
  final bool showCounts;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onRegister;
  final VoidCallback? onRegistrations;
  final bool isDeleting;
  const _ActivityCard({
    required this.item,
    required this.isAdmin,
    required this.showCounts,
    required this.onEdit,
    required this.onDelete,
    required this.onRegister,
    required this.onRegistrations,
    required this.isDeleting,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = MosquePalette.emerald;
    final closed = item.registrationClosed || !item.isPublic;
    final full = item.isFull;
    return MosqueCardShell(
      accent: accent,
      child: IntrinsicHeight(
        child: Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: accent,
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
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              MosqueTag(
                                text: item.kind == 'trip'
                                    ? 'رحلة جماعية'
                                    : 'نشاط مجتمعي',
                                color: accent,
                              ),
                              if (isAdmin && !item.isPublic)
                                const MosqueTag(
                                  text: 'مخفية عن المستخدمين',
                                  color: Colors.blueGrey,
                                  icon: Icons.visibility_off_outlined,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (item.imagePath.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  MosqueStoredImage(path: item.imagePath, height: 210),
                ],
                if (item.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .075),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      item.description,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        height: 1.65,
                      ),
                    ),
                  ),
                  if (item.description.length > 450)
                    TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(item.title),
                          content: SizedBox(
                            width: 500,
                            child: SingleChildScrollView(
                              child: SelectableText(
                                item.description,
                                style: const TextStyle(height: 1.7),
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('إغلاق'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('قراءة جميع التفاصيل'),
                    ),
                ],
                const SizedBox(height: 14),
                if (item.organizer.trim().isNotEmpty)
                  MosqueMetaLine(
                    icon: Icons.person_outline,
                    text: 'المشرف: ${item.organizer}',
                    accent: accent,
                  ),
                if (item.location.trim().isNotEmpty)
                  MosqueMetaLine(
                    icon: Icons.place_outlined,
                    text: 'المكان: ${item.location}',
                    accent: accent,
                  ),
                if (item.departureAt != null)
                  MosqueMetaLine(
                    icon: Icons.departure_board_outlined,
                    text:
                        'الانطلاق: ${ActivityItem.formatDate(item.departureAt!)}',
                    accent: accent,
                  ),
                if (item.returnAt != null)
                  MosqueMetaLine(
                    icon: Icons.event_available_outlined,
                    text: 'العودة: ${ActivityItem.formatDate(item.returnAt!)}',
                    accent: accent,
                  ),
                if (showCounts && item.capacity != null)
                  MosqueMetaLine(
                    icon: Icons.groups_outlined,
                    text:
                        'الأماكن المتبقية: ${item.remaining} من ${item.capacity}',
                    accent: accent,
                  ),
                if (isAdmin && item.hideAt != null)
                  MosqueMetaLine(
                    icon: Icons.visibility_off_outlined,
                    text:
                        'الإخفاء التلقائي: ${ActivityItem.formatDate(item.hideAt!)}',
                    accent: accent,
                  ),
                const SizedBox(height: 8),
                MosqueTag(
                  text: full
                      ? (item.kind == 'trip'
                            ? 'الرحلة مكتملة العدد'
                            : 'النشاط مكتمل العدد')
                      : closed
                      ? 'التسجيل مغلق'
                      : 'التسجيل مفتوح',
                  color: full
                      ? MosquePalette.ocean
                      : closed
                      ? Colors.blueGrey
                      : Colors.green,
                  icon: full
                      ? Icons.groups_outlined
                      : closed
                      ? Icons.lock_outline
                      : Icons.check_circle_outline,
                ),
                if (showCounts) ...[
                  const SizedBox(height: 12),
                  Text(
                    'بانتظار الموافقة: ${item.pendingCount}  ·  '
                    'المقبولون: ${item.acceptedCount}  ·  '
                    'المرفوضون: ${item.rejectedCount}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (isAdmin) ...[
                  const SizedBox(height: 13),
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _ActivityAdminAction(
                          onPressed: onEdit,
                          icon: Icons.edit_outlined,
                          label: 'تعديل',
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        flex: 5,
                        child: _ActivityAdminAction(
                          onPressed: onRegistrations,
                          icon: Icons.people_outline,
                          label: 'إدارة المسجلين',
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        flex: 3,
                        child: _ActivityAdminAction(
                          onPressed: onDelete,
                          icon: Icons.delete_outline,
                          label: 'حذف',
                          isLoading: isDeleting,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: item.canRegister ? onRegister : null,
                      icon: const Icon(Icons.how_to_reg_outlined),
                      label: const Text('التسجيل للمشاركة'),
                    ),
                  ),
                  if (item.canRegister && item.registrationMode == 'approval')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'التسجيل يحتاج إلى موافقة المسؤول',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
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
}


// Keeps the three admin actions on one line, even on narrow phones.
class _ActivityAdminAction extends StatelessWidget {
  const _ActivityAdminAction({
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

class _MyActivityRegistrationsDialog extends StatefulWidget {
  final String deviceKey;
  const _MyActivityRegistrationsDialog({required this.deviceKey});
  @override
  State<_MyActivityRegistrationsDialog> createState() =>
      _MyActivityRegistrationsDialogState();
}

class _MyActivityRegistrationsDialogState
    extends State<_MyActivityRegistrationsDialog> {
  late Future<RegistrationInbox> _entries;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _entries = ActivitiesService.myRegistrations(widget.deviceKey);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('📋 تسجيلاتي')),
            IconButton(
              onPressed: () => setState(_refresh),
              tooltip: 'تحديث الحالات',
              icon: const Icon(Icons.refresh_outlined),
            ),
          ],
        ),
        RegistrationReference(_entries),
      ],
    ),
    content: SizedBox(
      width: 490,
      child: FutureBuilder<RegistrationInbox>(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(ActivitiesService.error(snapshot.error!));
          }
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final items = snapshot.data!.entries;
          if (items.isEmpty) {
            return const Text('لا توجد حالات متاحة للعرض بعد تحقق الإدارة.');
          }
          return SizedBox(
            height: (items.length * 123.0).clamp(130.0, 385.0),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 18),
              itemBuilder: (context, index) {
                final e = items[index];
                final status = (e['status'] ?? 'pending').toString();
                final name = (e['fullName'] ?? '').toString();
                final title = (e['activityTitle'] ?? 'نشاط').toString();
                final color = status == 'accepted'
                    ? Colors.green
                    : status == 'rejected'
                    ? Colors.red
                    : Colors.blueGrey;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'النشاط أو الرحلة: $title',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text('اسم المسجل: $name'),
                      const SizedBox(height: 9),
                      MosqueTag(
                        color: color,
                        text: status == 'withdrawn'
                            ? 'تم الانسحاب'
                            : status == 'accepted'
                            ? 'تم قبول الطلب'
                            : status == 'rejected'
                            ? 'تم رفض الطلب'
                            : 'بانتظار موافقة المسؤول',
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
