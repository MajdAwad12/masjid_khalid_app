import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../models/activity_item.dart';
import '../services/homework_service.dart';
import '../widgets/masjid_media.dart';
import '../widgets/masjid_section_style.dart';
import 'homework_editor_dialog.dart';

class HomeworkPage extends StatefulWidget {
  final bool isAdmin;
  const HomeworkPage({super.key, required this.isAdmin});

  @override
  State<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends State<HomeworkPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    final docs = FirebaseFirestore.instance.collection('homework');
    _stream = widget.isAdmin
        ? docs.snapshots()
        : docs.where('isVisible', isEqualTo: true).snapshots();
  }

  void _notice(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _edit([DocumentSnapshot<Map<String, dynamic>>? doc]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => HomeworkEditorDialog(existing: doc),
    );
    if (mounted && saved == true) _notice('تم حفظ الوظيفة البيتية بنجاح 📚');
  }

  Future<void> _delete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (_deletingId != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الوظيفة البيتية'),
        content: const Text(
          'هل تريد حذف هذه الوظيفة نهائيًا؟'
          ' يمكنك إخفاؤها من «تعديل» بدلًا من الحذف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    setState(() => _deletingId = doc.id);
    try {
      await HomeworkService.delete(doc.id);
      _notice('تم حذف الوظيفة');
    } catch (_) {
      _notice('تعذر حذف الوظيفة، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final docs = [...?snapshot.data?.docs];
        docs.sort((a, b) {
          final at = a.data()['createdAt'];
          final bt = b.data()['createdAt'];
          return (bt is Timestamp ? bt.millisecondsSinceEpoch : 0).compareTo(
            at is Timestamp ? at.millisecondsSinceEpoch : 0,
          );
        });
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 26),
              children: [
                const MosqueSectionHeader(
                  emoji: '📚✏️',
                  title: 'الوظائف البيتية',
                  subtitle: 'مساحة هادئة للتعلّم والمراجعة والإنجاز',
                  accent: MosquePalette.plum,
                ),
                const SizedBox(height: 24),
                if (widget.isAdmin) ...[
                  FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.post_add_outlined),
                    label: const Text('نشر وظيفة بيتية'),
                  ),
                  const SizedBox(height: 23),
                ],
                if (snapshot.hasError)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('تعذر تحميل الوظائف البيتية'),
                    ),
                  )
                else if (!snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (docs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 44),
                    child: Column(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 48,
                          color: MosquePalette.plum.withValues(alpha: .8),
                        ),
                        const SizedBox(height: 12),
                        const Text('لا توجد وظائف بيتية منشورة حاليًا'),
                      ],
                    ),
                  )
                else
                  ...docs.map(
                    (doc) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _HomeworkNotebookCard(
                        data: doc.data(),
                        isAdmin: widget.isAdmin,
                        deleting: _deletingId == doc.id,
                        onEdit: () => _edit(doc),
                        onDelete: () => _delete(doc),
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

class _HomeworkNotebookCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isAdmin;
  final bool deleting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _HomeworkNotebookCard({
    required this.data,
    required this.isAdmin,
    required this.deleting,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final title = (data['title'] ?? '').toString();
    final body = (data['body'] ?? '').toString();
    final group = (data['groupName'] ?? '').toString();
    final path = (data['imagePath'] ?? '').toString();
    final due = data['dueAt'];
    final published = data['createdAt'];
    final dueAt = due is Timestamp ? due.toDate().toLocal() : null;
    final createdAt = published is Timestamp
        ? published.toDate().toLocal()
        : null;
    return MosqueCardShell(
      accent: MosquePalette.plum,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: MosquePalette.plum.withValues(alpha: .75),
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(22),
                  bottomStart: Radius.circular(22),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 19),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      children: [
                        const MosqueTag(
                          text: '✏️ وظيفة بيتية',
                          color: MosquePalette.plum,
                        ),
                        if (isAdmin && data['isVisible'] == false)
                          const MosqueTag(
                            text: 'مخفية عن المستخدمين',
                            color: Colors.blueGrey,
                            icon: Icons.visibility_off_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.4,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (group.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      MosqueTag(text: '🎓 $group', color: MosquePalette.ocean),
                    ],
                    if (body.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: dark
                              ? MosquePalette.plum.withValues(alpha: .11)
                              : MosquePalette.lavender.withValues(alpha: .58),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          body,
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 15.5,
                            height: 1.78,
                          ),
                        ),
                      ),
                    ],
                    if (body.length > 450) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        icon: const Icon(Icons.chrome_reader_mode_outlined),
                        label: const Text('📖 قراءة الوظيفة كاملة'),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(title),
                            content: SizedBox(
                              width: 520,
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  body,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.8,
                                  ),
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
                      ),
                    ],
                    if (path.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      MosqueStoredImage(path: path, height: 220),
                    ],
                    if (dueAt != null) ...[
                      const SizedBox(height: 15),
                      MosqueTag(
                        text:
                            '⏰ موعد التسليم: '
                            '${ActivityItem.formatDate(dueAt)}',
                        color: dueAt.isBefore(DateTime.now())
                            ? Colors.red.shade400
                            : MosquePalette.ocean,
                      ),
                    ],
                    if (createdAt != null) ...[
                      const SizedBox(height: 12),
                      MosqueMetaLine(
                        icon: Icons.calendar_today_outlined,
                        text:
                            '${createdAt.day.toString().padLeft(2, '0')}/'
                            '${createdAt.month.toString().padLeft(2, '0')}/'
                            '${createdAt.year}',
                        accent: MosquePalette.plum,
                      ),
                    ],
                    if (isAdmin) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 9,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('تعديل'),
                          ),
                          OutlinedButton.icon(
                            onPressed: deleting ? null : onDelete,
                            icon: deleting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.delete_outline),
                            label: const Text('حذف'),
                          ),
                        ],
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
