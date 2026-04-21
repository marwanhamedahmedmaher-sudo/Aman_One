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
// The test is written to be idempotent and self-cleaning — every row it
// creates carries `patrolRunTag` in its notes, and the `tearDown` deletes
// those rows via the rep's JWT (RLS confines the delete to the test rep's
// own merchants, so no service-role key is required in CI).
//
// Scope caveat: first-login change-password is NOT covered here. That flow
// fires only once per rep and a durable test rep has already rotated past
// it. Covering it would require provisioning a fresh rep every run, which
// needs the service-role key in CI — a security budget we are not spending
// for V1. Tracked in docs/PATROL-RUNBOOK.md.

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
    'golden path: login → create lead → list → profile → reveal NID',
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

      await _createLead($, phone: testPhone, nationalId: testNid);
      await _assertLeadSuccess($);
      await _openMerchantListFromHome($);
      await _openMerchantProfile($);
      await _revealNationalId($, testNid);
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
  await $('\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644').tap(); // تسجيل الدخول
  await $.pumpAndSettle();

  // Wait for the password screen to actually arrive before typing.
  await $('\u062f\u062e\u0648\u0644')
      .waitUntilVisible(timeout: const Duration(seconds: 15)); // دخول button
  await $(TextField).enterText(_testPassword);
  await $.pumpAndSettle();
  print('[patrol] password entered (len=${_testPassword.length}), tapping "دخول"');
  await $('\u062f\u062e\u0648\u0644').tap();
  await $.pumpAndSettle();
  print('[patrol] login tap fired');
}

