import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ActivitiesService {
  ActivitiesService._();
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  static String newId() =>
      FirebaseFirestore.instance.collection('activities').doc().id;

  static Future<void> save({
    required String id,
    required String title,
    required String kind,
    required String description,
    required String organizer,
    required String location,
    required DateTime? departureAt,
    required DateTime? returnAt,
    required DateTime? hideAt,
    required int? capacity,
    required String imagePath,
    required String registrationMode,
    required bool isOpen,
    required bool isVisible,
  }) async {
    await _functions.httpsCallable('saveActivity').call({
      'activityId': id,
      'title': title.trim(),
      'kind': kind,
      'description': description.trim(),
      'organizer': organizer.trim(),
      'location': location.trim(),
      'departureAtMs': departureAt?.millisecondsSinceEpoch,
      'returnAtMs': returnAt?.millisecondsSinceEpoch,
      'hideAtMs': hideAt?.millisecondsSinceEpoch,
      'capacity': capacity,
      'imagePath': imagePath,
      'registrationMode': registrationMode,
      'isOpen': isOpen,
      'isVisible': isVisible,
    });
  }

  static Future<String> register({
    required String activityId,
    required String fullName,
    required String phone,
    required String deviceKey,
    String? fcmToken,
  }) async {
    final response = await _functions.httpsCallable('registerForActivity').call(
      {
        'activityId': activityId,
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'deviceKey': deviceKey,
        'fcmToken': fcmToken,
      },
    );
    return Map<String, dynamic>.from(response.data as Map)['status'] as String;
  }

  static Future<bool> addParticipant(
    String activityId,
    String fullName,
    String phone,
  ) async {
    final response = await _functions
        .httpsCallable('adminAddActivityParticipant')
        .call({
          'activityId': activityId,
          'fullName': fullName.trim(),
          'phone': phone.trim(),
        });
    return Map<String, dynamic>.from(response.data as Map)['notified'] == true;
  }

  static Future<bool> decide(
    String activityId,
    String registrationId,
    String decision,
  ) async {
    final response = await _functions
        .httpsCallable('decideActivityRegistration')
        .call({
          'activityId': activityId,
          'registrationId': registrationId,
          'decision': decision,
        });
    return Map<String, dynamic>.from(response.data as Map)['notified'] == true;
  }

  static Future<bool> resend(String activityId, String registrationId) async {
    final response = await _functions
        .httpsCallable('resendActivityDecision')
        .call({'activityId': activityId, 'registrationId': registrationId});
    return Map<String, dynamic>.from(response.data as Map)['notified'] == true;
  }

  static Future<List<Map<String, dynamic>>> myRegistrations(
    String deviceKey,
  ) async {
    final response = await _functions
        .httpsCallable('myActivityRegistrations')
        .call({'deviceKey': deviceKey});
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['registrations'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> syncToken(String deviceKey, String token) async {
    await _functions.httpsCallable('syncActivityDeviceToken').call({
      'deviceKey': deviceKey,
      'fcmToken': token,
    });
  }

  static String error(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'already-exists':
          return 'هذا الشخص مسجل بالفعل في النشاط أو الرحلة';
        case 'unauthenticated':
          return 'يرجى تسجيل دخول المسؤول أولًا';
        case 'permission-denied':
          return 'ليست لديك صلاحية لإجراء هذه العملية';
        case 'invalid-argument':
          return 'تحقق من البيانات التي أدخلتها';
        case 'failed-precondition':
          return 'التسجيل مغلق أو النشاط غير متاح حاليًا';
        case 'resource-exhausted':
          return 'اكتمل العدد أو تجاوزت عدد المحاولات المسموح';
        case 'not-found':
          return 'لم يتم العثور على النشاط أو التسجيل';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'تعذر الاتصال بالخادم. حاول مرة أخرى';
      }
    }
    return 'حدث خطأ، يرجى المحاولة مجددًا';
  }
}
