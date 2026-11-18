import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'auth/auth_gate.dart';
import 'firebase_options.dart';
import 'screens/account_settings_page.dart';
import 'screens/announcements_page.dart';
import 'widgets/app_theme.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, defaultTargetPlatform, TargetPlatform;

// Keep existing screens that import main.dart for AppColors working.
export 'widgets/app_theme.dart' show AppColors;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable local Firebase Emulators only when explicitly requested.
  const useEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );

  if (useEmulators) {
    if (!kDebugMode) {
      throw StateError('Firebase Emulators are allowed only in debug mode.');
    }

    // Android emulator accesses the computer through 10.0.2.2.
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';

    await FirebaseAuth.instance.useAuthEmulator(host, 9099);

    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

    FirebaseFunctions.instanceFor(region: 'us-central1')
        .useFunctionsEmulator(host, 5001);
  }

  runApp(const MasjidApp());
}

// Spiritual content displayed on the home page.
const SpiritualMessage homeSpiritualMessage = SpiritualMessage(
  kind: SpiritualKind.quran,
  content: 'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا',
  source: 'سورة الشرح، الآية ٥',
);

// Replace with verified mosque contact information.
const String supportManagerName = 'يُضاف اسم المسؤول لاحقًا';
const String supportManagerPhone = 'يُضاف رقم الهاتف لاحقًا';

enum SpiritualKind { quran, hadith }

class SpiritualMessage {
  final SpiritualKind kind;
  final String content;
  final String source;

  const SpiritualMessage({
    required this.kind,
    required this.content,
    required this.source,
  });
}

// Application entry point.
class MasjidApp extends StatelessWidget {
  const MasjidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مسجد خالد بن الوليد',

      // Centralized application theme.
      theme: AppTheme.lightTheme,

      // Arabic right-to-left layout.
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },

      // Firebase decides whether the user is signed in
      // and whether the user has admin permissions.
      home: AuthGate(
        appBuilder: (isAdmin) {
          return MainScreen(isAdmin: isAdmin);
        },
      ),
    );
  }
}

// Main application screen.
class MainScreen extends StatefulWidget {
  final bool isAdmin;

  const MainScreen({super.key, required this.isAdmin});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  static const List<String> titles = [
    'الرئيسية',
    'الإعلانات',
    'الدورات',
    'الأنشطة',
    'الدروس',
    'الإعدادات',
  ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(
        message: homeSpiritualMessage,
        managerName: supportManagerName,
        managerPhone: supportManagerPhone,
      ),

      // Admin permissions come from Firebase Custom Claims.
      AnnouncementsPage(isAdmin: widget.isAdmin),

      const SectionPage(
        title: 'الدورات',
        icon: Icons.school_outlined,
        description: 'الدورات المتاحة والتسجيل فيها',
      ),

      const SectionPage(
        title: 'الأنشطة',
        icon: Icons.calendar_month_outlined,
        description: 'الفعاليات والمحاضرات القادمة',
      ),

      const SectionPage(
        title: 'الدروس المسجلة',
        icon: Icons.play_circle_outline,
        description: 'دروس ومحاضرات المسجد المسجلة',
      ),

      AccountSettingsPage(isAdmin: widget.isAdmin),
    ];

    return Scaffold(
      appBar: AppBar(
        title: selectedIndex == 0
            ? null
            : Text(
                titles[selectedIndex],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const NotificationsPage(),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),

      body: IndexedStack(index: selectedIndex, children: pages),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        iconSize: 21,
        showUnselectedLabels: true,
        onTap: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'الرئيسية',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            label: 'الإعلانات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school_outlined),
            label: 'الدورات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'الأنشطة',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle_outline),
            label: 'الدروس',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

// Main home page.
class HomePage extends StatelessWidget {
  final SpiritualMessage? message;
  final String managerName;
  final String managerPhone;

  const HomePage({
    super.key,
    required this.message,
    required this.managerName,
    required this.managerPhone,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: Text(
                        'بسم الله الرحمن الرحيم',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    const MosqueImageHero(),

                    const SizedBox(height: 12),

                    const Text(
                      'السلام عليكم ورحمة الله وبركاته',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.dark,
                        fontSize: 21,
                        height: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'منارةٌ للعلم، ومأوى للقلوب',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 15,
                        height: 1.7,
                      ),
                    ),

                    if (message != null) ...[
                      const SizedBox(height: 22),
                      SpiritualCard(message: message!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Mosque image displayed on the home page.
class MosqueImageHero extends StatelessWidget {
  const MosqueImageHero({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final imageSize = (screenWidth * 0.68).clamp(210.0, 270.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/mosque_home.png',
          width: imageSize,
          height: imageSize,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: 'شعار مسجد خالد بن الوليد',
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// Quran verse or Hadith card.
class SpiritualCard extends StatelessWidget {
  final SpiritualMessage message;

  const SpiritualCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final heading = message.kind == SpiritualKind.quran
        ? 'آية من القرآن الكريم'
        : 'حديث نبوي شريف';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            heading,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            message.content,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.dark,
              fontWeight: FontWeight.w600,
              fontSize: 19,
              height: 1.7,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            message.source,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// Contact and support information.
class SupportFooter extends StatelessWidget {
  final String managerName;
  final String managerPhone;

  const SupportFooter({
    super.key,
    required this.managerName,
    required this.managerPhone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.gold.withValues(alpha: 0.23)),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'للدعم والمساعدة عند حدوث مشكلة',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),

          const SizedBox(height: 7),

          Text(
            'مسؤول النظام: $managerName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.dark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'رقم الهاتف: $managerPhone',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// Temporary page for features not yet implemented.
class SectionPage extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const SectionPage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: AppColors.gold),

            const SizedBox(height: 16),

            Text(
              title,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

// Notifications page.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notifications_none, size: 64, color: AppColors.gold),

              SizedBox(height: 17),

              Text(
                'لا توجد إشعارات حتى الآن',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.dark,
                ),
              ),

              SizedBox(height: 10),

              Text(
                'ستظهر هنا إشعارات الدورات وأخبار المسجد',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