Future<void> _dismissBiometricDialogOrWaitForHome(
    PatrolIntegrationTester $) async {
  // The biometric opt-in dialog appears on devices with biometric hw + no
  // stored credentials. CI emulators don't have biometric hw, so the dialog
  // is reliably absent there.
  final laterButton = $('\u0644\u0627\u062d\u0642\u0627\u064b'); // لاحقا
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
  final homeGreeting = $(RegExp(r'\u0623\u0647\u0644\u0627')); // "أهلا ..."
  final unexpectedError =
      $('\u062d\u062f\u062b \u062e\u0637\u0623 \u063a\u064a\u0631 \u0645\u062a\u0648\u0642\u0639'); // حدث خطأ غير متوقع
  final badCredentials =
      $('\u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062f\u062e\u0648\u0644 \u063a\u064a\u0631 \u0635\u062d\u064a\u062d\u0629'); // بيانات الدخول غير صحيحة

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
    'phone_entry:تسجيل الدخول': '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644',
    'password:دخول': '\u062f\u062e\u0648\u0644',
    'password:كلمة المرور': '\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631',
    'change_password:تعيين كلمة مرور جديدة': '\u062a\u0639\u064a\u064a\u0646 \u0643\u0644\u0645\u0629 \u0645\u0631\u0648\u0631 \u062c\u062f\u064a\u062f\u0629',
    'change_password:حفظ': '\u062d\u0641\u0638',
    'forgot_password:نسيت كلمة المرور': '\u0646\u0633\u064a\u062a \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631',
    'error:فشل تسجيل الدخول': '\u0641\u0634\u0644 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644',
    'error:بيانات الدخول غير صحيحة': '\u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062f\u062e\u0648\u0644 \u063a\u064a\u0631 \u0635\u062d\u064a\u062d\u0629',
    'error:يرجى إدخال كلمة المرور': '\u064a\u0631\u062c\u0649 \u0625\u062f\u062e\u0627\u0644 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631',
    'main_shell:الرئيسية': '\u0627\u0644\u0631\u0626\u064a\u0633\u064a\u0629',
    'biometric:لاحقا': '\u0644\u0627\u062d\u0642\u0627\u064b',
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

Future<void> _createLead(
  PatrolIntegrationTester $, {
  required String phone,
  required String nationalId,
}) async {
  await $('\u062a\u0633\u062c\u064a\u0644 \u0639\u0645\u064a\u0644 \u062c\u062f\u064a\u062f').tap(); // تسجيل عميل جديد

  // Every TextField on this form is anchored by its `InputDecoration.hintText`.
  // Targeting the hint Text directly fails `waitUntilVisible` because Flutter's
  // InputDecorator wraps the hint in IgnorePointer, making the inner RichText
  // non-hit-testable. Walk up to the enclosing TextField (which IS hit-testable)
  // via `.containing(pattern)` — this keeps the selector readable and resilient
  // to form reorderings without requiring Keys on every field.
  await $(TextField)
      .containing('\u0627\u062f\u062e\u0644 \u0627\u0633\u0645 \u0627\u0644\u062a\u0627\u062c\u0631') // ادخل اسم التاجر
      .enterText(taggedName());

  await $(TextField).containing('01XXXXXXXXX').enterText(phone);
  await $(TextField).containing('XXXXXXXXXXXXXX').enterText(nationalId);

  // Products — all three, to exercise every conditional detail field. Product
  // rows are tappable GestureDetectors around Text labels, not TextFields, so
  // the plain-text selector works.
  await $('Microfinance').tap();
  await $(TextField)
      .containing('\u0627\u062f\u062e\u0644 \u0627\u0644\u0645\u0628\u0644\u063a') // ادخل المبلغ
      .enterText('50000');

  await $('BP POS').tap();

  await $('Acceptance POS').tap();
  await $(TextField)
      .containing('\u0627\u062f\u062e\u0644 \u0639\u062f\u062f \u0627\u0644\u0623\u062c\u0647\u0632\u0629') // ادخل عدد الأجهزة
      .enterText('3');

  // Notes + submit live at the bottom of the form. By the time we reach them
  // the soft keyboard has been up for five previous fields and may now cover
  // them entirely, so waitUntilVisible rejects them as not hit-testable even
  // though they're rendered. `.scrollTo()` walks to the enclosing Scrollable
  // (the form's SingleChildScrollView) and scrolls the target into view.
  await $(TextField)
      .containing('\u0623\u0636\u0641 \u0645\u0644\u0627\u062d\u0638\u0627\u062a (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)') // أضف ملاحظات (اختياري)
      .scrollTo()
      .enterText(taggedNotes());

  // Submit — button reads "تسجيل".
  await $('\u062a\u0633\u062c\u064a\u0644').scrollTo().tap();
}

Future<void> _assertLeadSuccess(PatrolIntegrationTester $) async {
  await $('\u062a\u0645 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u0639\u0645\u064a\u0644 \u0628\u0646\u062c\u0627\u062d') // تم تسجيل العميل بنجاح
      .waitUntilVisible(timeout: const Duration(seconds: 15));
  await $('\u0627\u0644\u0639\u0648\u062f\u0629 \u0644\u0644\u0631\u0626\u064a\u0633\u064a\u0629').tap(); // العودة للرئيسية
}

Future<void> _openMerchantListFromHome(PatrolIntegrationTester $) async {
  // Home stats card is tappable → merchant list.
  await $('\u062a\u0645 \u0625\u0646\u0634\u0627\u0624\u0647\u0645 \u0647\u0630\u0627 \u0627\u0644\u0623\u0633\u0628\u0648\u0639') // تم إنشاؤهم هذا الأسبوع
      .tap();
  await $('\u0627\u0644\u0639\u0645\u0644\u0627\u0621').waitUntilVisible(); // العملاء (list title)
}

Future<void> _openMerchantProfile(PatrolIntegrationTester $) async {
  // Tap the just-created merchant by name. The list is ordered newest-first
  // so the tagged row is at the top, but matching by text is selector-stable
  // either way.
  await $(taggedName()).tap();
  await $('\u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u0639\u0645\u064a\u0644') // بيانات العميل
      .waitUntilVisible();
}

Future<void> _revealNationalId(
    PatrolIntegrationTester $, String expectedNid) async {
  // Before reveal: 14 masking bullets visible as NID placeholder.
  expect($('*' * 14), findsOneWidget);
  await $('\u0639\u0631\u0636').tap(); // عرض

  // After reveal: bullets gone, the EXACT NID submitted for this run is
  // visible. Asserting the literal value (rather than just the generator's
  // fixed prefix) catches a whole class of regressions: reveal-RPC returning
  // the wrong merchant's NID, client-side masking/unmasking state drift,
  // or Vault decryption off-by-one.
  await $(expectedNid).waitUntilVisible(timeout: const Duration(seconds: 10));
}
