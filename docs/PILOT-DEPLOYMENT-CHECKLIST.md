# Aman Pilot Deployment Checklist

**Target:** Closed Android APK pilot, 20–50 sales reps
**Distribution:** Direct APK sideload (WhatsApp / Google Drive)
**Timeline:** 3–4 days (April 16–19, 2026)

Status: `[ ]` TODO · `[~]` IN PROGRESS · `[x]` DONE · `[—]` SKIPPED (with reason)

---

## Day 1 — Infrastructure & Android Build

### 1A. Production Supabase Project

- [x] Create new Supabase project (prod) — `yflwudkmhqwoscipscbb` in eu-west-1 (DONE 2026-04-16)
- [x] Enable extensions: pgsodium, pgcrypto enabled via SQL (supabase_vault pre-installed) (DONE 2026-04-16)
- [x] Apply all 15 migrations in order (001 → 015) — executed via MCP `execute_sql` (DONE 2026-04-16)
- [x] Verify `activity_types` table seeded (10 rows) — confirmed (DONE 2026-04-16)
- [x] Verify RLS enabled on all 6 tables: `users`, `merchants`, `audit_log`, `activity_types`, `cross_sell_pool`, `task_assignments` (DONE 2026-04-16)
- [x] Run security advisors — 0 lints, clean (DONE 2026-04-16)
- [x] **Auth settings (CRITICAL — Marwan manual step in Dashboard):** (DONE 2026-04-16, confirmed by Marwan)
  - [x] Phone provider ON, SMS provider UNCONFIGURED (hard rule)
  - [x] "Allow new users to sign up" → OFF
  - [x] Enable 2FA on all Dashboard admin accounts (mandatory)
- [x] Record prod `SUPABASE_URL` and `SUPABASE_ANON_KEY` — URL: `https://yflwudkmhqwoscipscbb.supabase.co`, anon key recorded (DONE 2026-04-16)
- [ ] Store service-role key in password manager (not plain text) — used only by provisioning scripts — **deferred, see P2-7**

### 1B. Android Signing Keystore

- [x] Generate release keystore — RSA 4096, 10k-day validity, alias `aman`, at `C:\Users\marwan.haahmed\aman-release.jks` (DONE 2026-04-16)
- [~] Store keystore + passwords in password manager — **interim:** encrypted 7z + cloud + USB backup (password memorized). Password-manager upgrade deferred to post-pilot (**see P2-7**).
- [x] Create `android/key.properties` from `android/key.properties.example` (DONE 2026-04-16, forward-slash Windows path wired + passwords substituted)
- [x] Update `android/app/build.gradle.kts` — signing config + minSdk=23 (DONE 2026-04-16, fixed truncation)
- [x] Add keystore entries to `.gitignore` (DONE 2026-04-16)

### 1C. Android Manifest & Permissions

