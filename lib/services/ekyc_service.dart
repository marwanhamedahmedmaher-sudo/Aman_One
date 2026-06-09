import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when an eKYC scan cannot be completed (network, vendor error, or an
/// unreadable card). Callers surface a rep-friendly Arabic message and let the
/// rep retry or fall back to manual entry — OCR is assistive, never required.
class EkycException implements Exception {
  const EkycException(this.message);
  final String message;
  @override
  String toString() => 'EkycException: $message';
}

/// Structured result of an eKYC / OCR scan of an Egyptian National ID card.
///
/// Mirrors what a production eKYC vendor (e.g. Valify) returns: the extracted
/// fields plus a per-field confidence map (0.0–1.0) so the UI can flag
/// low-confidence values for the rep to double-check. Every field is nullable —
/// a worn or glared card may yield only some of them, and the rep always
/// reviews before submit. The phone is intentionally absent: it is not printed
/// on the Egyptian ID card, so the rep still enters it manually.
class EkycResult {
  final String? fullName;
  final String? nationalId;
  final String? address;

  // Derived from the 14-digit NID structure. The card does not print these as
  // discrete fields, but the vendor returns them and they are cheap to parse —
  // useful for showing the rep a sanity-check summary ("ذكر • القاهرة • 1990").
  final DateTime? birthDate;
  final String? governorate;
  final String? gender;

  /// Confidence per field key: 'full_name', 'national_id', 'address'.
  final Map<String, double> confidence;

  const EkycResult({
    this.fullName,
    this.nationalId,
    this.address,
    this.birthDate,
    this.governorate,
    this.gender,
    this.confidence = const {},
  });

  factory EkycResult.fromJson(Map<String, dynamic> json) {
    final bdRaw = json['birth_date'];
    return EkycResult(
      fullName: json['full_name'] as String?,
      nationalId: json['national_id'] as String?,
      address: json['address'] as String?,
      birthDate:
          bdRaw is String && bdRaw.isNotEmpty ? DateTime.tryParse(bdRaw) : null,
      governorate: json['governorate'] as String?,
      gender: json['gender'] as String?,
      confidence: _confOf(json),
    );
  }
}

/// Structured result of a passport OCR scan (foreigner onboarding).
///
/// The passport carries no Egyptian National ID, so we capture the passport
/// number + nationality (issuing country) instead. Names are available in
/// English on the MRZ; the Arabic name is usually entered by the rep. Every
/// field is nullable — the rep reviews before submit.
class PassportResult {
  final String? fullName;     // Arabic, if the vendor transliterates
  final String? fullNameEn;   // Latin/MRZ name
  final String? passportNumber;
  final String? nationality;  // issuing country (Arabic)
  final DateTime? birthDate;
  final DateTime? expiryDate;
  final String? gender;
  final Map<String, double> confidence;

  const PassportResult({
    this.fullName,
    this.fullNameEn,
    this.passportNumber,
    this.nationality,
    this.birthDate,
    this.expiryDate,
    this.gender,
    this.confidence = const {},
  });

  factory PassportResult.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final raw = json[key];
      return raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
    }

    return PassportResult(
      fullName: json['full_name'] as String?,
      fullNameEn: json['full_name_en'] as String?,
      passportNumber: json['passport_number'] as String?,
      nationality: json['nationality'] as String?,
      birthDate: parse('birth_date'),
      expiryDate: parse('expiry_date'),
      gender: json['gender'] as String?,
      confidence: _confOf(json),
    );
  }
}

/// Generic OCR result for supporting documents (commercial register, tax card).
///
/// [fields] holds the extracted values keyed by form-field name, e.g.
/// `{'commercial_reg': '12345', 'company_name': '...'}`. The caller pulls only
/// the keys it cares about — keeps the facade open to richer extraction later
/// (issue/expiry dates, legal name) without a new result type per document.
class DocOcrResult {
  final Map<String, String> fields;
  final Map<String, double> confidence;

  const DocOcrResult({this.fields = const {}, this.confidence = const {}});

  factory DocOcrResult.fromJson(Map<String, dynamic> json) {
    final f = <String, String>{};
    final raw = json['fields'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v != null) f[k.toString()] = v.toString();
      });
    }
    return DocOcrResult(fields: f, confidence: _confOf(json));
  }
}

/// Shared parser for the `confidence` map present on every eKYC response.
Map<String, double> _confOf(Map<String, dynamic> json) {
  final conf = <String, double>{};
  final raw = json['confidence'];
  if (raw is Map) {
    raw.forEach((k, v) {
      if (v is num) conf[k.toString()] = v.toDouble();
    });
  }
  return conf;
}

