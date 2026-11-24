import 'package:material_ui/material_ui.dart';

import '../models/activity_item.dart';
import '../services/activities_service.dart';
import '../widgets/masjid_media.dart';
import '../widgets/masjid_section_style.dart';

class ActivityEditorDialog extends StatefulWidget {
  final ActivityItem? existing;
  const ActivityEditorDialog({super.key, this.existing});

  @override
  State<ActivityEditorDialog> createState() => _ActivityEditorDialogState();
}

class _ActivityEditorDialogState extends State<ActivityEditorDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _organizer;
  late final TextEditingController _capacity;
  DateTime? _departure;
  DateTime? _return;
  DateTime? _hideAt;
  late String _kind;
  late String _registrationMode;
  late bool _isVisible;
  late bool _isOpen;
  MosqueImageDraft? _newImage;
  late String _oldPath;
  bool _removePhoto = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _title = TextEditingController(text: item?.title ?? '');
    _description = TextEditingController(text: item?.description ?? '');
    _location = TextEditingController(text: item?.location ?? '');
    _organizer = TextEditingController(text: item?.organizer ?? '');
    _capacity = TextEditingController(text: item?.capacity?.toString() ?? '');
    _departure = item?.departureAt;
    _return = item?.returnAt;
    _hideAt = item?.hideAt;
    _kind = item?.kind ?? 'trip';
    _registrationMode = item?.registrationMode ?? 'approval';
    _isVisible = item?.isVisible ?? true;
    _isOpen = item?.isOpen ?? true;
    _oldPath = item?.imagePath ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _organizer.dispose();
    _capacity.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickPhoto() async {
    try {
      final selected = await MosqueMedia.chooseImage();
      if (selected != null && mounted) {
        setState(() {
          _newImage = selected;
          _removePhoto = false;
        });
      }
    } on FormatException catch (e) {
      _notice(e.message);
    } catch (error) {
      _notice(MosqueMedia.errorMessage(error));
    }
  }

  Future<void> _selectDate(String field) async {
    final current = field == 'departure'
        ? _departure
        : field == 'return'
        ? _return
        : _hideAt;
    final initial = current ?? DateTime.now().add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (field == 'departure') _departure = chosen;
      if (field == 'return') _return = chosen;
      if (field == 'hide') _hideAt = chosen;
    });
  }

  Widget _dateControl(
    String field,
    String label,
    IconData icon,
    DateTime? value,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _selectDate(field),
            icon: Icon(icon, size: 18),
            label: Text(
              value == null
                  ? label
                  : '$label: ${ActivityItem.formatDate(value)}',
            ),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: 'إزالة الموعد',
            onPressed: _busy
                ? null
                : () => setState(() {
                    if (field == 'departure') _departure = null;
                    if (field == 'return') _return = null;
                    if (field == 'hide') _hideAt = null;
                  }),
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );
  }

  Future<void> _save() async {
    if (_busy || !_key.currentState!.validate()) return;
    if (_return != null &&
        _departure != null &&
        _return!.isBefore(_departure!)) {
      _notice('موعد العودة يجب أن يكون بعد موعد الانطلاق');
      return;
    }
    setState(() => _busy = true);
    String? uploaded;
    var uploadingImage = false;
    final id = widget.existing?.id ?? ActivitiesService.newId();
    try {
      if (_newImage != null) {
        uploadingImage = true;
        uploaded = await MosqueMedia.upload('activities', id, _newImage!);
        uploadingImage = false;
      }
      final path = uploaded ?? (_removePhoto ? '' : _oldPath);
      await ActivitiesService.save(
        id: id,
        title: _title.text,
        kind: _kind,
        description: _description.text,
        location: _location.text,
        organizer: _organizer.text,
        departureAt: _departure,
        returnAt: _return,
        hideAt: _hideAt,
        capacity: _capacity.text.trim().isEmpty
            ? null
            : int.parse(_capacity.text.trim()),
        imagePath: path,
        isOpen: _isOpen,
        isVisible: _isVisible,
        registrationMode: _registrationMode,
      );
      if (_oldPath.isNotEmpty && _oldPath != path) {
        await MosqueMedia.deleteSafely(_oldPath);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (uploaded != null) await MosqueMedia.deleteSafely(uploaded);
      _notice(
        uploadingImage
            ? MosqueMedia.errorMessage(e)
            : ActivitiesService.error(e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          const Text('🚌  '),
          Expanded(
            child: Text(
              widget.existing == null
                  ? 'إضافة نشاط أو رحلة'
                  : 'تعديل النشاط أو الرحلة',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'trip', label: Text('رحلة 🚌')),
                    ButtonSegment(value: 'activity', label: Text('نشاط 🌿')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _busy
                      ? null
                      : (choice) => setState(() => _kind = choice.first),
                ),
                const SizedBox(height: 17),
                TextFormField(
                  controller: _title,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'اسم النشاط أو الرحلة',
                    prefixIcon: Icon(Icons.edit_note_outlined),
                  ),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'أدخل اسم النشاط أو الرحلة'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _description,
                  maxLength: 6000,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل النشاط',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _organizer,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'المشرف أو المنظّم',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _location,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'المكان أو الوجهة',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'عدد الأماكن',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  validator: (v) {
                    final raw = v?.trim() ?? '';
                    if (raw.isEmpty) return null;
                    final n = int.tryParse(raw);
                    return n == null || n < 1 || n > 2000
                        ? 'أدخل عددًا بين 1 و2000'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                _dateControl(
                  'departure',
                  'موعد الانطلاق',
                  Icons.event_outlined,
                  _departure,
                ),
                const SizedBox(height: 8),
                _dateControl(
                  'return',
                  'موعد العودة',
                  Icons.event_available_outlined,
                  _return,
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
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _newImage!.bytes,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                ] else if (_oldPath.isNotEmpty && !_removePhoto) ...[
                  const SizedBox(height: 10),
                  MosqueStoredImage(path: _oldPath, height: 150),
                ],
                if (_newImage != null || (_oldPath.isNotEmpty && !_removePhoto))
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _newImage = null;
                            _removePhoto = true;
                          }),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('إزالة الصورة'),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _registrationMode,
                  decoration: const InputDecoration(
                    labelText: 'طريقة التسجيل',
                    prefixIcon: Icon(Icons.how_to_reg_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'approval',
                      child: Text('بموافقة المسؤول'),
                    ),
                    DropdownMenuItem(
                      value: 'automatic',
                      child: Text('تسجيل تلقائي'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v != null) setState(() => _registrationMode = v);
                        },
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isOpen,
                  onChanged: _busy ? null : (v) => setState(() => _isOpen = v),
                  title: const Text('فتح التسجيل'),
                  subtitle: Text(
                    'يمكن إغلاق التسجيل دون إخفاء النشاط',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isVisible,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _isVisible = v),
                  title: const Text('إظهار النشاط للمستخدمين'),
                  secondary: const Icon(
                    Icons.visibility_outlined,
                    color: MosquePalette.emerald,
                  ),
                ),
                const SizedBox(height: 7),
                _dateControl(
                  'hide',
                  'إخفاء تلقائيًا في موعد',
                  Icons.visibility_off_outlined,
                  _hideAt,
                ),
                Text(
                  'يُخفى النشاط في الموعد المحدد دون حذف بيانات المسجلين.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
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
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ النشاط'),
        ),
      ],
    );
  }
}
