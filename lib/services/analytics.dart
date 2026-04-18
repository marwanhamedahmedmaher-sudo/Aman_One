import 'package:flutter/foundation.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

/// Vendor-neutral analytics facade. Mixpanel is the first sink; swap-out stays
/// cheap by routing all call sites through [Analytics.track] / .identify / .reset.
///
/// PII rule: rep behavioural events only. Never pass merchant NID / phone /
/// name / nid_hash as a property — the debug-mode assertion in [_assertNoPii]
/// throws on forbidden keys so leaks surface locally before they ship.
class Analytics {
  static _Sink _sink = _NoopSink();

  /// Call once at app boot. If [token] is empty the sink stays no-op — keeps
  /// local dev silent and lets CI builds without MIXPANEL_TOKEN still run.
  static Future<void> init({required String token}) async {
    if (token.isEmpty) return;
    try {
      final mp = await Mixpanel.init(
        token,
        trackAutomaticEvents: false,
        optOutTrackingDefault: false,
      );
      _sink = _MixpanelSink(mp);
    } catch (_) {
      // Fail open — analytics must never break the app.
      _sink = _NoopSink();
    }
  }

  /// Attach all future events to this rep's distinct id (Supabase auth UUID).
  /// Call on login success and after a successful change-password rotation.
  static Future<void> identify(String repId) async {
    await _sink.identify(repId);
  }

  /// Fire an event. [properties] must not contain merchant PII.
  static Future<void> track(
    String event, {
    Map<String, Object?> properties = const {},
  }) async {
    _assertNoPii(properties);
    await _sink.track(event, properties);
  }

  /// Clear identity + buffered state. Call on logout.
  static Future<void> reset() async {
    await _sink.reset();
  }

  static final _forbiddenKeyPattern = RegExp(
    r'national_id|nid_hash|\bnid\b|phone|password|merchant_name|full_name',
    caseSensitive: false,
  );

  static void _assertNoPii(Map<String, Object?> properties) {
    assert(() {
      for (final key in properties.keys) {
        if (_forbiddenKeyPattern.hasMatch(key)) {
          throw StateError(
            'Analytics PII leak: event property "$key" looks like merchant PII. '
            'Rep behavioural events only — strip this field before calling track().',
          );
        }
      }
      return true;
    }());
  }
}

abstract class _Sink {
  Future<void> identify(String repId);
  Future<void> track(String event, Map<String, Object?> properties);
  Future<void> reset();
}

class _NoopSink implements _Sink {
  @override
  Future<void> identify(String repId) async {}
  @override
  Future<void> track(String event, Map<String, Object?> properties) async {
    if (kDebugMode) {
      debugPrint('[analytics:noop] $event ${properties.isEmpty ? '' : properties}');
    }
  }
  @override
  Future<void> reset() async {}
}

class _MixpanelSink implements _Sink {
  _MixpanelSink(this._mp);
  final Mixpanel _mp;

  @override
  Future<void> identify(String repId) async {
    await _mp.identify(repId);
  }

  @override
  Future<void> track(String event, Map<String, Object?> properties) async {
    _mp.track(event, properties: properties.isEmpty ? null : properties);
  }

  @override
  Future<void> reset() async {
    await _mp.reset();
  }
}
