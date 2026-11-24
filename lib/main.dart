import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'auth/auth_gate.dart';
import 'services/theme_controller.dart';
import 'firebase_options.dart';
import 'screens/account_settings_page.dart';
import 'screens/announcements_page.dart';
import 'screens/courses_page.dart';
import 'screens/activities_page.dart';
import 'screens/homework_page.dart';
import 'services/course_notifications_service.dart';
import 'services/public_notifications_service.dart';
import 'widgets/app_theme.dart';
import 'widgets/editable_spiritual_card.dart';

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

  await themeController.load();
  runApp(const MasjidApp());
  unawaited(CourseNotificationsService.instance.initialize());
  unawaited(PublicNotificationsService.instance.initialize());
}

// Replace with verified mosque contact information.
const String supportManagerName = 'يُضاف اسم المسؤول لاحقًا';
const String supportManagerPhone = 'يُضاف رقم الهاتف لاحقًا';

// Application entry point.
class MasjidApp extends StatelessWidget {
  const MasjidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, selectedTheme, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'مسجد خالد بن الوليد',
          scaffoldMessengerKey: courseMessengerKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: selectedTheme,
          themeAnimationDuration: Duration.zero,
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: AuthGate(
            appBuilder: (isAdmin) => MainScreen(
              key: ValueKey(isAdmin ? 'admin-main' : 'public-main'),
              isAdmin: isAdmin,
            ),
          ),
        );
      },
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
  int selectedIndex = PublicNotificationsService.requestedTab.value ?? 0;

  @override
  void initState() {
    super.initState();
    PublicNotificationsService.requestedTab.addListener(_onNotificationOpen);
  }

  void _onNotificationOpen() {
    final section = PublicNotificationsService.requestedTab.value;
    if (mounted && section != null && section != selectedIndex) {
      setState(() => selectedIndex = section);
    }
  }

  @override
  void dispose() {
    PublicNotificationsService.requestedTab.removeListener(_onNotificationOpen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(isAdmin: widget.isAdmin),

      // Admin permissions come from Firebase Custom Claims.
      AnnouncementsPage(isAdmin: widget.isAdmin),

      CoursesPage(isAdmin: widget.isAdmin),

      ActivitiesPage(isAdmin: widget.isAdmin),

      HomeworkPage(isAdmin: widget.isAdmin),

      AccountSettingsPage(
        isAdmin: widget.isAdmin,
        managerName: supportManagerName,
        managerPhone: supportManagerPhone,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: selectedIndex, children: pages),
      ),

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
            label: 'آخر الأخبار',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school_outlined),
            label: 'الدورات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'الأنشطة والرحلات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            label: 'الوظائف البيتية',
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
  final bool isAdmin;

  const HomePage({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scheme = Theme.of(context).colorScheme;
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

                    Text(
                      'السلام عليكم ورحمة الله وبركاته',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 21,
                        height: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'منارةٌ للعلم، ومأوى للقلوب',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 15,
                        height: 1.7,
                      ),
                    ),

                    const SizedBox(height: 22),
                    EditableSpiritualCard(isAdmin: isAdmin),
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
          Text(
            'للدعم والمساعدة عند حدوث مشكلة',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            'مسؤول النظام: $managerName',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'رقم الهاتف: $managerPhone',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
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
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
