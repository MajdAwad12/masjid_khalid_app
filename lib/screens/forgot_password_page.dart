import 'package:cloud_functions/cloud_functions.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../widgets/app_theme.dart';

/// Normal users contact the mosque. Administrators can request a reset link
/// only to the personal recovery email they have already verified.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  bool _sending = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _requestAdminReset() async {
    if (_sending || _formKey.currentState?.validate() != true) return;
    setState(() {
      _sending = true;
      _submitted = false;
      _error = null;
    });
    try {
      await _functions.httpsCallable('requestAdminPasswordRecovery').call({
        'username': _usernameController.text.trim().toLowerCase(),
      });
      if (!mounted) return;
      // The server deliberately returns the same result for all usernames.
      setState(() => _submitted = true);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'resource-exhausted'
            ? 'طلبات كثيرة. حاول مرة أخرى لاحقًا.'
            : 'تعذر إرسال الطلب الآن. حاول مرة أخرى لاحقًا.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر الاتصال بالخدمة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة المرور')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lock_reset_outlined,
                    color: AppColors.gold,
                    size: 70,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'نسيت كلمة المرور؟',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.dark,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'اختر طريقة استعادة حسابك',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_outline, color: AppColors.gold),
                            SizedBox(width: 10),
                            Text(
                              'أنا مستخدم',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Text(
                          'يرجى التواصل مع إدارة المسجد للتحقق من هويتك '
                              'والمساعدة في إعادة تعيين كلمة المرور.',
                        ),
                        SizedBox(height: 8),
                        Text(
                          'سيُضاف رقم هاتف الإدارة ورابط واتساب قريبًا.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.admin_panel_settings_outlined,
                                color: AppColors.gold,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'أنا مسؤول النظام',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'أدخل اسم المستخدم. إذا كان حساب مسؤول نشطًا '
                                'وله بريد استرداد موثّق، سنرسل إليه رابطًا آمنًا.',
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _usernameController,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'اسم المستخدم',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final name = value?.trim().toLowerCase() ?? '';
                              if (!AuthService.usernamePattern.hasMatch(name)) {
                                return 'يرجى إدخال اسم مستخدم صحيح';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _requestAdminReset(),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _sending ? null : _requestAdminReset,
                            icon: const Icon(Icons.mark_email_unread_outlined),
                            label: Text(
                              _sending
                                  ? 'جارٍ إرسال الطلب...'
                                  : 'إرسال رابط استعادة كلمة المرور',
                            ),
                          ),
                          if (_submitted) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'إذا كان الحساب مسؤولًا نشطًا وله بريد استرداد '
                                  'موثّق، سيصل الرابط إلى ذلك البريد. '
                                  'تحقق أيضًا من مجلد الرسائل غير المرغوبة.',
                              style: TextStyle(color: Color(0xFF2E7D32)),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFC62828)),
                            ),
                          ],
                          const SizedBox(height: 10),
                          const Text(
                            'الرابط صالح لمدة 15 دقيقة ولمرة واحدة فقط. '
                                'لا يُستخدم البريد الداخلي لتسجيل الدخول هنا.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
