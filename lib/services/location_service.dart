import 'package:geolocator/geolocator.dart';

/// Result of a foreground location request — either a fix or an Arabic error.
class LocationResult {
  final Position? position;
  final String? error;

  const LocationResult._({this.position, this.error});

  factory LocationResult.success(Position position) =>
      LocationResult._(position: position);
  factory LocationResult.failure(String error) =>
      LocationResult._(error: error);

  bool get isSuccess => position != null;
}

/// Thin wrapper over geolocator. FOREGROUND ONLY — one fix per call, taken when
/// the rep taps "submit location". No streams, no background tracking.
class LocationService {
  /// Request a single high-accuracy fix. Surfaces Arabic errors for the UI.
  static Future<LocationResult> getCurrentPosition() async {
    // 1. Is the device's location service (GPS) turned on at all?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationResult.failure(
        'خدمة الموقع غير مفعّلة. برجاء تفعيل الـ GPS وإعادة المحاولة.',
      );
    }

    // 2. App-level permission.
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationResult.failure(
        'تم رفض إذن الموقع نهائياً. برجاء تفعيله من إعدادات التطبيق.',
      );
    }
    if (permission == LocationPermission.denied) {
      return LocationResult.failure(
        'لم يتم منح إذن الوصول للموقع.',
      );
    }

    // 3. Take the fix (bounded so the button never hangs forever).
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationResult.success(position);
    } catch (_) {
      return LocationResult.failure(
        'تعذّر تحديد الموقع. برجاء المحاولة في مكان مكشوف وإعادة المحاولة.',
      );
    }
  }
}
