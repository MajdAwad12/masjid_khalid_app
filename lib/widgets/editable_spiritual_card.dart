import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// Public home card. A missing Firestore document retains the existing verse.
/// Only admins see editing tools; Firestore rules enforce the same permission.
class EditableSpiritualCard extends StatefulWidget {
  final bool isAdmin;

  const EditableSpiritualCard({super.key, required this.isAdmin});

  static final _document = FirebaseFirestore.instance
      .collection('app_settings')
      .doc('home');

  @override
  State<EditableSpiritualCard> createState() => _EditableSpiritualCardState();
}

class _EditableSpiritualCardState extends State<EditableSpiritualCard> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _cardStream;

  @override
  void initState() {
    super.initState();
    _refreshStream();
  }

  void _refreshStream() {
    // A fresh listener is important after switching between public and admin.
    _cardStream = EditableSpiritualCard._document.snapshots();
  }

  @override
  void didUpdateWidget(covariant EditableSpiritualCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isAdmin != widget.isAdmin) {
      _refreshStream();
    }
  }

  Future<void> _edit(BuildContext context, _HomeCardData data) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _HomeCardEditor(initial: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _cardStream,
      builder: (context, snapshot) {
        // Do not mistake an unavailable Firestore read for a missing document.
        if (snapshot.hasError) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'تعذر تحميل بطاقة الصفحة الرئيسية. يرجى المحاولة مجددًا.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: () => setState(_refreshStream),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Use the old verse only if the document truly does not exist.
        final data = _HomeCardData.fromMap(snapshot.data!.data());
        if (!widget.isAdmin && !data.visible) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isAdmin) ...[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => _edit(context, data),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    data.visible ? 'تعديل البطاقة' : 'إظهار أو تعديل البطاقة',
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (data.visible)
              _SpiritualCard(data: data)
            else if (widget.isAdmin)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  'البطاقة مخفية عن الزوار',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HomeCardData {
  final bool visible;
  final String title;
  final String content;
  final String source;

  const _HomeCardData({
    required this.visible,
    required this.title,
    required this.content,
    required this.source,
  });

  static const defaultCard = _HomeCardData(
    visible: true,
    title: 'آية من القرآن الكريم',
    content: 'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا',
    source: 'سورة الشرح، الآية ٥',
  );

  static _HomeCardData fromMap(Map<String, dynamic>? values) {
    if (values == null) return defaultCard;
    return _HomeCardData(
      visible: values['visible'] == false ? false : true,
      title:
          values['title'] is String &&
              (values['title'] as String).trim().isNotEmpty
          ? values['title'] as String
          : defaultCard.title,
      content:
          values['content'] is String &&
              (values['content'] as String).trim().isNotEmpty
          ? values['content'] as String
          : defaultCard.content,
      source: values['source'] is String
          ? values['source'] as String
          : defaultCard.source,
    );
  }
}

/// Keeps the original visual layout of the existing verse card.
class _SpiritualCard extends StatelessWidget {
  final _HomeCardData data;

  const _SpiritualCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252B27) : AppColors.surface,
        border: Border.all(
          color: isDark ? const Color(0xFF404A42) : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.content,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 19,
              height: 1.7,
            ),
          ),
          if (data.source.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              data.source,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeCardEditor extends StatefulWidget {
  final _HomeCardData initial;

  const _HomeCardEditor({required this.initial});

  @override
  State<_HomeCardEditor> createState() => _HomeCardEditorState();
}

class _HomeCardEditorState extends State<_HomeCardEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _source;
  late bool _visible;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial.title);
    _content = TextEditingController(text: widget.initial.content);
    _source = TextEditingController(text: widget.initial.source);
    _visible = widget.initial.visible;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _formKey.currentState?.validate() != true) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _error = 'يرجى تسجيل الدخول كمسؤول أولًا');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await EditableSpiritualCard._document.set({
        'visible': _visible,
        'title': _title.text.trim(),
        'content': _content.text.trim(),
        'source': _source.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });
      if (mounted) Navigator.of(context).pop();
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.code == 'permission-denied'
              ? 'لا تملك صلاحية تعديل البطاقة'
              : 'تعذر حفظ البطاقة. حاول مجددًا.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر حفظ البطاقة. حاول مجددًا.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل بطاقة الصفحة الرئيسية'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار البطاقة للزوار'),
                  value: _visible,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _visible = value),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _title,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    labelText: 'عنوان البطاقة',
                    hintText: 'آية، حديث، حكمة، أو رسالة',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'اكتب عنوانًا للبطاقة'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _content,
                  maxLength: 10000,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'النص',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'اكتب نص البطاقة'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _source,
                  maxLength: 15000,
                  decoration: const InputDecoration(
                    labelText: 'المصدر (اختياري)',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات'),
        ),
      ],
    );
  }
}
