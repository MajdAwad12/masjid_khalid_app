import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

// Colors matching the mosque application.
class AnnouncementColors {
  static const gold = Color(0xFFA16602);
  static const dark = Color(0xFF342F27);
  static const muted = Color(0xFF756C5D);
  static const border = Color(0xFFE9DFC9);
  static const paleGold = Color(0xFFF9EED7);
}

// Displays live announcements from Firebase Firestore.
class AnnouncementsPage extends StatefulWidget {
  // Kept for compatibility with main.dart.
  // Admin actions will be connected after Firebase Authentication.
  final bool isAdmin;

  const AnnouncementsPage({super.key, this.isAdmin = false});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _announcementsStream;

  @override
  void initState() {
    super.initState();

    _announcementsStream = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('publishedAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _announcementsStream,
      builder: (context, snapshot) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            const Center(
              child: Column(
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    size: 42,
                    color: AnnouncementColors.gold,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'إعلانات المسجد',
                    style: TextStyle(
                      fontSize: 24,
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

            const SizedBox(height: 30),

            if (snapshot.hasError)
              const _StatusMessage(
                icon: Icons.error_outline,
                message: 'تعذر تحميل الإعلانات، حاول لاحقًا',
              )
            else if (!snapshot.hasData)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AnnouncementColors.gold,
                  ),
                ),
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
                  child: AnnouncementCard(data: document.data()),
                ),
              ),
          ],
        );
      },
    );
  }
}

// Reusable card for an announcement.
class AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const AnnouncementCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? '').toString();
    final description = (data['description'] ?? '').toString();

    final isImportant = data['isImportant'] == true;
    final imageUrl = (data['imageUrl'] ?? '').toString().trim();

    final publishedAt = data['publishedAt'];

    final DateTime? date = publishedAt is Timestamp
        ? publishedAt.toDate()
        : null;

    final formattedDate = date == null
        ? ''
        : '${date.day}/${date.month}/${date.year}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isImportant
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
          if (isImportant) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            const SizedBox(height: 14),
          ],

          Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AnnouncementColors.dark,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              height: 1.8,
              color: AnnouncementColors.muted,
            ),
          ),

          // Optional image stored in Firebase Storage.
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'تعذر عرض الصورة',
                        style: TextStyle(color: AnnouncementColors.muted),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          if (formattedDate.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: AnnouncementColors.border),
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
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// Shown when there are no announcements or a loading error.
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
              style: const TextStyle(
                fontSize: 16,
                color: AnnouncementColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