- [x] Add INTERNET permission to main `AndroidManifest.xml` (currently only in debug/profile):
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  ```
- [x] Add biometric permission (required by `local_auth`):
  ```xml
  <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
  ```
- [x] Set proper `android:label` — "أمان" (not "aman_sales_app")
- [ ] Add app icon (replace default Flutter icon with Aman branding) — **deferred, brand artwork pending**

### 1D. Build Release APK

- [ ] Set prod Supabase credentials via `--dart-define`:
  ```bash
  flutter build apk --release \
    --dart-define=SUPABASE_URL=https://<prod>.supabase.co \
    --dart-define=SUPABASE_ANON_KEY=<prod-anon-key>
  ```
- [ ] Verify APK builds without errors
- [ ] Record APK size (flag if > 50MB — WhatsApp file limit)
- [ ] Rename APK: `aman-v1.0.0-pilot.apk`

---

## Day 2 — Functionality Testing

### 2A. Auth Flow (test on physical Android device)

- [ ] Provision 3 test rep accounts on PROD using `scripts/provision_rep.sh`
- [ ] Fresh install APK → phone entry screen renders RTL, Arabic labels correct
- [ ] Login with phone + temp password → forced to change-password screen
- [ ] Change password → lands on home screen
- [ ] Kill app → reopen → biometric prompt appears (if enabled)
- [ ] Biometric auth succeeds → lands on home
- [ ] Login with wrong password → Arabic error displayed
- [ ] Login with suspended account → Arabic error "الحساب معلق" or appropriate rejection
- [ ] Login with non-existent phone → rejected (no account creation)

### 2B. Lead Submission (core workflow — test 10+ entries)

- [ ] New lead form renders RTL, all labels in Arabic
- [ ] Submit with valid data: name, phone (01xxxxxxxxx), NID (14-digit valid), ≥1 product, notes
  - [ ] Verify phone normalized to E.164 in DB (+20...)
  - [ ] Verify `national_id_hash` generated, `national_id` encrypted (Vault)
  - [ ] Verify `audit_log` INSERT row created with correct `actor_name`
- [ ] Submit duplicate NID → Arabic dedup error: "رقم القومي مسجل بالفعل"
- [ ] Submit invalid phone (e.g., 5 digits) → Arabic error: "رقم الموبايل غير صحيح"
- [ ] Submit invalid NID (e.g., 13 digits) → Arabic error: "رقم القومي غير صحيح"
- [ ] Submit with zero products selected → button disabled (grayed out)
- [ ] Microfinance selected → amount field appears and is required
- [ ] Acceptance POS selected → device count field appears and is required
- [ ] BP POS selected → no extra fields
- [ ] Optional fields (avg sales, address, activity type) → submit works with or without them
- [ ] Activity type dropdown populated with 10 Arabic values
- [ ] Success screen → navigate back to home → weekly count updated

### 2C. Merchant List & Profile

- [ ] Home stats card shows correct weekly count
- [ ] Tap stats card → merchant list screen
- [ ] List shows only current rep's merchants (RLS enforced)
- [ ] Phone numbers masked in list view
- [ ] Tap merchant → profile screen
- [ ] NID shows `*************` by default
- [ ] Tap "عرض" (Reveal) → NID appears in plaintext
  - [ ] Verify `audit_log` row with `national_id_revealed` action
- [ ] Navigate back → NID re-masked on next visit
- [ ] Product details shown (amount for Microfinance, device count for Acceptance POS)
- [ ] Optional info (activity type, avg sales, address) shown when populated
- [ ] Pull-to-refresh works on merchant list

### 2D. Edge Cases & Offline

- [ ] Airplane mode → submit lead → meaningful error (not crash)
- [ ] Airplane mode → login → meaningful error
- [ ] Rotate device → no layout overflow or crash
- [ ] Back button behavior correct on all screens (no infinite loops)
- [ ] Session expiry → user redirected to login (not stuck)
- [ ] Very long merchant name / notes → no overflow, text wraps

---

## Day 2–3 — Security Testing

### 3A. Network & Transport

- [ ] Verify all Supabase calls use HTTPS (check `SUPABASE_URL` starts with `https://`)
- [ ] No hardcoded credentials in APK — decompile with `apktool` and grep:
  ```bash
  apktool d aman-v1.0.0-pilot.apk -o decompiled/
  grep -ri "service_role\|supabase_service\|password" decompiled/
  ```
  Only `SUPABASE_ANON_KEY` should be present (anon key is public by design)
- [ ] Certificate pinning: not required for pilot, but flag as post-pilot hardening item

### 3B. Authentication & Authorization

- [ ] Anon user cannot read `merchants` table (test via `curl` with anon key, no JWT)
- [ ] Anon user cannot read `audit_log` (same test)
- [ ] Rep A cannot see Rep B's merchants (login as Rep A, attempt query filtered to Rep B's UUID)
- [ ] Rep cannot update `created_by` on a merchant to spoof another rep
- [ ] Rep cannot delete merchants (RLS blocks DELETE)
- [ ] Rep cannot read other reps' audit_log entries
- [ ] Rep cannot promote self to admin (attempt `set_claim()` call)
- [ ] Expired JWT rejected by Supabase (test with a manually expired token)

### 3C. Data Protection

- [ ] `national_id` column encrypted at rest via Vault — verify:
  ```sql
  SELECT national_id FROM merchants LIMIT 1;
  -- Should return ciphertext unless queried by authorized role
  ```
