// ignore_for_file: avoid_print
//
// `print` (not `debugPrint`) is deliberate — Patrol's framework
// intercepts `debugPrint` and routes it into its PATROL_LOG JSON
// channel, making it hard to grep in the CI logcat stream. `print`
// writes to stdout which lands in logcat as `I/flutter` alongside
// the test's normal output.

// Aman Sales App — Patrol golden-path regression test.
//
// Runs on a real Android emulator against the live pilot Supabase project.
//
// Scope: this is a SHALLOW golden path — login → new-lead form → select all
// three products → launch the unified onboarding wizard, asserting it opens on
// the ID-scan step. Completing the wizard (ID scan → KYC → per-product modules
// → documents → submit → merchant list → NID reveal) is NOT yet covered:
//   - the ID scan needs a native image-picker interaction; a test seam to
//     bypass the camera/gallery on CI does not exist yet,
//   - the mock OCR overwrites the seeded NID, so reveal-assert + tag-based
//     cleanup need a deterministic value first,
//   - first-login change-password remains out of scope (durable rep).
// Because the shallow path creates no merchant row, the tag-cleanup tearDown is
// a no-op here. Restore deep coverage once the wizard has an injectable image
// source. Tracked in docs/PATROL-RUNBOOK.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aman_sales_app/main.dart' as app;

import 'helpers/test_cleanup.dart';
import 'helpers/test_data.dart';

// Env injected via --dart-define at `patrol test` time. These map to GH
// Actions secrets; see docs/PATROL-RUNBOOK.md for provisioning.
const _testPhone = String.fromEnvironment('PATROL_TEST_PHONE');
const _testPassword = String.fromEnvironment('PATROL_TEST_PASSWORD');

// Patrol config — native timeouts kept generous because emulator cold-start
// and Supabase round-trips can both stretch on CI runners.
final _config = const PatrolTesterConfig(
  settleTimeout: Duration(seconds: 30),
  visibleTimeout: Duration(seconds: 30),
);

void main() {
  patrolTest(
    'golden path: login → new lead → launch onboarding wizard',
    config: _config,
    ($) async {
      // Breadcrumbs: if patrol_cli hangs silently in CI again, the missing
      // breadcrumb tells us exactly how far the isolate got. Previously a
      // top-of-main StateError on missing secrets killed the isolate before
      // patrolTest() was even registered, giving us 17 min of total silence.
      debugPrint('[patrol] entering test body');

      // Moved from top-of-main so a missing --dart-define surfaces as a test
      // failure (with a stack trace in patrol logs) instead of a silent
      // isolate death that hangs CI for its 45-minute timeout budget.
      expect(_testPhone.isNotEmpty, isTrue,
          reason:
              'PATROL_TEST_PHONE was empty — --dart-define did not reach the '
              'test bundle. Check .github/workflows/patrol-regression.yml.');
      expect(_testPassword.isNotEmpty, isTrue,
          reason:
              'PATROL_TEST_PASSWORD was empty — --dart-define did not reach '
              'the test bundle.');

      debugPrint('[patrol] dart-defines OK, launching app');
      await app.main();
      await $.pumpAndSettle();
      debugPrint('[patrol] app settled, beginning golden path');

      await _loginAsTestRep($);
      await _dismissBiometricDialogOrWaitForHome($);

      final testPhone = generateTestPhone();
      final testNid = generateTestNationalId();

      await _startOnboarding($, phone: testPhone, nationalId: testNid);
      // Deep wizard coverage (ID scan → KYC → product modules → documents →
      // submit → merchant list → NID reveal) is deferred — see the scope
      // caveat at the top of this file.
    },
  );

  tearDown(() async {
    final deleted = await cleanupMerchantsByTag(patrolRunTag);
    debugPrint('[patrol cleanup] deleted $deleted merchant(s) tagged $patrolRunTag');
    // Sign out so subsequent test iterations start from a clean slate.
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  });
}

