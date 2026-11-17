import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import '../auth/auth_service.dart';

class AccountSettingsPage extends StatelessWidget {
  final bool isAdmin;
  const AccountSettingsPage({super.key, required this.isAdmin});

  static const gold = Color(0xFFA16602);
  static const dark = Color(0xFF342F27);
  static const muted = Color(0xFF756C5D);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      children: [
        const Icon(Icons.settings_outlined, color: gold, size: 50),
        const SizedBox(height: 12),
        const Text('إعدادات الحساب', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 23, color: dark, fontWeight: FontWeight.bold)),
        const SizedBox(height: 25),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users')
              .doc(user.uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('تعذر تحميل الملف الشخصي');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = snapshot.data!.data();
            if (profile == null) {
              return const Text(
                'لم يتم إنشاء الملف الشخصي لهذا الحساب بعد.\n'
                'أكمل بيانات حساب المسؤول لاحقًا.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              );
            }
            final name = '${profile['firstName'] ?? ''} '
                '${profile['lastName'] ?? ''}'.trim();
            return Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: dark)),
                    const SizedBox(height: 7),
                    Text('اسم المستخدم: ${profile['username'] ?? '—'}'),
                    Text('المدينة: ${profile['city'] ?? '—'}'),
                    Text('رقم الهاتف: ${profile['phone'] ?? '—'}'),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined, color: gold),
            title: Text(isAdmin ? 'مسؤول النظام' : 'مستخدم'),
            subtitle: const Text('تُحدد الصلاحيات تلقائيًا من Firebase'),
          ),
        ),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 10),
        const Text('الدعم والمساعدة', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.bold, color: dark)),
        const SizedBox(height: 8),
        const Text(
          'اسم المسؤول ورقم التواصل سيُضافان بعد تأكيد البيانات.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => AuthService.signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'),
          style: OutlinedButton.styleFrom(
            foregroundColor: gold,
            side: const BorderSide(color: gold),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
