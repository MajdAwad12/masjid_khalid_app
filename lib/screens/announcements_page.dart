
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

// Application colors
class AnnouncementColors {
  static const gold = Color(0xFFA16602);
  static const dark = Color(0xFF342F27);
  static const muted = Color(0xFF756C5D);
  static const border = Color(0xFFE9DFC9);
  static const paleGold = Color(0xFFF9EED7);
}

// Announcement data model
class Announcement {
  final int id;
  final String title;
  final String description;
  final DateTime publishedAt;
  final bool isImportant;
  final Uint8List? imageBytes;

  const Announcement({
    required this.id,
    required this.title,
    required this.description,
    required this.publishedAt,
    required this.isImportant,
    this.imageBytes,
  });
}

// Main announcements screen
class AnnouncementsPage extends StatefulWidget {
  final bool isAdmin;

  const AnnouncementsPage({
    super.key,
    this.isAdmin = false,
  });

  @override
  State<AnnouncementsPage> createState() =>
      _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  // Temporary demo data. Firebase will replace this list later.
  final List<Announcement> _announcements = [
    Announcement(
      id: 1,
      title: 'إعلان تجريبي مهم',
      description:
      'هذا مثال على إعلان مهم داخل التطبيق. '
          'يمكن للمسؤول نشر الإعلانات وتحديثها.',
      publishedAt: DateTime(2026, 11, 17),
      isImportant: true,
    ),
    Announcement(
      id: 2,
      title: 'إعلان تجريبي',
      description:
      'هذا نموذج لإعلان عادي يمكن أن يحتوي '
          'على نص وصورة وتاريخ النشر.',
      publishedAt: DateTime(2026, 11, 16),
      isImportant: false,
    ),
  ];

  int _nextId = 3;