// --- Steps ------------------------------------------------------------------

Future<void> _loginAsTestRep(PatrolIntegrationTester $) async {
  // PhoneEntryScreen — 11-digit Egyptian mobile (leading 0, no +20 prefix).
  final phoneDigits =
      _testPhone.startsWith('+20') ? '0${_testPhone.substring(3)}' : _testPhone;

  await $(TextField).enterText(phoneDigits);
  // pumpAndSettle between enterText and tap so the TextEditingController
  // change has fully propagated before the tap handler reads it. Without
  // it we observed the password screen's empty-password guard firing even
  // though enterText had ostensibly populated the field.
  await $.pumpAndSettle();
  print('[patrol] phone entered ($phoneDigits), tapping "تسجيل الدخول"');
  await $('تسجيل الدخول').tap(); // تسجيل الدخول
  await $.pumpAndSettle();

  // Wait for the password screen to actually arrive before typing.
  await $('دخول')
      .waitUntilVisible(timeout: const Duration(seconds: 15)); // دخول button
  await $(TextField).enterText(_testPassword);
  await $.pumpAndSettle();
  print('[patrol] password entered (len=${_testPassword.length}), tapping "دخول"');
  await $('دخول').tap();
  await $.pumpAndSettle();
  print('[patrol] login tap fired');
}

Future<void> _dismissBiometricDialogOrWaitForHome(
    PatrolIntegrationTester $) async {
  // The biometric opt-in dialog appears on devices with biometric hw + no
  // stored credentials. CI emulators don't have biometric hw, so the dialog
  // is reliably absent there.
  final laterButton = $('لاحقاً'); // لاحقا
  try {
    await $.pumpAndSettle(
      duration: const Duration(milliseconds: 500),
      timeout: const Duration(seconds: 10),
    );
  } catch (_) {
    // pumpAndSettle times out on continuously animating widgets (e.g. loading
    // spinner stuck on the login screen). Don't fail here — the wait below
    // will surface the real problem with better context.
  }
  if (laterButton.exists) {
    await laterButton.tap();
  }

  // Wait up to 60s for the home greeting. Poll every second so a visible
  // login-error SnackBar ("حدث خطأ غير متوقع" / "بيانات الدخول غير صحيحة")
  // fails the test immediately instead of burning the full 60s budget on
  // a screen we already know is broken. The error copy lives only on the
  // Scaffold SnackBar and fades after ~4s — the poll catches it while it
  // is still up.
  final homeGreeting = $(RegExp(r'أهلا')); // "أهلا ..."
  final unexpectedError =
      $('حدث خطأ غير متوقع'); // حدث خطأ غير متوقع
  final badCredentials =
      $('بيانات الدخول غير صحيحة'); // بيانات الدخول غير صحيحة

  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    if (homeGreeting.exists) return;
    // Biometric opt-in can appear LATE — emulator biometric-availability
    // checks are async and sometimes resolve only after the first pump.
    // Re-dismiss inside the loop so a slow dialog doesn't block the
    // home-greeting wait. Safe to tap every iteration since the dialog
    // disappears on the first tap.
    if (laterButton.exists) {
      print('[patrol] biometric dialog appeared late, dismissing');
      await laterButton.tap();
    }
    if (unexpectedError.exists) {
      print('[patrol] LOGIN FAILED (unexpected error SnackBar) — bailing early');
      _reportScreenState($);
      throw TestFailure(
          'Login produced "حدث خطأ غير متوقع" SnackBar — see [auth:signIn] '
          'lines in logcat for the underlying exception.');
    }
    if (badCredentials.exists) {
      print('[patrol] LOGIN FAILED (bad credentials) — check PATROL_TEST_PASSWORD secret');
      throw TestFailure(
          'Login produced "بيانات الدخول غير صحيحة" SnackBar — rotate the '
          'Patrol test rep password or update the PATROL_TEST_PASSWORD secret.');
    }
    try {
      await $.pump(const Duration(seconds: 1));
    } catch (_) {}
  }

  print('[patrol] HOME GREETING TIMEOUT — snapshotting screen state');
  _reportScreenState($);
  throw TestFailure('Home greeting "أهلا" did not appear within 60s.');
}

