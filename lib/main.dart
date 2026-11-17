import 'package:material_ui/material_ui.dart';
import 'screens/announcements_page.dart';
void main() {
  runApp(const MasjidApp());
}

// Shared visual language inspired by the mosque's existing website.
class AppColors {
  static const background = Color(0xFFFAF8F1);
  static const surface = Color(0xFFFFFEFC);
  static const gold = Color(0xFFA16602);
  static const softGold = Color(0xFFEBB44C);
  static const paleGold = Color(0xFFF5EACF);
  static const dark = Color(0xFF342F27);
  static const muted = Color(0xFF756C5D);
  static const border = Color(0xFFE9DFC9);
  // Soft sage green reserved for the mosque arch on the home page.
  static const sageBackground = Color(0xFFF0F6EE);
  static const sageBorder = Color(0xFF9BB59B);
  static const sageDetails = Color(0xFF6F936F);
}

// Eventually the administrator will manage this item through Firebase.
// Set this to null to hide the spiritual-content section completely.
const SpiritualMessage? homeSpiritualMessage = SpiritualMessage(
  kind: SpiritualKind.quran,
  content: 'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا',
  source: 'سورة الشرح، الآية ٥',
);

// These are placeholders, NOT confirmed contact details.
// Replace them with the verified mosque administrator's details.
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

class MasjidApp extends StatelessWidget {
  const MasjidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مسجد خالد بن الوليد',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.gold,
          surface: AppColors.background,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.dark,
          centerTitle: true,
          elevation: 0,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  static const titles = <String>[
    'الرئيسية',
    'الإعلانات',
    'الدورات',
    'الأنشطة',
    'الدروس',
    'الإعدادات',
  ];

  @override
  Widget build(BuildContext context) {
    const pages = <Widget>[
      HomePage(
        message: homeSpiritualMessage,
        managerName: supportManagerName,
        managerPhone: supportManagerPhone,
      ),
      AnnouncementsPage(isAdmin: true),
      SectionPage(
        title: 'الدورات',
        icon: Icons.school_outlined,
        description: 'الدورات المتاحة والتسجيل فيها',
      ),
      SectionPage(
        title: 'الأنشطة',
        icon: Icons.calendar_month_outlined,
        description: 'الفعاليات والمحاضرات القادمة',
      ),
      SectionPage(
        title: 'الدروس المسجلة',
        icon: Icons.play_circle_outline,
        description: 'دروس ومحاضرات المسجد المسجلة',
      ),
      SectionPage(
        title: 'الإعدادات',
        icon: Icons.settings_outlined,
        description: 'إعدادات الحساب والتطبيق',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        // The home screen has its own heading: avoid repeating it in the app bar.
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
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.gold,
        unselectedItemColor: AppColors.muted,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        iconSize: 21,
        showUnselectedLabels: true,
        onTap: (index) => setState(() => selectedIndex = index),
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

// A deliberately calm home page with NO duplicate navigation buttons.
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
                    // The supplied mosque image replaces the previous drawn arch completely.
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

// The supplied illustration is a local image asset, not a drawn arch.
// BoxFit.contain keeps the entire illustration visible, without cropping.

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
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

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

// Other tabs are intentionally placeholders until their dedicated screens are built.
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
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
              Icon(
                Icons.notifications_none,
                size: 64,
                color: AppColors.gold,
              ),
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
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
