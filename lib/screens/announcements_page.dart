import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/masjid_section_style.dart';

// Colors used by the existing mosque application.
class AnnouncementColors {
  static const gold = Color(0xFFA16602);
  static const dark = Color(0xFF342F27);
  static const muted = Color(0xFF756C5D);
  static const border = Color(0xFFE9DFC9);
  static const paleGold = Color(0xFFF9EED7);
}

// Keeps the original API used by main.dart.
class AnnouncementsPage extends StatefulWidget {
  final bool isAdmin;

  const AnnouncementsPage({super.key, this.isAdmin = false});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _announcementsStream;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _announcementsStream = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('publishedAt', descending: true)
        .snapshots();
  }

  void _showNotice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openEditor({
    DocumentSnapshot<Map<String, dynamic>>? document,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AnnouncementEditorDialog(document: document),
    );
    if (!mounted || saved != true) return;
    _showNotice(
      document == null ? 'تم نشر الإعلان بنجاح' : 'تم تعديل الإعلان بنجاح',
    );
  }

  Future<void> _deleteAnnouncement(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    if (_deletingId != null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الإعلان'),
        content: const Text('هل أنت متأكد من حذف هذا الإعلان نهائيًا؟'),
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
    if (confirm != true || !mounted) return;
    setState(() => _deletingId = document.id);
    try {
      final data = document.data() ?? <String, dynamic>{};
      final oldPath = (data['imagePath'] ?? '').toString();
      await document.reference.delete();
      var imageCleanupFailed = false;
      if (_isOwnedImagePath(document.id, oldPath)) {
        try {
          await FirebaseStorage.instance.ref(oldPath).delete();
        } on FirebaseException catch (error) {
          // Missing images need no cleanup; all other failures are reported.
          if (error.code != 'object-not-found') imageCleanupFailed = true;
        }
      }
      _showNotice(
        imageCleanupFailed
            ? 'تم حذف الإعلان، لكن تعذر حذف صورته من التخزين'
            : 'تم حذف الإعلان بنجاح',
      );
    } on FirebaseException catch (error) {
      _showNotice(
        error.code == 'permission-denied'
            ? 'ليس لديك صلاحية لحذف الإعلانات'
            : 'تعذر حذف الإعلان، حاول مرة أخرى',
      );
    } catch (_) {
      _showNotice('تعذر حذف الإعلان، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _announcementsStream,
      builder: (context, snapshot) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
              children: [
                const MosqueSectionHeader(
                  emoji: '📢',
                  title: 'إعلانات المسجد',
                  subtitle: 'تابع آخر الإعلانات والمستجدات',
                  accent: MosquePalette.amber,
                ),
                const SizedBox(height: 24),
                if (widget.isAdmin) ...[
                  FilledButton.icon(
                    onPressed: _deletingId == null ? () => _openEditor() : null,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('إضافة إعلان جديد'),
                  ),
                  const SizedBox(height: 24),
                ],
                if (snapshot.hasError)
                  const _StatusMessage(
                    icon: Icons.error_outline,
                    message: 'تعذر تحميل الإعلانات، حاول لاحقًا',
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.data!.docs.isEmpty)
                  const _StatusMessage(
                    icon: Icons.inbox_outlined,
                    message: 'لا توجد إعلانات حاليًا',
                  )
                else
                  ...snapshot.data!.docs.map(
                    (document) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: AnnouncementCard(
                        data: document.data(),
                        isAdmin: widget.isAdmin,
                        isDeleting: _deletingId == document.id,
                        onEdit: _deletingId == null
                            ? () => _openEditor(document: document)
                            : null,
                        onDelete: _deletingId == null
                            ? () => _deleteAnnouncement(document)
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

// Reusable card for an announcement.
class AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isAdmin;
  final bool isDeleting;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const AnnouncementCard({
    super.key,
    required this.data,
    this.isAdmin = false,
    this.isDeleting = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = (data['title'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final isImportant = data['isImportant'] == true;
    final imageUrl = (data['imageUrl'] ?? '').toString().trim();
    final publishedAt = data['publishedAt'];
    final DateTime? publishedDate = publishedAt is Timestamp
        ? publishedAt.toDate().toLocal()
        : null;

    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return MosqueCardShell(
      accent: MosquePalette.amber,
      child: IntrinsicHeight(
        child: Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700),
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
                if (isImportant) ...[
                  MosqueTag(
                    text: 'إعلان مهم',
                    color: isDark
                        ? const Color(0xFFFFD700)
                        : MosquePalette.amber,
                    icon: Icons.star_outline_rounded,
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: 13),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: MosquePalette.amber.withValues(
                        alpha: isDark ? .12 : .075,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.7,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
                if (imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      imageUrl,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'تعذر عرض الصورة',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (publishedDate != null) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFFFC107), thickness: 2),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      textDirection: TextDirection.ltr,
                      spacing: 180,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          textDirection: TextDirection.ltr,
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                              color: MosquePalette.amber,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '${twoDigits(publishedDate.day)}/'
                              '${twoDigits(publishedDate.month)}/'
                              '${publishedDate.year}',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          textDirection: TextDirection.ltr,
                          children: [
                            const Icon(
                              Icons.access_time_outlined,
                              size: 16,
                              color: MosquePalette.amber,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '${twoDigits(publishedDate.hour)}:'
                              '${twoDigits(publishedDate.minute)}',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (isAdmin) ...[
                  const SizedBox(height: 12),
                  Divider(color: scheme.outlineVariant),
                  const SizedBox(height: 9),
                  Wrap(
                    textDirection: TextDirection.rtl,
                    spacing: 9,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('تعديل'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onDelete,
                        icon: isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
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

class _StatusMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _StatusMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 70),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 55, color: AnnouncementColors.gold),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementEditorDialog extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>>? document;

  const _AnnouncementEditorDialog({this.document});

  @override
  State<_AnnouncementEditorDialog> createState() =>
      _AnnouncementEditorDialogState();
}

class _AnnouncementEditorDialogState extends State<_AnnouncementEditorDialog> {
  static const int _maxImageBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isImportant = false;
  bool _isSaving = false;
  Uint8List? _newImage;
  String? _imageContentType;
  String? _extension;
  bool _removeCurrentImage = false;
  String _existingImageUrl = '';
  String _existingImagePath = '';

  @override
  void initState() {
    super.initState();
    final data = widget.document?.data();
    if (data == null) return;
    _titleController.text = (data['title'] ?? '').toString();
    _descriptionController.text = (data['description'] ?? '').toString();
    _isImportant = data['isImportant'] == true;
    _existingImageUrl = (data['imageUrl'] ?? '').toString();
    _existingImagePath = (data['imagePath'] ?? '').toString();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isSaving) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty || bytes.length > _maxImageBytes) {
        _showError('حجم الصورة يجب ألا يتجاوز 5 ميغابايت');
        return;
      }
      final format = _detectImageFormat(bytes);
      if (format == null) {
        _showError('صيغة الصورة غير مدعومة. اختر JPEG أو PNG أو WebP');
        return;
      }
      setState(() {
        _newImage = bytes;
        _imageContentType = format.$1;
        _extension = format.$2;
        _removeCurrentImage = false;
      });
    } catch (_) {
      _showError('تعذر اختيار الصورة، حاول مرة أخرى');
    }
  }

  (String, String)? _detectImageFormat(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return ('image/jpeg', 'jpg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return ('image/png', 'png');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return ('image/webp', 'webp');
    }
    return null;
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('يرجى تسجيل الدخول أولًا');
      return;
    }
    setState(() => _isSaving = true);
    final reference =
        widget.document?.reference ??
        FirebaseFirestore.instance.collection('announcements').doc();
    final oldImagePath = _existingImagePath;
    var nextImagePath = _removeCurrentImage ? '' : _existingImagePath;
    var nextImageUrl = _removeCurrentImage ? '' : _existingImageUrl;
    String? uploadedPath;
    try {
      if (_newImage != null) {
        final path =
            'announcements/${reference.id}/images/'
            'cover_${DateTime.now().microsecondsSinceEpoch}.$_extension';
        final imageRef = FirebaseStorage.instance.ref(path);
        uploadedPath = path;
        await imageRef.putData(
          _newImage!,
          SettableMetadata(contentType: _imageContentType),
        );
        nextImageUrl = await imageRef.getDownloadURL();
        nextImagePath = path;
      }

      if (widget.document == null) {
        await reference.set({
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'isImportant': _isImportant,
          'imageUrl': nextImageUrl,
          'imagePath': nextImagePath,
          'publishedAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
        });
      } else {
        await reference.update({
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'isImportant': _isImportant,
          'imageUrl': nextImageUrl,
          'imagePath': nextImagePath,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      // Cleanup old image only after the Firestore document was saved.
      if (_isOwnedImagePath(reference.id, oldImagePath) &&
          oldImagePath != nextImagePath) {
        try {
          await FirebaseStorage.instance.ref(oldImagePath).delete();
        } on FirebaseException {
          // Editing remains successful even when cleanup is unavailable.
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      // If Firestore failed after upload, remove the unreferenced new image.
      if (uploadedPath != null) {
        try {
          await FirebaseStorage.instance.ref(uploadedPath).delete();
        } on FirebaseException {
          // A cleanup failure does not hide the original error.
        }
      }
      _showError(
        error.code == 'permission-denied' || error.code == 'unauthorized'
            ? 'ليس لديك صلاحية لحفظ الإعلان أو صورته'
            : error.code == 'bucket-not-found'
            ? 'يرجى إعداد Firebase Storage أولًا'
            : 'تعذر حفظ الإعلان، حاول مرة أخرى',
      );
    } catch (_) {
      if (uploadedPath != null) {
        try {
          await FirebaseStorage.instance.ref(uploadedPath).delete();
        } on FirebaseException {
          // Ignore cleanup failure.
        }
      }
      _showError('تعذر حفظ الإعلان، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOldImage =
        _newImage == null &&
        !_removeCurrentImage &&
        _existingImageUrl.isNotEmpty;
    return AlertDialog(
      title: Text(
        widget.document == null ? 'إضافة إعلان جديد' : 'تعديل الإعلان',
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الإعلان',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final title = (value ?? '').trim();
                    if (title.isEmpty) return 'يرجى إدخال عنوان الإعلان';
                    if (title.length < 2) return 'العنوان قصير جدًا';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLength: 2000,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل الإعلان',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'يرجى إدخال تفاصيل الإعلان'
                      : null,
                ),
                CheckboxListTile(
                  title: const Text('إعلان مهم'),
                  value: _isImportant,
                  activeColor: AnnouncementColors.gold,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _isSaving
                      ? null
                      : (value) =>
                            setState(() => _isImportant = value ?? false),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _newImage != null || showOldImage
                        ? 'تغيير الصورة'
                        : 'إضافة صورة (اختياري)',
                  ),
                ),
                if (_newImage != null || showOldImage) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _newImage != null
                        ? Image.memory(
                            _newImage!,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.contain,
                          )
                        : Image.network(
                            _existingImageUrl,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.contain,
                          ),
                  ),
                  TextButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => setState(() {
                            _newImage = null;
                            _removeCurrentImage = true;
                          }),
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: const Text(
                      'إزالة الصورة',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AnnouncementColors.gold,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.document == null ? 'نشر الإعلان' : 'حفظ التعديلات'),
        ),
      ],
    );
  }
}

bool _isOwnedImagePath(String announcementId, String path) {
  return path.startsWith('announcements/$announcementId/images/');
}

