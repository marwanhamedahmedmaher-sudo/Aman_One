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

  // The phone field sits inside a Directionality(ltr) wrapper. There is
  // exactly one TextField on the screen, so matching by type is unambiguous.
  await $(TextField).enterText(phoneDigits);
  await $('\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644').tap(); // تسجيل الدخول

  // PasswordScreen — enter password and tap "\u062f\u062e\u0648\u0644" (دخول).
  await $(TextField).enterText(_testPassword);
  await $('\u062f\u062e\u0648\u0644').tap();
}

Future<void> _dismissBiometricDialogOrWaitForHome(
    PatrolIntegrationTester $) async {
  // The biometric opt-in dialog appears on devices with biometric hw + no
  // stored credentials. CI emulators don't have biometric hw, so the dialog
  // is reliably absent there. Earlier we used a while-loop polling
  // `$.pump(500ms)` to race the dialog against the home greeting — but that
  // loop appeared to hang (27+ min CI wallclock before cancellation),
  // likely because `$.pump()` under Patrol can block indefinitely if the
  // framework is waiting on a pending frame the app never schedules.
  //
  // Patrol-idiomatic replacement: one short non-blocking check for the
  // dialog, then a long wait for home. Handles both branches cleanly
  // without any custom timing code.
  final laterButton = $('\u0644\u0627\u062d\u0642\u0627\u064b'); // لاحقا
  await $.pumpAndSettle(
    duration: const Duration(milliseconds: 500),
    timeout: const Duration(seconds: 10),
  );
  if (laterButton.exists) {
    await laterButton.tap();
  }

  // Wait up to 60s for the home greeting. Generous cap covers slow CI
  // Supabase round-trips; if it still doesn't appear the test fails with
  // a clear "waitUntilVisible timeout" from Patrol.
  await $(RegExp(r'\u0623\u0647\u0644\u0627')) // "أهلا ..."
      .waitUntilVisible(timeout: const Duration(seconds: 60));
}

Future<void> _createLead(
  PatrolIntegrationTester $, {
  required String phone,
  required String nationalId,
}) async {
  await $('\u062a\u0633\u062c\u064a\u0644 \u0639\u0645\u064a\u0644 \u062c\u062f\u064a\u062f').tap(); // تسجيل عميل جديد

  // The lead form has many TextFields in the same shape — narrow each one
  // by its label so reorderings don't break the test.
  await $('\u0627\u062f\u062e\u0644 \u0627\u0633\u0645 \u0627\u0644\u062a\u0627\u062c\u0631') // ادخل اسم التاجر
      .enterText(taggedName());

  // Phone field — anchor on its hint "01XXXXXXXXX".
  await $('01XXXXXXXXX').enterText(phone);

  // National ID field — anchor on its hint "XXXXXXXXXXXXXX".
  await $('XXXXXXXXXXXXXX').enterText(nationalId);

  // Products — all three, to exercise every conditional detail field.
  await $('Microfinance').tap();
  await $('\u0627\u062f\u062e\u0644 \u0627\u0644\u0645\u0628\u0644\u063a') // ادخل المبلغ
      .enterText('50000');

  await $('BP POS').tap();

  await $('Acceptance POS').tap();
  await $('\u0627\u062f\u062e\u0644 \u0639\u062f\u062f \u0627\u0644\u0623\u062c\u0647\u0632\u0629') // ادخل عدد الأجهزة
      .enterText('3');

  // Notes — required carrier for patrolRunTag.
  await $('\u0623\u0636\u0641 \u0645\u0644\u0627\u062d\u0638\u0627\u062a (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)') // أضف ملاحظات (اختياري)
      .enterText(taggedNotes());

  // Submit — button reads "تسجيل".
  await $('\u062a\u0633\u062c\u064a\u0644').tap();
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
