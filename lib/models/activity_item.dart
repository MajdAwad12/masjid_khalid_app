import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityItem {
  final String id;
  final String title;
  final String description;
  final String kind;
  final String organizer;
  final String location;
  final String imagePath;
  final DateTime? departureAt;
  final DateTime? returnAt;
  final DateTime? hideAt;
  final int? capacity;
  final int acceptedCount;
  final int pendingCount;
  final int rejectedCount;
  final String registrationMode;
  final bool isOpen;
  final bool isVisible;

  const ActivityItem({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.organizer,
    required this.location,
    required this.imagePath,
    required this.departureAt,
    required this.returnAt,
    required this.hideAt,
    required this.capacity,
    required this.acceptedCount,
    required this.pendingCount,
    required this.rejectedCount,
    required this.registrationMode,
    required this.isOpen,
    required this.isVisible,
  });

  factory ActivityItem.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    Map<String, dynamic>? counts,
  }) {
    final d = doc.data() ?? <String, dynamic>{};
    DateTime? date(String key) {
      final value = d[key];
      return value is Timestamp ? value.toDate().toLocal() : null;
    }

    final rawCapacity = d['capacity'];
    return ActivityItem(
      id: doc.id,
      title: (d['title'] ?? '').toString(),
      kind: (d['kind'] ?? 'activity').toString(),
      description: (d['description'] ?? '').toString(),
      organizer: (d['organizer'] ?? '').toString(),
      location: (d['location'] ?? '').toString(),
      imagePath: (d['imagePath'] ?? '').toString(),
      departureAt: date('departureAt'),
      returnAt: date('returnAt'),
      hideAt: date('hideAt'),
      capacity: rawCapacity is num && rawCapacity > 0
          ? rawCapacity.toInt()
          : null,
      acceptedCount: (counts?['acceptedCount'] as num?)?.toInt() ?? 0,
      pendingCount: (counts?['pendingCount'] as num?)?.toInt() ?? 0,
      rejectedCount: (counts?['rejectedCount'] as num?)?.toInt() ?? 0,
      registrationMode: (d['registrationMode'] ?? 'approval').toString(),
      isOpen: d['isOpen'] == true,
      isVisible: d['isVisible'] == true,
    );
  }

  bool get isFull =>
      capacity != null && acceptedCount + pendingCount >= capacity!;
  int? get remaining => capacity == null
      ? null
      : (capacity! - acceptedCount - pendingCount).clamp(0, capacity!).toInt();
  bool get isPublic =>
      isVisible && (hideAt == null || hideAt!.isAfter(DateTime.now()));
  bool get canRegister =>
      isPublic &&
      isOpen &&
      !isFull &&
      (departureAt == null || departureAt!.isAfter(DateTime.now()));
  bool get registrationClosed =>
      !isOpen || (departureAt != null && !departureAt!.isAfter(DateTime.now()));

  static String formatDate(DateTime time) {
    String pad(int x) => x.toString().padLeft(2, '0');
    return '${pad(time.day)}/${pad(time.month)}/${time.year}'
        '  ${pad(time.hour)}:${pad(time.minute)}';
  }
}