- [ ] `national_id_hash` is SHA-256, not plaintext NID
- [ ] NID reveal RPC enforces ownership check — Rep A calling `reveal_national_id` for Rep B's merchant fails
- [ ] Audit log records every NID reveal with rep UUID and timestamp
- [ ] Supabase Dashboard 2FA enabled for all admin accounts
- [ ] Service-role key NOT in git history: `git log --all -p | grep service_role` → empty
- [ ] `.env.admin` is in `.gitignore`

### 3D. Input Validation (server-side — DB is final authority)

- [ ] SQL injection attempt in merchant name → no error, text stored as literal string
- [ ] XSS payload in notes field (`<script>alert(1)</script>`) → stored as text, no execution
- [ ] NID with dashes/spaces → hard-rejected by trigger
- [ ] Phone with letters → hard-rejected by trigger
- [ ] Extremely long input (10,000 chars in notes) → handled gracefully (Postgres `text` has no limit, but test UI rendering)

---

## Day 3 — Provisioning & Distribution Prep

### 4A. Provision Real Rep Accounts

- [ ] Prepare rep roster: phone numbers (E.164 format) + display names for all 20–50 reps
- [ ] Run `scripts/provision_rep.sh` for each rep against PROD project
- [ ] Generate unique temp passwords (12+ chars, mix of letters/numbers)
- [ ] Verify all accounts created in Supabase Dashboard → Authentication → Users
- [ ] Verify `must_change_password` = true in user metadata for each account

### 4B. Prepare Distribution Package

- [ ] Final release APK built with prod credentials (re-run Day 1D if any code changed)
- [ ] Test final APK on 2 different Android devices (different OS versions: Android 10+ minimum)
- [ ] Upload APK to Google Drive (shared link, restricted access)
- [ ] Prepare WhatsApp message template (Arabic):
  - APK download link
  - Installation instructions (enable "Install from unknown sources")
  - Rep's phone number (username)
  - Temp password
  - "You will be asked to change your password on first login"
- [ ] Create shared Google Sheet to track: rep name, phone, provisioned (yes/no), installed (yes/no), first login (yes/no)

### 4C. Admin Readiness

- [ ] Admin has Supabase Dashboard access with 2FA
- [ ] Admin has tested: suspend rep, reset password, export CSV
- [ ] P0-18 Dashboard Runbook printed/bookmarked for admin reference
- [ ] Admin knows the "Phone provider ON, SMS OFF" rule — will not change auth settings
- [ ] Monitoring plan: admin checks `audit_log` daily for anomalies during first week
- [ ] Escalation path defined: rep reports bug → admin → developer (WhatsApp group recommended)

---

## Day 4 — Soft Launch & Verify

### 5A. Canary Group (5 reps first)

- [ ] Send APK + credentials to 5 reps
- [ ] Verify all 5 install successfully
- [ ] Verify all 5 complete first login + password change
- [ ] Each canary rep submits 1 test lead
- [ ] Verify 5 leads in Supabase Dashboard (correct data, audit log entries)
- [ ] Collect verbal feedback: any crashes, Arabic display issues, confusing UX

### 5B. Full Rollout

- [ ] Fix any canary issues (if critical — otherwise note for post-pilot)
- [ ] Send APK + credentials to remaining reps
- [ ] Monitor `audit_log` for first 2 hours — check for errors or unusual patterns
- [ ] Verify at least 50% of reps have logged in within 24 hours
- [ ] Run first admin CSV export to verify data quality

---

## Post-Pilot Hardening (NOT blocking launch, track for later)

- [ ] Firebase Crashlytics or Sentry for crash reporting
- [ ] App version check — force update mechanism for future APK versions
- [ ] Certificate pinning
- [ ] ProGuard / R8 obfuscation (currently default Flutter settings)
- [ ] Client-side NID format validation (P1-1)
- [ ] Soft delete for merchants (P1-2)
- [ ] Migrate to Firebase App Distribution or Play Store internal track for auto-updates
- [ ] PDPL compliance review when legal responds
- [ ] Rate limiting on auth endpoints (Supabase has built-in, verify settings)
- [ ] Client-s