/// Vendor-neutral eKYC facade. The app only ever talks to [EkycService.instance]
/// — swapping the OCR provider (company eKYC, Valify, cloud OCR, on-device SDK)
/// is a one-file change. Same philosophy as the `Analytics` facade.
///
/// Production wiring: set `--dart-define=EKYC_ENDPOINT=ekyc-scan`. When empty
/// (local dev, emulator demo) the [MockEkycService] runs so the full
/// scan → pre-fill → review → submit flow is demonstrable without a live vendor.
/// The real call lives server-side in `supabase/functions/ekyc-scan` so the
/// vendor API key never ships in the app bundle.
abstract class EkycService {
  /// Egyptian National ID card (front). Returns identity + NID-derived fields.
  Future<EkycResult> scanNationalId(Uint8List imageBytes);

  /// Foreign passport. Returns passport number + nationality + identity.
  Future<PassportResult> scanPassport(Uint8List imageBytes);

  /// Commercial register document — fetches `commercial_reg` (+ company name).
  Future<DocOcrResult> scanCommercialRegister(Uint8List imageBytes);

  /// Tax card document — fetches `tax_card` (tax registration number).
  Future<DocOcrResult> scanTaxCard(Uint8List imageBytes);

  static EkycService _instance = _resolve();
  static EkycService get instance => _instance;

  /// Test seam — inject a fake from widget/unit tests.
  @visibleForTesting
  static set instance(EkycService service) => _instance = service;

  static EkycService _resolve() {
    const endpoint = String.fromEnvironment('EKYC_ENDPOINT', defaultValue: '');
    if (endpoint.isEmpty) return MockEkycService();
    return EdgeFunctionEkycService(endpoint);
  }
}

/// Production seam: POSTs the card image to a Supabase Edge Function that
/// proxies the company eKYC vendor. The vendor key lives in the function's
/// secrets, never in the app bundle. See `supabase/functions/ekyc-scan`.
class EdgeFunctionEkycService implements EkycService {
  EdgeFunctionEkycService(this.endpoint);
  final String endpoint;

  @override
  Future<EkycResult> scanNationalId(Uint8List imageBytes) async =>
      EkycResult.fromJson(await _invoke(imageBytes, 'national_id'));

  @override
  Future<PassportResult> scanPassport(Uint8List imageBytes) async =>
      PassportResult.fromJson(await _invoke(imageBytes, 'passport'));

  @override
  Future<DocOcrResult> scanCommercialRegister(Uint8List imageBytes) async =>
      DocOcrResult.fromJson(await _invoke(imageBytes, 'commercial_register'));

  @override
  Future<DocOcrResult> scanTaxCard(Uint8List imageBytes) async =>
      DocOcrResult.fromJson(await _invoke(imageBytes, 'tax_card'));

  /// Single chokepoint to the Edge Function. `doc_type` tells the server which
  /// document to OCR; the vendor key stays server-side.
  Future<Map<String, dynamic>> _invoke(Uint8List bytes, String docType) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        endpoint,
        body: {'image_base64': base64Encode(bytes), 'doc_type': docType},
      );
      if (res.status != 200 || res.data is! Map) {
        throw EkycException('eKYC service returned status ${res.status}');
      }
      return Map<String, dynamic>.from(res.data as Map);
    } on EkycException {
      rethrow;
    } catch (e) {
      throw EkycException('eKYC request failed: $e');
    }
  }
}

/// Offline mock for local dev + the emulator demo (no `EKYC_ENDPOINT` set).
///
/// Returns realistic, structurally-valid Egyptian ID data — the generated NID
/// satisfies the `validate_national_id` trigger (migration 003): century 2,
/// real YYMMDD, governorate code in 01–35. That means a scanned-then-submitted
/// lead lands a real `merchants` row on stage, exactly like manual entry.
class MockEkycService implements EkycService {
  final _random = Random();

  @override
  Future<EkycResult> scanNationalId(Uint8List imageBytes) async {
    // Simulate capture + OCR latency so the loading state is visible in the demo.
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    final nid = _generateValidNid();
    final decoded = _decodeNid(nid);

    return EkycResult(
      fullName: _sampleNames[_random.nextInt(_sampleNames.length)],
      nationalId: nid,
      address: _sampleAddresses[_random.nextInt(_sampleAddresses.length)],
      birthDate: decoded.birthDate,
      governorate: decoded.governorate,
      gender: decoded.gender,
      confidence: const {
        'full_name': 0.97,
        'national_id': 0.99,
        'address': 0.90,
      },
    );
  }

