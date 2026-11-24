import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../models/activity_item.dart';
import '../services/homework_service.dart';
import '../widgets/masjid_media.dart';
import '../widgets/masjid_section_style.dart';

class HomeworkEditorDialog extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>>? existing;
  const HomeworkEditorDialog({super.key, this.existing});

  @override
  State<HomeworkEditorDialog> createState() => _HomeworkEditorDialogState();
}

class _HomeworkEditorDialogState extends State<HomeworkEditorDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _group;
  DateTime? _dueAt;
  late bool _isVisible;
  late String _oldPath;
  bool _removeOldImage = false;
  MosqueImageDraft? _newImage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final doc = widget.existing?.data() ?? <String, dynamic>{};
    _title = TextEditingController(text: (doc['title'] ?? '').toString());
    _body = TextEditingController(text: (doc['body'] ?? '').toString());
    _group = TextEditingController(text: (doc['groupName'] ?? '').toString());
    final timestamp = doc['dueAt'];
    _dueAt = timestamp is Timestamp ? timestamp.toDate().toLocal() : null;
    _oldPath = (doc['imagePath'] ?? '').toString();
    _isVisible = doc['isVisible'] != false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _group.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _pickDue() async {
    final initial = _dueAt ?? DateTime.now().add(const Duration(days: 7));
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(
      () => _dueAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _pickPhoto() async {
    try {
      final image = await MosqueMedia.chooseImage();
      if (image != null && mounted) {
        setState(() {
          _newImage = image;
          _removeOldImage = false;
        });
      }
    } on FormatException catch (e) {
      _notice(e.message);
    } catch (error) {
      _notice(MosqueMedia.errorMessage(error));
    }
  }

  Future<void> _save() async {
    if (_busy || !_key.currentState!.validate()) return;
    setState(() => _busy = true);
    final id = widget.existing?.id ?? HomeworkService.newId();
    String? uploaded;
    var uploadingImage = false;
    try {
      if (_newImage != null) {
        uploadingImage = true;
        uploaded = await MosqueMedia.upload('homework', id, _newImage!);
        uploadingImage = false;
      }
      final path = uploaded ?? (_removeOldImage ? '' : _oldPath);
      await HomeworkService.save(
        id: id,
        title: _title.text,
        body: _body.text,
        groupName: _group.text,
        dueAt: _dueAt,
        imagePath: path,
        isVisible: _isVisible,
      );
      if (_oldPath.isNotEmpty && _oldPath != path) {
        await MosqueMedia.deleteSafely(_oldPath);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (uploaded != null) await MosqueMedia.deleteSafely(uploaded);
      _notice(
        uploadingImage
            ? MosqueMedia.errorMessage(e)
            : 'تعذر حفظ الوظيفة. تحقق من الاتصال وصلاحيات المسؤول.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          const Text('📚  '),
          Expanded(
            child: Text(
              widget.existing == null
                  ? 'نشر وظيفة بيتية'
                  : 'تعديل الوظيفة البيتية',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 530,
        child: SingleChildScrollView(
          child: Form(
            key: _key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الوظيفة',
                    prefixIcon: Icon(Icons.edit_note_outlined),
                  ),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'أدخل عنوان الوظيفة' : null,
                ),
                const SizedBox(height: 9),
                TextFormField(
                  controller: _group,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'الدورة أو المجموعة',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _body,
                  maxLength: 20000,
                  minLines: 7,
                  maxLines: 16,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل الوظيفة والتعليمات ✏️',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pickDue,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          _dueAt == null
                              ? 'موعد التسليم'
                              : 'التسليم: ${ActivityItem.formatDate(_dueAt!)}',
                        ),
                      ),
                    ),
                    if (_dueAt != null)
                      IconButton(
                        tooltip: 'إزالة الموعد',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _dueAt = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('إضافة صورة 🖼️'),
                ),
                if (_newImage != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      _newImage!.bytes,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                ] else if (_oldPath.isNotEmpty && !_removeOldImage) ...[
                  const SizedBox(height: 10),
                  MosqueStoredImage(path: _oldPath, height: 160),
                ],
                if (_newImage != null ||
                    (_oldPath.isNotEmpty && !_removeOldImage))
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _newImage = null;
                            _removeOldImage = true;
                          }),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('إزالة الصورة'),
                  ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار الوظيفة للمستخدمين'),
                  secondary: const Icon(
                    Icons.visibility_outlined,
                    color: MosquePalette.plum,
                  ),
                  value: _isVisible,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _isVisible = v),
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
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ الوظيفة'),
        ),
      ],
    );
  }
}
