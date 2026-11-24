import 'package:cloud_functions/cloud_functions.dart';
import 'package:material_ui/material_ui.dart';

/// Admin-only settings section. The server owns the verified-email state.
class AdminRecoveryEmailCard extends StatefulWidget {
  const AdminRecoveryEmailCard({super.key});

  @override
  State<AdminRecoveryEmailCard> createState() => _AdminRecoveryEmailCardState();
}

class _AdminRecoveryEmailCardState extends State<AdminRecoveryEmailCard> {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  bool _showForm = true;
  String? _verifiedEmail;
  String? _pendingEmail;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _functions
          .httpsCallable('getAdminRecoveryEmailStatus')
          .call();
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      setState(() {
        _verifiedEmail = (data['verifiedEmail'] as String?)?.trim();
        _pendingEmail = (data['pendingEmail'] as String?)?.trim();
        _showForm = (_verifiedEmail?.isEmpty ?? true);
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر التحقق من بريد الاسترداد. حاول مجددًا.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'يرجى تسجيل الدخول مجددًا.';
      case 'permission-denied':
        return 'هذه الميزة متاحة للمسؤولين فقط.';
      case 'failed-precondition':
        return 'لأسباب أمنية، سجّل الخروج ثم ادخل مجددًا قبل حفظ البريد.';
      case 'invalid-argument':
        return 'يرجى إدخال عنوان بريد إلكتروني صحيح.';
      case 'already-exists':
        return 'هذا البريد مرتبط بالفعل بمسؤول آخر.';
      case 'resource-exhausted':
        return 'يرجى الانتظار قليلًا قبل طلب رابط جديد.';
      case 'unavailable':
        return 'تعذر إرسال الرسالة. تحقق من بريدك أو حاول لاحقًا.';
      default:
        return 'تعذر تنفيذ الطلب. يرجى المحاولة مجددًا.';
    }
  }

  Future<void> _requestVerification() async {
    if (_sending || _formKey.currentState?.validate() != true) return;
    setState(() {
      _sending = true;
      _error = null;
      _success = null;
    });
    try {
      await _functions
          .httpsCallable('requestAdminRecoveryEmailVerification')
          .call({'email': _emailController.text.trim()});
      if (!mounted) return;
      setState(() {
        _success = 'تم إرسال رابط التحقق. افتح بريدك واضغط على تأكيد البريد.';
      });
      await _loadStatus();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'حدث خطأ أثناء إرسال رسالة التحقق.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _verifiedEmail?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'البريد الإلكتروني لاستعادة حساب المسؤول',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 9),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: verified
                  ? const Color(0xFFEAF6EE)
                  : const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: verified
                    ? const Color(0xFF388E3C)
                    : const Color(0xFFC62828),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  verified
                      ? Icons.verified_user_outlined
                      : Icons.warning_amber_rounded,
                  color: verified
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFC62828),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    verified
                        ? 'تم تأكيد بريد الاسترداد: $_verifiedEmail'
                        : 'تنبيه مهم: يجب على كل مسؤول إضافة بريد إلكتروني شخصي '
                              'وتأكيده لاستعادة كلمة المرور عند نسيانها.',
                    style: TextStyle(
                      color: verified
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFFB71C1C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_pendingEmail?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              'بانتظار تأكيد البريد: $_pendingEmail',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (verified && !_showForm) ...[
            const SizedBox(height: 7),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _showForm = true),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('تغيير بريد الاسترداد'),
              ),
            ),
          ],
          if (_showForm) ...[
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _emailController,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني الشخصي (مطلوب)',
                  hintText: 'name@gmail.com',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
                      email.length > 254) {
                    return 'أدخل بريدًا إلكترونيًا صحيحًا';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 9),
            FilledButton.icon(
              onPressed: _sending ? null : _requestVerification,
              icon: const Icon(Icons.mark_email_unread_outlined),
              label: Text(_sending ? 'جارٍ الإرسال...' : 'إرسال رابط التحقق'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFC62828))),
          ],
          if (_success != null) ...[
            const SizedBox(height: 8),
            Text(_success!, style: const TextStyle(color: Color(0xFF2E7D32))),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _loadStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث حالة التحقق'),
            ),
          ),
          Text(
            'لن يصبح البريد صالحًا لاستعادة كلمة المرور إلا بعد تأكيد الرابط '
            'المرسل إليه. لا يتغير اسم المستخدم أو بريد Firebase الداخلي.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
