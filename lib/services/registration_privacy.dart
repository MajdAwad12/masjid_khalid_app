import 'package:cloud_functions/cloud_functions.dart';

class RegistrationInbox {
  const RegistrationInbox(this.entries, this.reference);

  factory RegistrationInbox.fromPage(Map<String, dynamic> page) {
    final reference = page['reference'];
    if (reference is! String ||
        !RegExp(r'^[0-9a-f]{12}$').hasMatch(reference)) {
      return const RegistrationInbox([], '');
    }
    final rows = (page['registrations'] as List)
        .whereType<Map>()
        .where((item) => item['deviceVerified'] == true)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return RegistrationInbox(rows, reference);
  }

  final List<Map<String, dynamic>> entries;
  final String reference;
}

Future<void> _readPages(
  String endpoint,
  Map<String, dynamic> arguments,
  void Function(Map<String, dynamic>) read,
) async {
  final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
      .httpsCallable(endpoint);
  String? cursor;
  do {
    final result = await callable.call({...arguments, 'cursor': ?cursor});
    final page = Map<String, dynamic>.from(result.data as Map);
    read(page);
    final next = page['nextCursor'] as String?;
    if (next != null && cursor != null && next.compareTo(cursor) <= 0) {
      throw StateError('Invalid registration cursor');
    }
    cursor = next;
  } while (cursor != null);
}

Future<RegistrationInbox> readRegistrationInbox(
  String endpoint,
  String deviceKey,
) async {
  final entries = <Map<String, dynamic>>[];
  var reference = '';
  await _readPages(endpoint, {'deviceKey': deviceKey}, (page) {
    final verified = RegistrationInbox.fromPage(page);
    reference = verified.reference;
    entries.addAll(verified.entries);
  });
  return RegistrationInbox(entries, reference);
}

Future<void> submitRegistration(
  String endpoint,
  Map<String, dynamic> data,
) async {
  try {
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(endpoint)
        .call(data);
  } on FirebaseFunctionsException catch (error) {
    // Older servers return a distinct duplicate error during a rolling release.
    if (error.code != 'already-exists') rethrow;
  }
}

Future<void> syncRegistrationToken(
  String endpoint,
  String deviceKey,
  String token,
) => _readPages(endpoint, {'deviceKey': deviceKey, 'fcmToken': token}, (_) {});

Future<Map<String, dynamic>> manageRegistration({
  required bool course,
  required String parentId,
  required String registrationId,
  required String action,
  String? generation,
  String? reference,
  bool identityChecked = false,
}) async {
  final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final result = await functions
      .httpsCallable(
        course ? 'manageCourseRegistration' : 'manageActivityRegistration',
      )
      .call({
        (course ? 'courseId' : 'activityId'): parentId,
        'registrationId': registrationId,
        'action': action,
        'identityChecked': identityChecked,
        'generation': ?generation,
        'reference': ?reference,
      });
  return Map<String, dynamic>.from(result.data as Map);
}
