import 'package:geolocator/geolocator.dart';

/// Why a location request failed — lets the UI offer the right recovery action
/// (re-request the permission, open OS settings, or simply retry the fix).
enum LocationErrorKind {
  /// Device location (GPS) master switch is off.
  serviceDisabled,

  /// App permission denied this time, but can be requested again.
  permissionDenied,

  /// App permission denied permanently ("don't ask again") — only the OS
  /// app-settings page can flip it back on.
  permissionDeniedForever,

  /// Permission was granted but a fix couldn't be taken (timeout / no signal).
  fixFailed,
}

/// Result of a foreground location request — either a fix or an Arabic error
/// carrying the [kind] so the caller can choose the right fallback.
class LocationResult {
  final Position? position;
  final String? error;
  final LocationErrorKind? kind;

  const LocationResult._({this.position, this.error, this.kind});

  factory LocationResult.success(Position position) =>
      LocationResult._(position: position);
  factory LocationResult.failure(String error, LocationErrorKind kind) =>
      LocationResult._(error: error, kind: kind);

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
        LocationErrorKind.serviceDisabled,
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
        LocationErrorKind.permissionDeniedForever,
      );
    }
    if (permission == LocationPermission.denied) {
      return LocationResult.failure(
        'لم يتم منح إذن الوصول للموقع.',
        LocationErrorKind.permissionDenied,
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
        LocationErrorKind.fixFailed,
      );
    }
  }

  /// Opens the OS app-settings page so the rep can re-enable a permanently
  /// denied location permission. Returns true if the page was opened.
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the OS location (GPS) settings so the rep can turn location on.
  /// Returns true if the page was opened.
  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();
}
