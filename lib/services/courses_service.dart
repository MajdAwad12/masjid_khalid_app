import 'package:cloud_functions/cloud_functions.dart';

import '../models/course.dart';

class CoursesService {
  CoursesService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  static Future<String> saveCourse({
    Course? existing,
    required String title,
    required String description,
    required String teacher,
    required String location,
    required DateTime? startAt,
    required int? capacity,
    required String registrationMode,
    required bool isOpen,
    required bool isVisible,
  }) async {
    final response = await _functions.httpsCallable('saveCourse').call({
      if (existing != null) 'courseId': existing.id,
      'title': title.trim(),
      'description': description.trim(),
      'teacher': teacher.trim(),
      'location': location.trim(),
      'startAtMs': startAt?.millisecondsSinceEpoch,
      'capacity': capacity,
      'registrationMode': registrationMode,
      'isOpen': isOpen,
      'isVisible': isVisible,
    });
    return Map<String, dynamic>.from(response.data as Map)['courseId']
        as String;
  }

  // Admin-only, idempotent one-time upgrade for legacy course documents.
  static Future<int> initializeCourseVisibility() async {
    final response = await _functions
        .httpsCallable('initializeCourseVisibility')
        .call();
    final result = Map<String, dynamic>.from(response.data as Map);
    return (result['updated'] as num?)?.toInt() ?? 0;
  }

  static Future<String> register({
    required String courseId,
    required String fullName,
    required String phone,
    required String deviceKey,
    String? fcmToken,
  }) async {
    final response = await _functions.httpsCallable('registerForCourse').call({
      'courseId': courseId,
      'fullName': fullName.trim(),
      'phone': phone.trim(),
      'deviceKey': deviceKey,
      'fcmToken': fcmToken,
    });
    return Map<String, dynamic>.from(response.data as Map)['status'] as String;
  }

  // Admin only. Manual additions bypass the public enrollment window and
  // the capacity limit; existing pending/rejected requests become accepted.
  static Future<bool> addParticipant({
    required String courseId,
    required String fullName,
    String? phone,
  }) async {
    final response = await _functions
        .httpsCallable('adminAddCourseParticipant')
        .call({
          'courseId': courseId,
          'fullName': fullName.trim(),
          'phone': (phone ?? '').trim(),
        });
    return Map<String, dynamic>.from(response.data as Map)['notified'] == true;
  }

  static Future<bool> decide({
    required String courseId,
    required String registrationId,
    required String decision,
  }) async {
    final response = await _functions
        .httpsCallable('decideCourseRegistration')
        .call({
          'courseId': courseId,
          'registrationId': registrationId,
          'decision': decision,
        });
    return Map<String, dynamic>.from(response.data as Map)['notified'] == true;
  }

  // Admin-only: rebuild counters from actual Firestore registrations.
  // Useful for courses created before rejectedCount was introduced.
  static Future<void> reconcileCounts(String courseId) async {
    await _functions.httpsCallable('reconcileCourseCounts').call({
      'courseId': courseId,
    });
  }

  static Future<bool> resend({
    required String courseId,
    required String registrationId,
  }) async {
    final response = await _functions
        .httpsCallable('resendCourseDecision')
        .call({'courseId': courseId, 'registrationId': registrationId});
    return Map<String, dynamic>.from(response.data as Map)['notified'] == true;
  }

  static Future<void> syncToken({
    required String deviceKey,
    required String token,
  }) async {
    await _functions.httpsCallable('syncCourseDeviceToken').call({
      'deviceKey': deviceKey,
      'fcmToken': token,
    });
  }

  static Future<List<Map<String, dynamic>>> myRegistrations(
    String deviceKey,
  ) async {
    final response = await _functions
        .httpsCallable('myCourseRegistrations')
        .call({'deviceKey': deviceKey});
    final result = Map<String, dynamic>.from(response.data as Map);
    final items = result['registrations'] as List? ?? [];
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static String errorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'already-exists':
          return 'هذا الشخص مسجل بالفعل في الدورة';
        case 'unauthenticated':
          return 'يرجى تسجيل دخول المسؤول أولًا';
        case 'permission-denied':
          return 'ليس لديك صلاحية لإجراء هذه العملية';
        case 'invalid-argument':
          return 'تحقق من البيانات المدخلة';
        case 'failed-precondition':
          return 'تعذر إكمال العملية، تحقق من حالة التسجيل وحاول مجددًا';
        case 'resource-exhausted':
          return 'الدورة مكتملة العدد أو تجاوزت عدد المحاولات المسموح';
        case 'not-found':
          return 'لم يتم العثور على الدورة أو التسجيل';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'تعذر الاتصال بالخادم، حاول مرة أخرى';
      }
    }
    return 'حدث خطأ، يرجى المحاولة مجددًا';
  }
}
