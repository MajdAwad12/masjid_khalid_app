import 'package:cloud_firestore/cloud_firestore.dart';

class Course {
  final String id;
  final String title;
  final String description;
  final String teacher;
  final String location;
  final DateTime? startAt;
  // null means that the administrator did not set a capacity limit.
  final int? capacity;
  final int acceptedCount;
  final int pendingCount;
  final int rejectedCount;
  final bool isOpen;
  final bool isVisible;
  final String registrationMode;

  const Course({
    required this.id,
    required this.title,
    required this.description,
    required this.teacher,
    required this.location,
    required this.startAt,
    required this.capacity,
    required this.acceptedCount,
    required this.pendingCount,
    required this.rejectedCount,
    required this.isOpen,
    required this.isVisible,
    required this.registrationMode,
  });

  factory Course.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    final rawStart = map['startAt'];
    final rawCapacity = map['capacity'];
    return Course(
      id: doc.id,
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      teacher: (map['teacher'] ?? '').toString(),
      location: (map['location'] ?? '').toString(),
      startAt: rawStart is Timestamp ? rawStart.toDate().toLocal() : null,
      capacity: rawCapacity is num && rawCapacity > 0
          ? rawCapacity.toInt()
          : null,
      acceptedCount: (map['acceptedCount'] as num?)?.toInt() ?? 0,
      pendingCount: (map['pendingCount'] as num?)?.toInt() ?? 0,
      rejectedCount: (map['rejectedCount'] as num?)?.toInt() ?? 0,
      isOpen: map['isOpen'] == true,
      isVisible: map['isVisible'] != false,
      registrationMode: (map['registrationMode'] ?? 'approval').toString(),
    );
  }

  int get occupied => acceptedCount + pendingCount;
  bool get isFull => capacity != null && occupied >= capacity!;
  int? get remaining {
    if (capacity == null) return null;
    final left = capacity! - occupied;
    return left > 0 ? left : 0;
  }

  bool get canRegister =>
      isVisible &&
      isOpen &&
      !isFull &&
      (startAt == null || startAt!.isAfter(DateTime.now()));

  String get formattedStart {
    final time = startAt;
    if (time == null) return '';
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${pad(time.day)}/${pad(time.month)}/${time.year}  '
        '${pad(time.hour)}:${pad(time.minute)}';
  }
}