  // Add or edit an announcement
  Future<void> _openEditor([Announcement? existing]) async {
    if (!widget.isAdmin) return;

    final result = await Navigator.of(context).push<AnnouncementDraft>(
      MaterialPageRoute(
        builder: (_) => AnnouncementEditorPage(
          existing: existing,
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      if (existing == null) {
        _announcements.add(
          Announcement(
            id: _nextId++,
            title: result.title,
            description: result.description,
            publishedAt: DateTime.now(),
            isImportant: result.isImportant,
            imageBytes: result.imageBytes,
          ),
        );
      } else {
        final index = _announcements.indexWhere(
              (item) => item.id == existing.id,
        );

        if (index != -1) {
          _announcements[index] = Announcement(
            id: existing.id,
            title: result.title,
            description: result.description,
            publishedAt: existing.publishedAt,
            isImportant: result.isImportant,
            imageBytes: result.imageBytes,
          );
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null
              ? 'تمت إضافة الإعلان بنجاح'
              : 'تم تعديل الإعلان بنجاح',
        ),
      ),
    );
  }

  // Delete an announcement after confirmation
  Future<void> _deleteAnnouncement(
      Announcement announcement,
      ) async {
    if (!widget.isAdmin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الإعلان'),
        content: const Text(
          'هل أنت متأكد من حذف هذا الإعلان؟',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _announcements.removeWhere(
            (item) => item.id == announcement.id,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حذف الإعلان'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Newest announcements first
    final sortedAnnouncements =
    List<Announcement>.from(_announcements)
      ..sort(
            (a, b) =>
            b.publishedAt.compareTo(a.publishedAt),
      );

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 22,
      ),
      children: [
        const Center(
          child: Column(
            children: [
              Icon(
                Icons.campaign_outlined,
                color: AnnouncementColors.gold,
                size: 40,
              ),
              SizedBox(height: 12),
              Text(
                'إعلانات المسجد',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: AnnouncementColors.dark,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'تابع آخر الإعلانات والمستجدات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AnnouncementColors.muted,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Only admins can add announcements
        if (widget.isAdmin) ...[
          FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
            label: const Text('إضافة إعلان'),
            style: FilledButton.styleFrom(
              backgroundColor: AnnouncementColors.gold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        const Text(
          'بيانات تجريبية',
          style: TextStyle(
            fontSize: 12,
            color: AnnouncementColors.muted,
          ),
        ),

        const SizedBox(height: 12),

        if (sortedAnnouncements.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 55,
                    color: AnnouncementColors.gold,
                  ),
                  SizedBox(height: 15),
                  Text(
                    'لا توجد إعلانات حاليًا',
                    style: TextStyle(
                      fontSize: 17,
                      color: AnnouncementColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...sortedAnnouncements.map(
                (announcement) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AnnouncementCard(
                announcement: announcement,
                isAdmin: widget.isAdmin,
                onEdit: () => _openEditor(announcement),
                onDelete: () =>
                    _deleteAnnouncement(announcement),
              ),
            ),
          ),
      ],
    );
  }
}

// One announcement card
class AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final date = announcement.publishedAt;

    final formattedDate =
        '${date.day}/${date.month}/${date.year}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: announcement.isImportant
              ? const Color(0xFFE3C991)
              : AnnouncementColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (announcement.isImportant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AnnouncementColors.paleGold,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'إعلان مهم',
                    style: TextStyle(
                      color: AnnouncementColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              const Spacer(),

              // Admin-only editing controls
              if (isAdmin) ...[
                IconButton(
                  tooltip: 'تعديل الإعلان',
                  icon: const Icon(Icons.edit_outlined),
                  color: AnnouncementColors.gold,
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'حذف الإعلان',
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.redAccent,
                  onPressed: onDelete,
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),

          Text(
            announcement.title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AnnouncementColors.dark,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            announcement.description,
            style: const TextStyle(
              fontSize: 15,
              height: 1.8,
              color: AnnouncementColors.muted,
            ),
          ),

          // Optional announcement image
          if (announcement.imageBytes != null) ...[
            const SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                announcement.imageBytes!,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ],

          const SizedBox(height: 16),

          const Divider(
            color: AnnouncementColors.border,
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: AnnouncementColors.gold,
              ),
              const SizedBox(width: 8),
              Text(
                formattedDate,
                style: const TextStyle(
                  color: AnnouncementColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Data returned from the add/edit form
class AnnouncementDraft {
  final String title;
  final String description;
  final bool isImportant;
  final Uint8List? imageBytes;

  const AnnouncementDraft({
    required this.title,
    required this.description,
    required this.isImportant,
    required this.imageBytes,
  });
}

// Add/edit announcement form
class AnnouncementEditorPage extends StatefulWidget {
  final Announcement? existing;

  const AnnouncementEditorPage({
    super.key,
    this.existing,
  });

  @override
  State<AnnouncementEditorPage> createState() =>
      _AnnouncementEditorPageState();
}

class _AnnouncementEditorPageState
    extends State<AnnouncementEditorPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  late bool _isImportant;

  Uint8List? _imageBytes;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );

    _descriptionController = TextEditingController(
      text: widget.existing?.description ?? '',
    );

    _isImportant = widget.existing?.isImportant ?? false;
    _imageBytes = widget.existing?.imageBytes;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // Select an optional image from the gallery
  Future<void> _pickImage() async {
    if (_pickingImage) return;

    setState(() => _pickingImage = true);

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        _imageBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر اختيار الصورة. حاول مرة أخرى.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pickingImage = false);
      }
    }
  }

  // Validate form and return the result
  void _saveAnnouncement() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      AnnouncementDraft(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        isImportant: _isImportant,
        imageBytes: _imageBytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'تعديل الإعلان' : 'إضافة إعلان',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 12),

              // Title input
              TextFormField(
                controller: _titleController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'عنوان الإعلان',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return 'يرجى كتابة عنوان الإعلان';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Description input
              TextFormField(
                controller: _descriptionController,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'محتوى الإعلان',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return 'يرجى كتابة محتوى الإعلان';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 12),

              // Important announcement checkbox
              CheckboxListTile(
                title: const Text('إعلان مهم'),
                subtitle: const Text(
                  'إظهار علامة مميزة للإعلان',
                ),
                value: _isImportant,
                onChanged: (value) {
                  setState(() {
                    _isImportant = value ?? false;
                  });
                },
                controlAffinity:
                ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 18),

              // Optional image picker
              OutlinedButton.icon(
                onPressed: _pickingImage
                    ? null
                    : _pickImage,
                icon: const Icon(
                  Icons.add_photo_alternate_outlined,
                ),
                label: Text(
                  _pickingImage
                      ? 'جارٍ اختيار الصورة...'
                      : 'إضافة صورة (اختياري)',
                ),
              ),

              if (_imageBytes != null) ...[
                const SizedBox(height: 15),

                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    _imageBytes!,
                    height: 190,
                    fit: BoxFit.contain,
                  ),
                ),

                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _imageBytes = null;
                    });
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('إزالة الصورة'),
                ),
              ],

              const SizedBox(height: 30),

              // Save button
              FilledButton.icon(
                onPressed: _saveAnnouncement,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  isEditing
                      ? 'حفظ التعديلات'
                      : 'نشر الإعلان',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor:
                  AnnouncementColors.gold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