// Best-effort check of which screen the app is actually on when the home
// greeting fails to appear. Checks for known Arabic anchors from each
// auth-adjacent screen plus error markers. Every line prefixed `[patrol]`
// so we can grep the CI LOGCAT| stream.
void _reportScreenState(PatrolIntegrationTester $) {
  final checks = <String, String>{
    'phone_entry:تسجيل الدخول': 'تسجيل الدخول',
    'password:دخول': 'دخول',
    'password:كلمة المرور': 'كلمة المرور',
    'change_password:تعيين كلمة مرور جديدة': 'تعيين كلمة مرور جديدة',
    'change_password:حفظ': 'حفظ',
    'forgot_password:نسيت كلمة المرور': 'نسيت كلمة المرور',
    'error:فشل تسجيل الدخول': 'فشل تسجيل الدخول',
    'error:بيانات الدخول غير صحيحة': 'بيانات الدخول غير صحيحة',
    'error:يرجى إدخال كلمة المرور': 'يرجى إدخال كلمة المرور',
    'main_shell:الرئيسية': 'الرئيسية',
    'biometric:لاحقا': 'لاحقاً',
  };
  for (final entry in checks.entries) {
    final hit = $(entry.value).exists;
    print('[patrol] screen_marker ${entry.key} -> $hit');
  }
  final spinners = find.byType(CircularProgressIndicator).evaluate().length;
  print('[patrol] CircularProgressIndicator count = $spinners');

  // Dump every Text widget's content so we see exactly what's rendering.
  // Limited to first 40 to keep logs bounded. This is the definitive
  // answer to "what screen am I on?" when the named markers don't match.
  final texts = find.byType(Text).evaluate().toList();
  print('[patrol] Text widget count = ${texts.length}');
  var i = 0;
  for (final el in texts.take(40)) {
    final w = el.widget;
    String? data;
    if (w is Text) data = w.data ?? w.textSpan?.toPlainText();
    print('[patrol] text[$i]=${data ?? "<null/span>"}');
    i++;
  }
  // Also dump navigator route if the app is still running a MaterialApp.
  try {
    final mat =
        find.byType(MaterialApp).evaluate().firstOrNull?.widget as MaterialApp?;
    print('[patrol] MaterialApp.home.type = ${mat?.home.runtimeType}');
  } catch (_) {}
}

Future<void> _startOnboarding(
  PatrolIntegrationTester $, {
  required String phone,
  required String nationalId,
}) async {
  await $('تسجيل عميل جديد').tap(); // تسجيل عميل جديد

  // Identity fields are anchored by their InputDecoration.hintText — walk up to
  // the enclosing TextField (hit-testable) via `.containing(hint)`.
  await $(TextField)
      .containing('ادخل اسم التاجر') // ادخل اسم التاجر
      .enterText(taggedName());
  await $(TextField).containing('01XXXXXXXXX').enterText(phone);
  await $(TextField).containing('XXXXXXXXXXXXXX').enterText(nationalId);

  // Products render as Arabic-labelled checkboxes (productLabelAr).
  await $('تمويل المشروعات').tap(); // Microfinance (business financing)
  await $('دفع الفواتير').tap(); // BP POS
  await $('نقاط البيع البنكية').tap(); // Acceptance POS

  // Launch the unified onboarding wizard and confirm it opened on the first
  // step (identity-document capture; nationality defaults to Egyptian).
  await $('بدء التسجيل').scrollTo().tap();
  await $('تصوير وثيقة الهوية').waitUntilVisible(timeout: const Duration(seconds: 10));
}
