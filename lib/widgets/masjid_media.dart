import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

// Storage file names cannot be guessed from a simple timestamp.
class MosqueImageDraft {
  final Uint8List bytes;
  final String extension;
  final String contentType;
  const MosqueImageDraft(this.bytes, this.extension, this.contentType);
}

class MosqueMedia {
  static Future<MosqueImageDraft?> chooseImage() async {
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (selected == null) return null;
    final bytes = await selected.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('حجم الصورة يجب ألا يتجاوز 5 ميغابايت');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return MosqueImageDraft(bytes, 'jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return MosqueImageDraft(bytes, 'png', 'image/png');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return MosqueImageDraft(bytes, 'webp', 'image/webp');
    }
    throw const FormatException('اختر صورة JPEG أو PNG أو WebP');
  }

  static Future<String> upload(
    String collection,
    String id,
    MosqueImageDraft image,
  ) async {
    final random = Random.secure();
    final nonce = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    final path = '$collection/$id/images/$nonce.${image.extension}';
    // Refresh the Firebase admin claim before writing to Storage.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('admin-sign-in-required');
    }
    final token = await user.getIdTokenResult(true);
    if (token.claims?['admin'] != true) {
      throw StateError('admin-permission-required');
    }
    await FirebaseStorage.instance
        .ref(path)
        .putData(image.bytes, SettableMetadata(contentType: image.contentType));
    return path;
  }

  /// Human-readable upload/picker errors.
  static String errorMessage(Object error) {
    if (error is FormatException) return error.message;
    if (error is StateError) {
      if (error.message == 'admin-sign-in-required') {
        return 'يجب تسجيل دخول المسؤول قبل رفع الصورة';
      }
      if (error.message == 'admin-permission-required') {
        return 'صلاحية المسؤول غير مفعّلة. سجّل الدخول مجددًا';
      }
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unauthorized':
        case 'permission-denied':
          return 'رفض Firebase رفع الصورة. تحقق من قواعد Storage وصلاحيات المسؤول';
        case 'unauthenticated':
          return 'انتهت جلسة المسؤول. سجّل الدخول مجددًا';
        case 'quota-exceeded':
          return 'تعذر الرفع بسبب حصة التخزين';
        case 'canceled':
          return 'تم إلغاء رفع الصورة';
        default:
          return 'تعذر رفع الصورة (Firebase: ${error.code})';
      }
    }
    if (error is PlatformException) {
      return 'تعذر اختيار الصورة (${error.code})';
    }
    return 'تعذر رفع الصورة. جرّب صورة JPG أو PNG أقل من 5 ميغابايت';
  }

  static Future<void> deleteSafely(String path) async {
    if (path.isEmpty) return;
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } on FirebaseException {
      // Never roll back an already-committed Firestore document because an
      // unused image could not be removed. The image is no longer referenced.
    }
  }
}

class MosqueStoredImage extends StatefulWidget {
  final String path;
  final double height;
  const MosqueStoredImage({super.key, required this.path, this.height = 190});

  @override
  State<MosqueStoredImage> createState() => _MosqueStoredImageState();
}

class _MosqueStoredImageState extends State<MosqueStoredImage> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _bytes = FirebaseStorage.instance.ref(widget.path).getData(5 * 1024 * 1024);
  }

  @override
  void didUpdateWidget(MosqueStoredImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            height: widget.height,
            child: Center(
              child: snapshot.hasError
                  ? const Icon(Icons.broken_image_outlined, size: 28)
                  : const CircularProgressIndicator(),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            snapshot.data!,
            width: double.infinity,
            height: widget.height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }
}