  @override
  Future<PassportResult> scanPassport(Uint8List imageBytes) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final yy = 1975 + _random.nextInt(30);
    return PassportResult(
      fullName: _foreignNames[_random.nextInt(_foreignNames.length)],
      fullNameEn: _foreignNamesEn[_random.nextInt(_foreignNamesEn.length)],
      // One letter + 8 digits — a generic, widely-valid passport shape.
      passportNumber:
          '${String.fromCharCode(65 + _random.nextInt(26))}${10000000 + _random.nextInt(89999999)}',
      nationality: _nationalities[_random.nextInt(_nationalities.length)],
      birthDate: DateTime(yy, 1 + _random.nextInt(12), 1 + _random.nextInt(28)),
      expiryDate: DateTime(2028 + _random.nextInt(5), 1 + _random.nextInt(12), 1 + _random.nextInt(28)),
      gender: _random.nextBool() ? 'ذكر' : 'أنثى',
      confidence: const {'passport_number': 0.98, 'nationality': 0.95},
    );
  }

  @override
  Future<DocOcrResult> scanCommercialRegister(Uint8List imageBytes) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return DocOcrResult(
      fields: {
        'commercial_reg': '${10000 + _random.nextInt(900000)}',
        'company_name': _companyNames[_random.nextInt(_companyNames.length)],
      },
      confidence: const {'commercial_reg': 0.96},
    );
  }

  @override
  Future<DocOcrResult> scanTaxCard(Uint8List imageBytes) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // Egyptian tax registration number — 9 digits.
    final n = (100000000 + _random.nextInt(899999999)).toString();
    return DocOcrResult(
      fields: {'tax_card': n},
      confidence: const {'tax_card': 0.96},
    );
  }

  /// Century 2 (1980–1999) + valid YYMMDD + a real governorate code + a random
  /// serial + any check digit. Random serial keeps repeat demos from colliding
  /// on the `national_id_hash` UNIQUE constraint.
  String _generateValidNid() {
    final govCodes = _govNames.keys.toList();
    final yy = 80 + _random.nextInt(20); // 1980–1999
    final mm = 1 + _random.nextInt(12); // 01–12
    final dd = 1 + _random.nextInt(28); // 01–28 (always valid)
    final gov = govCodes[_random.nextInt(govCodes.length)];
    final serial = 1000 + _random.nextInt(9000); // 4 digits
    final check = _random.nextInt(10);
    return '2${_p2(yy)}${_p2(mm)}${_p2(dd)}$gov$serial$check';
  }

  ({DateTime? birthDate, String? governorate, String? gender}) _decodeNid(
      String nid) {
    try {
      final centuryBase = nid[0] == '3' ? 2000 : 1900;
      final yy = int.parse(nid.substring(1, 3));
      final mm = int.parse(nid.substring(3, 5));
      final dd = int.parse(nid.substring(5, 7));
      final gov = nid.substring(7, 9);
      final genderDigit = int.parse(nid[12]); // 13th digit: odd = male
      return (
        birthDate: DateTime(centuryBase + yy, mm, dd),
        governorate: _govNames[gov],
        gender: genderDigit.isOdd ? 'ذكر' : 'أنثى',
      );
    } catch (_) {
      return (birthDate: null, governorate: null, gender: null);
    }
  }

  static String _p2(int v) => v.toString().padLeft(2, '0');

  static const _sampleNames = [
    'محمد أحمد علي',
    'منى سعيد إبراهيم',
    'أحمد محمود حسن',
    'فاطمة عبد الله محمد',
    'كريم مصطفى السيد',
    'هبة جمال الدين',
  ];

  static const _sampleAddresses = [
    '١٥ شارع جمال عبد الناصر، مدينة نصر، القاهرة',
    '٧ شارع البحر، محرم بك، الإسكندرية',
    '٢٢ شارع الهرم، الجيزة',
    '٣ شارع الجمهورية، المنصورة، الدقهلية',
  ];

  static const _foreignNames = [
    'أحمد خالد المنصور',
    'عمر عبد الرحمن الشامي',
    'ليلى يوسف الحاج',
    'خالد إبراهيم السوداني',
  ];

  static const _foreignNamesEn = [
    'Ahmed Khaled Almansour',
    'Omar Abdulrahman Alshami',
    'Laila Youssef Alhaj',
    'Khaled Ibrahim Alsudani',
  ];

  static const _nationalities = ['سوري', 'سعودي', 'أردني', 'سوداني', 'ليبي', 'يمني'];

  static const _companyNames = [
    'شركة النور للتجارة',
    'مؤسسة الأمل التجارية',
    'شركة المستقبل للاستثمار',
    'مجموعة الرواد',
  ];

  // Governorate codes used by the generator — all within the trigger's 01–35
  // range, paired with their Arabic names for the sanity-check summary.
  static const _govNames = {
    '01': 'القاهرة',
    '02': 'الإسكندرية',
    '12': 'الدقهلية',
    '13': 'الشرقية',
    '14': 'القليوبية',
    '21': 'الجيزة',
    '22': 'بني سويف',
    '25': 'أسيوط',
  };
}
