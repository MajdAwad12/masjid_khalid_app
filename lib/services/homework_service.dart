import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class HomeworkService {
  HomeworkService._();
  static final _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  static String newId() =>
      FirebaseFirestore.instance.collection('homework').doc().id;

  static Future<void> save({
    required String id,
    required String title,
    required String body,
    required String groupName,
    required DateTime? dueAt,
    required String imagePath,
    required bool isVisible,
  }) async {
    await _functions.httpsCallable('saveHomework').call({
      'homeworkId': id,
      'title': title.trim(),
      'body': body.trim(),
      'groupName': groupName.trim(),
      'dueAtMs': dueAt?.millisecondsSinceEpoch,
      'imagePath': imagePath,
      'isVisible': isVisible,
    });
  }

  static Future<void> delete(String id) async {
    await _functions.httpsCallable('deleteHomework').call({'homeworkId': id});
  }
}
