import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A photo-handling failure with a ready-to-show Arabic message.
class VisitPhotoException implements Exception {
  final String messageAr;
  const VisitPhotoException(this.messageAr);

  static const tooLarge = VisitPhotoException(
      'حجم الصورة كبير جدًا (الحد ٥ ميجابايت). برجاء اختيار صورة أصغر.');
  static const uploadFailed = VisitPhotoException(
      'تعذّر رفع الصورة. برجاء المحاولة مرة أخرى.');
  static const notAuthenticated = VisitPhotoException('انتهت الجلسة. سجّل الدخول مرة أخرى.');

  @override
  String toString() => 'VisitPhotoException: $messageAr';
}

/// Picks a place photo (camera or gallery) and uploads it to the private
/// `task-visit-photos` bucket. Returns the Storage object path on success.
///
/// Path convention: `{rep_id}/{task_id}/{ts}.jpg` — the first segment is the
/// rep's uid so the Storage RLS path-isolation policy (migration 025) lets the
/// rep write only into their own folder, and record_task_visit (migration 028)
/// verifies the path is under that folder before recording the visit.
class VisitPhotoService {
  static final _picker = ImagePicker();
  static const _bucket = 'task-visit-photos';

  /// Hard client-side ceiling, matched to the bucket's server cap (5 MB). The
  /// picker already downscales to 1600px/q70 so this almost never triggers —
  /// it's the defensive guard for the high-resolution edge case.
  static const int maxBytes = 5 * 1024 * 1024;

  /// Pick from the given [source]; returns the picked file or null if the rep
  /// cancelled. Downscaled + compressed on-device to keep uploads small.
  static Future<XFile?> pick(ImageSource source) {
    return _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 70,
    );
  }

  /// Upload [file] for [taskId] and return the Storage object path.
  /// Throws [VisitPhotoException] (with an Arabic message) on failure.
  static Future<String> upload(XFile file, String taskId) async {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      throw VisitPhotoException.notAuthenticated;
    }

    final bytes = await file.readAsBytes();

    // Defensive size guard — rejects an oversized file before any network call,
    // with a clear message instead of a generic 413 from Storage.
    if (bytes.length > maxBytes) {
      if (kDebugMode) {
        debugPrint('[visit_photo] rejected oversized file: ${bytes.length} bytes');
      }
      throw VisitPhotoException.tooLarge;
    }

    final ts = DateTime.now().microsecondsSinceEpoch;
    final path = '$uid/$taskId/$ts.jpg';

    try {
      await supabase.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      if (kDebugMode) debugPrint('[visit_photo] storage error: ${e.message}');
      // 413 / size-limit rejections surface here if the client guard is bypassed.
      final msg = e.statusCode == '413' ? VisitPhotoException.tooLarge : VisitPhotoException.uploadFailed;
      throw msg;
    } catch (e) {
      if (kDebugMode) debugPrint('[visit_photo] upload failed: $e');
      throw VisitPhotoException.uploadFailed;
    }

    if (kDebugMode) {
      debugPrint('[visit_photo] uploaded $path (${bytes.length} bytes)');
    }
    return path;
  }
}
