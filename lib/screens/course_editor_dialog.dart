import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/courses_service.dart';
import '../widgets/app_theme.dart';

class CourseEditorDialog extends StatefulWidget {
  final Course? existing;

  const CourseEditorDialog({super.key, this.existing});

  @override
  State<CourseEditorDialog> createState() => _CourseEditorDialogState();
}

class _CourseEditorDialogState extends State<CourseEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late final TextEditingController _capacity;
  DateTime? _startAt;
  late String _registrationMode;
  late bool _isOpen;
  late bool _isVisible;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final course = widget.existing;
    _title = TextEditingController(text: course?.title ?? '');
    _description = TextEditingController(text: course?.description ?? '');
    _teacher = TextEditingController(text: course?.teacher ?? '');
    _location = TextEditingController(text: course?.location ?? '');
    _capacity = TextEditingController(text: course?.capacity?.toString() ?? '');
    _startAt = course?.startAt;
    _registrationMode = course?.registrationMode ?? 'approval';
    _isOpen = course?.isOpen ?? true;
    _isVisible = course?.isVisible ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _teacher.dispose();
    _location.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final initial = _startAt ?? DateTime.now().add(const Duration(days: 7));
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
    setState(() {
      _startAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final rawCapacity = _capacity.text.trim();
      await CoursesService.saveCourse(
        existing: widget.existing,
        title: _title.text,
        description: _description.text,
        teacher: _teacher.text,
        location: _location.text,
        startAt: _startAt,
        capacity: rawCapacity.isEmpty ? null : int.parse(rawCapacity),
        registrationMode: _registrationMode,
        isOpen: _isOpen,
        isVisible: _isVisible,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _notice(CoursesService.errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validateCapacity(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final count = int.tryParse(raw);
    if (count == null || count < 1 || count > 1000) {
      return 'أدخل عددًا بين 1 و1000';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          Icon(Icons.school_outlined, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.existing == null ? 'إضافة دورة جديدة' : 'تعديل الدورة',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 510,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 90,
                  decoration: const InputDecoration(
                    labelText: 'اسم الدورة',
                    prefixIcon: Icon(Icons.school_outlined),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'أدخل اسم الدورة'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _description,
                  maxLength: 1200,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'وصف الدورة',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _teacher,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'اسم المحاضر',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _location,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'مكان الدورة',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'عدد الأماكن',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  validator: _validateCapacity,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickStart,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _startAt == null
                        ? 'موعد الدورة'
                        : 'موعد الدورة: ${_format(_startAt!)}',
                  ),
                ),
                if (_startAt != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _startAt = null),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('إزالة الموعد'),
                    ),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _registrationMode,
                  decoration: const InputDecoration(
                    labelText: 'نوع التسجيل',
                    prefixIcon: Icon(Icons.how_to_reg_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'approval',
                      child: Text('يحتاج موافقة المسؤول'),
                    ),
                    DropdownMenuItem(
                      value: 'automatic',
                      child: Text('تسجيل تلقائي'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          if (value != null) _registrationMode = value;
                        }),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('فتح التسجيل'),
                  subtitle: Text(
                    'يمكن إغلاق التسجيل دون حذف الدورة',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  value: _isOpen,
                  activeThumbColor: AppColors.gold,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _isOpen = value),
                ),
                const SizedBox(height: 9),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار الدورة للمستخدمين'),
                  subtitle: Text(
                    'عند الإيقاف تبقى الدورة ظاهرة للمسؤولين فقط',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  secondary: Icon(
                    _isVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.gold,
                  ),
                  value: _isVisible,
                  activeThumbColor: AppColors.gold,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _isVisible = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_outlined),
          label: const Text('حفظ الدورة'),
        ),
      ],
    );
  }

  String _format(DateTime time) {
    String p(int x) => x.toString().padLeft(2, '0');
    return '${p(time.day)}/${p(time.month)}/${time.year}  '
        '${p(time.hour)}:${p(time.minute)}';
  }
}
