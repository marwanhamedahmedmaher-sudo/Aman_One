# Aman Sales App (أمان) — Project State

Single source of truth for project status. Static reference (tech stack, architecture, commands, conventions) lives in `ARCHITECTURE.md`.

**Session rules:**
- Read this file at the start of every session.
- Update it at the end of every session.
- Never delete backlog items — mark `DONE` with date.
- Keep only the last 5 session log entries here; archive older entries to `CLAUDE.archive.md`.

---

## Current Decisions

- **Backend:** Supabase (Postgres + Auth + Storage + Edge Functions). Dev project: `yynhcrtdzgcgedkolgxw`. **Prod project: `yflwudkmhqwoscipscbb`** (eu-west-1, created 2026-04-16, all 15 migrations applied, security advisors clean). Prod URL: `https://yflwudkmhqwoscipscbb.supabase.co`.
- **Source control:** GitHub `marwanhamedahmedmaher-sudo/Jawaker` (pushed 2026-04-17). Default branch `main`. `.claude/` and `.obsidian/` are fully gitignored — never commit editor/tooling state (can accrue local paths + anon keys). Root `.gitignore` also covers `.env.admin`, `*.jks`, `*.keystore`, `android/key.properties`.
- **Auth model:** Sales reps only log in. Admin-provisioned accounts. Phone + password, biometric fast-path via `local_auth`. **No OTP in V1.** No SMS provider.
- **Admin UX — Option A (Dashboard-only for pilot):** Rep provisioning, suspend/reactivate, merchant list, and CSV export all done via Supabase Studio (Auth UI + Table Editor + saved SQL snippets). No in-app admin screens for V1. Graduate to Option B (in-app admin + Edge Function) post-pilot.
- **Dedup & format enforcement:** Postgres triggers normalize phone (E.164) and National ID on write to `auth.users` and `merchants`; `UNIQUE` constraints catch duplicates at insert time. Format validation also in triggers — bad data rejected by Dashboard immediately.
- **Forgot password:** Admin-mediated reset in Supabase Dashboard → new temp password → rep rotates via in-app change-password screen (reuses `must_change_password` flow).
- **Temp-password delivery (pilot):** Admin sends manually via email **and** WhatsApp. No automated channel in V1. Runbook (P0-18) documents both.
- **Exports:** Saved SQL snippets in Supabase SQL Editor → "Download CSV" button. 3-click workflow, no SQL typed after setup. Arabic-friendly column headers, joined rep names, filtered columns.
- **Audit:** In-app `audit_log` captures rep actions only. Admin actions logged by Supabase Dashboard (system of record for V1). Accepted gap — revisit before production launch.
- **Dashboard access discipline:** Keep Supabase project member list to 1–2 people max. 2FA mandatory on Supabase accounts.
- **Merchant identity scope (V1):** Egyptian **individuals only**. 14-digit National ID, structural rules (century + birthdate + governorate code + serial + checksum). Businesses / commercial registration deferred to post-pilot (see P2 backlog).
- **POC scope — lead capture only:** Reps collect `name`, `phone`, `national_id` (number only), `notes`, `status`. **No KYC images, no selfies, no ID-card photos** during pilot. Full merchant onboarding + KYC handled by other teams' existing software; Aman feeds them leads via Supabase SQL exports. Aman graduates into full merchant profile + KYC post-pilot (see P2-6).
- **Security posture (POC):** `merchants.national_id` stored via **Supabase Vault** (pgsodium Transparent Column Encryption) — ciphertext at rest, decrypted transparently for authorized RLS reads. Plaintext `merchants.national_id_hash text UNIQUE` companion column for dedup (SHA-256 of normalized ID). Baseline stack: TLS, at-rest encryption, RLS, 2FA on Dashboard, in-app audit log. Client-side encryption / external key broker deferred to pre-production pending PDPL legal response.
- **UI masking + reveal-with-audit:** Deferred to post-POC — added when the dedicated merchant profile screen is built (see P1-6). POC displays National ID fully to the submitting rep only.
- **Bad-data behavior:** **Hard-reject** at DB trigger level for malformed phone or National ID. Bad input surfaces Arabic error (`رقم الموبايل غير صحيح` / `رقم القومي غير صحيح`) and the insert fails. No flag-and-save. Consistent with "bad data rejected by Dashboard immediately" principle.
- **Phase 1 scope matches the Figma reference flow** at https://kale-wired-82468678.figma.site — phone → password → (change-password if `must_change_password`) → home → single-screen lead form. No OTP, no KYC images, no 3-step registration. Implementation guide: `docs/P0-IMPLEMENTATION-GUIDE.md`.
- **Provisioning model — Option C1 (script via Admin API):** `scripts/provision_rep.sh` + `scripts/reset_password.sh` call Supabase Admin API with `phone_confirm: true` (no SMS). **Service-role keys (dev + prod) now resolved from Bitwarden as of 2026-04-17 (evening)** — `.env.admin` uses `export SUPABASE_SERVICE_ROLE_KEY="$("$BW_CLI" get password 'Aman Supabase [Dev|Prod] service_role')"` with `$BW_CLI` hardcoded to the winget-installed `bw.exe` path (dodges Git Bash not inheriting the winget-updated Windows PATH). No plaintext JWTs in the file tree. Both keys rotated at migration time. Requires `export BW_SESSION=$("$BW_CLI" unlock --raw)` in the current shell before `source .env.admin` — the script dies fast if the JWT regex fails. Graduates to Edge Function (C2) post-pilot.
- **Phone provider ON, SMS provider UNCONFIGURED — permanent V1 rule.** Phone provider is required for phone-as-username login; SMS provider must remain unconfigured to avoid silently enabling billable OTP flows the app does not implement. Documented as a hard rule in P0-18 runbook.
- **Public signup OFF.** Authentication → Settings → "Allow new users to sign up" → OFF. Admin-only provisioning is enforced at the Auth layer, not just by convention.
- **NID reveal policy (V1):** One tap on "Reveal NID" in the merchant profile screen → plaintext NID visible for the remainder of that screen visit. Navigating away re-masks; returning requires another tap. Each tap writes one `national_id_revealed` row to `audit_log` via RPC. No timer, no re-prompt. Simple, auditable, one-audit-row-per-intent.
- **RTL-first UI:** App is Arabic-first for Egyptian reps. All screens must render RTL by default (`Locale('ar', 'EG')` + locale-driven `Directionality`). New screens built RTL-native; existing screens audited and fixed before pilot.
- **Merchant list + profile scope (V1):** Reps access their own merchants via the home dashboard card ("created this week") → full merchant list (not filtered). View-only. Admin "all merchants" view deferred to post-pilot.
- **Product-specific data capture:** Each product selection on the lead form can trigger additional required fields. Microfinance → "المبلغ" (amount, numeric). Acceptance POS → "عدد الأجهزة" (device count, integer). BP POS → no extra fields. DB CHECK constraints enforce: detail required when product selected, must be NULL when product not selected. Client validates before submit; DB is final authority.
- **Merchant information fields (optional):** Three informational fields on the lead form: `avg_monthly_sales` (numeric, EGP), `business_address` (free text), `activity_type_id` (FK to `activity_types` lookup table). All nullable — not required for lead submission. Activity types managed by admin via Supabase Dashboard Table Editor; seeded with 10 values (سوبر ماركت, صيدلية, مطعم, كافيه, بقالة, ملابس, إلكترونيات, مواد بناء, خدمات, أخرى). RLS: authenticated read, admin write.
- **Release APK builds via GitHub Actions CI (not local).** Local Windows release builds blocked by Gradle's inability to bind a loopback socket on Marwan's corp-managed laptop — the hosts file has been stripped of the default `127.0.0.1 localhost` / `::1 localhost` entries and admin rights aren't available to restore them. Switched to `.github/workflows/build-pilot-apk.yml` (manual `workflow_dispatch` trigger, Ubuntu runner, pinned `flutter-version: 3.41.6` to match local dev exactly). Keystore, passwords, and Supabase creds live in GitHub repo Secrets; signed release APK uploaded as a 30-day artifact. Pipeline hard-fails on missing Supabase secrets, empty `apksigner`, empty `version_name`, and any `service_role` / `SERVICE_ROLE_KEY` match in the decompiled APK. Local dev still runs `flutter analyze` + debug APKs fine — only release signing is CI-exclusive.
- **Keystore password storage (pilot):** Password lives in plaintext at `C:\Users\marwan.haahmed\aman-keystore-password.txt` alongside `C:\Users\marwan.haahmed\aman-release.jks` on Marwan's encrypted laptop, and both files are backed up in the same encrypted 7z archive (cloud + USB). 20-char cryptographically-random alphanumeric password (no memorization). Decision forced 2026-04-17 after the previous memorized password was forgotten between generation and first CI sign attempt — keystore had to be regenerated mid-pilot. **No memorization-only passwords for the keystore under any circumstances.** Proper password manager migration (P2-7) upgrade trigger is effectively already met — treat as overdue, not "before production rollout".
- **Product analytics — Mixpanel, rep behavioural events only.** SDK: `mixpanel_flutter`, token injected via `--dart-define=MIXPANEL_TOKEN` (optional — empty token routes all calls to a NoopSink, so local dev + token-less CI builds stay silent). Residency explicitly not a concern here per product call — Mixpanel is US-hosted and that's acceptable because **events carry rep behaviour only, never merchant PII**. Hard rule enforced in code: `lib/services/analytics.dart` runs a debug-mode `assert` over every property map and throws on keys matching `national_id|nid_hash|\bnid\b|phone|password|merchant_name|full_name` — PII leaks surface locally before they ship. Merchant UUIDs are allowed (non-PII opaque identifier). All call sites go through the `Analytics` facade, not the SDK directly, so swapping vendors (PostHog, Amplitude, self-host) stays a single-file change. Events tracked today: `app_started`, `login_succeeded/failed`, `password_changed/change_failed`, `biometric_enabled`, `biometric_login_attempted/failed`, `logged_out`, `lead_form_opened`, `lead_product_selected/deselected`, `lead_validation_failed`, `lead_submit_attempted/succeeded/failed`, `merchant_list_viewed`, `merchant_profile_viewed`, `nid_revealed/reveal_failed`. Identity attached via `Analytics.identify(repId)` on login; cleared via `Analytics.reset()` on logout.

---

## Backlog

Status markers: `TODO` | `IN_PROGRESS` | `DONE` | `BLOCKED`

### P0 — Must Ship (pilot blockers)

| # | Task | Status | Assigned | Notes |
|---|------|--------|----------|-------|
| 1 | Supabase project setup (dev + prod) | DONE 2026-04-16 | — | Dev: `yynhcrtdzgcgedkolgxw`. **Prod: `yflwudkmhqwoscipscbb`** — both eu-west-1, Postgres 17. Prod: all 15 migrations applied, RLS on 6 tables, 10 activity types seeded, 5 RPCs verified, security advisors clean. **Auth settings confirmed by Marwan 2026-04-16** (phone ON, SMS OFF, signup OFF, 2FA enabled). **First signed pilot APK built via GitHub Actions 2026-04-17** — `.github/workflows/build-pilot-apk.yml` produced `aman-v1.0.0-pilot.apk` against prod Supabase credentials. **First real pilot rep provisioned + full prod smoke test green 2026-04-17 (evening)** — `scripts/provision_rep.sh` against prod via Bitwarden-sourced service-role key; APK on Android emulator walked end-to-end (phone+password login → forced change-password via `must_change_password` flip → home dashboard RTL Arabic → new-lead form with all 3 products + microfinance amount → `merchants` row landed with E.164 phone and SHA-256 NID hash → `audit_log` row captured INSERT action with actor_id = rep UUID, same tx as insert). |
| 2 | Postgres schema: `users`, `merchants`, `audit_log` | DONE 2026-04-14 | — | `supabase/migrations/001_schema.sql`. Vault TCE on `national_id`, `national_id_hash UNIQUE` for dedup. |
| 3 | Role model: `sales_rep`, `admin` via custom claims | DONE 2026-04-14 | — | `set_claim()` SQL function in 001_schema.sql. Enforced in RLS (004_rls_policies.sql). |
| 4 | Auth wiring: `signInWithPassword` + `must_change_password` flag | DONE 2026-04-14 | — | `auth_provider.dart` fully rewritten. `signIn()`, `changePassword()`, `completeAuth()`. |
| 5 | Prototype rework: remove OTP screen, adjust routing | DONE 2026-04-14 | — | OTP screen + otp_input widget deleted. Phone entry always → password. |
| 6 | Biometric fast-path via `local_auth` package | DONE 2026-04-14 | — | `canUseBiometric()`, `enableBiometric()`, `signInWithBiometric()` in auth_provider. Opt-in dialog in password_screen. |
| 7 | Lead registration: Postgres insert + National ID dedup | DONE 2026-04-14 | — | Single-screen `new_lead_screen.dart`. `LeadProvider.submit()` inserts to merchants, surfaces Arabic dedup error. |
| 8 | ~~KYC image upload to Supabase Storage~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped from POC. Lead-capture-only scope — KYC handled by downstream systems. Revisit when Aman grows into full merchant profile (P2-6). |
| 9 | RLS policies: reps see own records, admins see all | DONE 2026-04-14 | — | `supabase/migrations/004_rls_policies.sql`. `is_admin()` helper. All 3 tables covered. |
| 10 | ~~Admin screen: provision rep~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped. Provisioning via Supabase Dashboard Auth UI. See Dashboard runbook (P0-18). |
| 11 | ~~Admin screen: list reps, suspend/reactivate~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped. Use Dashboard "Ban user" toggle + `users.status` trigger sync. |
| 12 | ~~Admin screen: list merchants with filters~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped. Use Supabase Table Editor (filter/sort UI, no SQL). |
| 13 | ~~CSV + Excel export via Edge Function~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped. Replaced by saved SQL snippets (P0-17). |
| 14 | Audit log triggers (rep actions only) | DONE 2026-04-14 | — | `supabase/migrations/005_audit_triggers.sql`. AFTER triggers on merchants INSERT/UPDATE/DELETE. |
| 15 | Testing + hardening | DONE 2026-04-15 | — | End-to-end smoke test passed: phone login → password auth → forced change-password → lead submission with products → Supabase verification. Merchant row, E.164 normalization, NID hash, products array, and audit log INSERT all confirmed. Trigger test fixtures (D3) verified earlier. |
| 16a | Phone normalization & format trigger | DONE 2026-04-14 | — | `supabase/migrations/002_phone_trigger.sql`. BEFORE trigger on merchants. E.164, hard-reject, Arabic error. Test fixtures included. |
| 16b | National ID normalization & format trigger | DONE 2026-04-14 | — | `supabase/migrations/003_national_id_trigger.sql`. 14-digit structural validation, SHA-256 hash, hard-reject, Arabic error. Test fixtures included. |
| 17 | Saved SQL snippets for admin exports | DONE 2026-04-14 | — | `supabase/migrations/006_export_snippets.sql`. 4 snippets with Arabic headers. |
| 18 | Dashboard operator runbook (Arabic + English) | DONE 2026-04-14 | — | `docs/P0-DASHBOARD-RUNBOOK.md`. Bilingual. Covers create rep, suspend, reset password, export, 2FA. |
| 19 | Change-password screen (logged-in user) | DONE 2026-04-14 | — | `lib/screens/auth/change_password_screen.dart`. Handles first-login rotation + voluntary change. |
| 20 | Provisioning scripts (Option C1) | DONE 2026-04-15 | — | `scripts/provision_rep.sh` + `scripts/reset_password.sh` + `.env.admin.example`. Admin API + `phone_confirm: true` (no SMS). Service-role key from password manager at runtime. `.gitignore` updated. P0-18 runbook updated with SMS hard-rule + script section (v1.1). |
| 21 | Product-interest capture on lead form | DONE 2026-04-15 | — | Migration 008 (`products text[]` + CHECK constraint for Microfinance / BP POS / Acceptance POS, ≥1 required). Migration 009 (audit trigger early-return on NULL `auth.uid()` to unblock Dashboard writes). Flutter: `Lead.products`, `toggleProduct`, checkbox UI in new_lead_screen. |

### P1 — Should Ship (pilot quality)

| # | Task | Status | Assigned | Notes |
|---|------|--------|----------|-------|
| 1 | National ID format validation | TODO | — | Client regex + server check. Egypt-specific rules TBD. |
| 2 | Soft delete for merchants | TODO | — | `deleted_at` column. Preserves dedup history. |
| 3 | Excel (.xlsx) export option | TODO | — | Alongside CSV. |
| 4 | Forgot password flow (admin-mediated) | DONE-BY-DESIGN 2026-04-14 | — | Rep messages admin → admin resets in Supabase Dashboard → rep rotates via change-password screen (P0-19). No in-app self-serve flow for V1. |
| 5 | ~~Image compression before upload~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped — no image uploads in POC. Revisit with P2-6 (full merchant profile + KYC). |
| 6 | UI masking + reveal-with-audit for National ID | DONE 2026-04-15 | — | Implemented as part of P1-9. `MerchantProfileScreen` shows `*************` by default. "عرض" (Reveal) button calls `reveal_national_id` RPC → plaintext NID displayed for rest of screen visit + `national_id_revealed` audit row written. |
| 7 | Client-side guard: block submit when zero products selected | DONE 2026-04-15 | — | Submit button in `new_lead_screen.dart:196` now disabled when `provider.lead.products.isEmpty`. Immediate visual feedback (grayed-out button) instead of raw DB error. `validate()` in `LeadProvider` remains as second guard. |
| 8 | App-wide RTL enforcement | DONE 2026-04-15 | — | `main.dart` already had `locale: Locale('ar', 'EG')`, `supportedLocales`, `localizationsDelegates`, and `Directionality(textDirection: TextDirection.rtl)` builder wrapper. All screens use directional-aware widgets (`AlignmentDirectional`, `EdgeInsetsDirectional`). Confirmed RTL-native before P1-9 implementation. |
| 9 | Merchant list + profile screen (rep's own merchants) | DONE 2026-04-15 | — | Migration 010 (`reveal_national_id` SECURITY DEFINER RPC — returns plaintext NID + writes `national_id_revealed` audit row atomically). `MerchantListProvider` (fetch list excluding NID, weekly count, reveal RPC call). `MerchantListScreen` (rep's own merchants, masked phone, status badges, pull-to-refresh). `MerchantProfileScreen` (view-only, masked NID with "عرض" reveal button, products, notes). Home stats card now dynamic + tappable → merchant list. `MultiProvider` in `main.dart`. Closes P1-6. |
| 10 | Product-specific fields on lead form | DONE 2026-04-15 | — | Migration 011 (`microfinance_amount numeric`, `acceptance_device_count integer` + 4 CHECK constraints). Lead model + provider updated. Lead form shows conditional fields per product (Microfinance → amount, Acceptance POS → device count, BP POS → none). Merchant profile displays product details. Home dashboard weekly count now refreshes on navigation return. |
| 11 | Merchant information fields (avg sales, address, activity type) | DONE 2026-04-15 | — | Migration 012: `activity_types` table (10 seeded rows, RLS, admin-managed) + 3 nullable columns on `merchants` (`avg_monthly_sales`, `business_address`, `activity_type_id` FK). `ActivityType` model. Lead form: 3 new optional fields (numeric, text, dropdown). Profile: conditional info cards. List provider: Supabase foreign-table embed for activity type name. |
| 12 | Pre-pilot code review agent (CodeRabbit) | DONE 2026-04-16 | — | `.coderabbit.yaml` (assertive profile, 5 path-scoped rules, 5 pre-merge gates: RLS enabled, SECURITY DEFINER hardening, no plaintext NID leak, secrets hygiene, RTL-safe UI) + `.github/REVIEW_CONTEXT.md` (fintech/PDPL review ruleset, file-level grounding, pilot checklist). Tool choice: CodeRabbit over Greptile (higher precision, $24 vs $30/dev/mo, GitHub-native). Auto-discovers `CLAUDE.md` + `ARCHITECTURE.md` via `knowledge_base.code_guidelines`. Wiring up on GitHub requires installing the CodeRabbit GitHub App on the repo. |
| 13 | Product analytics — Mixpanel integration (rep behavioural events) | DONE 2026-04-17 | — | `mixpanel_flutter ^2.3.1` (resolves to 2.6.2), vendor-neutral `Analytics` facade in `lib/services/analytics.dart` with PII-scrub `assert`. Token via `--dart-define=MIXPANEL_TOKEN` (empty → NoopSink). `MIXPANEL_TOKEN` added as optional secret to `.github/workflows/build-pilot-apk.yml`. Events wired in `auth_provider`, `merchant_provider` (LeadProvider), `merchant_list_provider`, `new_lead_screen`, `merchant_list_screen`, `merchant_profile_screen`. `flutter analyze` clean. **Before next APK build:** create Mixpanel project + add `MIXPANEL_TOKEN` to GitHub Actions secrets (optional — build still works without it). |
| 14 | Regression automation — Patrol golden-path on Android emulator | IN_PROGRESS | — | `patrol ^3.13.0` + `integration_test` dev deps. [integration_test/patrol_test.dart](integration_test/patrol_test.dart) covers: phone→password→biometric-dialog-dismiss→home→new-lead (all 3 products + microfinance amount + device count)→success→merchant-list→profile→NID reveal. Every run tags its merchant row with `PATROL-TEST-<ts>-<rand>` in `notes` for cleanup; `tearDown` deletes via the rep's JWT (RLS-scoped, no service-role in CI). NID generator fixed-prefix `28501010` + 6 random digits; phone `0109999XXXX`. Android test runner wired in [android/app/build.gradle.kts](android/app/build.gradle.kts) + [MainActivityTest.java](android/app/src/androidTest/java/com/aman/aman_sales_app/MainActivityTest.java). CI at [.github/workflows/patrol-regression.yml](.github/workflows/patrol-regression.yml) — Ubuntu + `reactivecircus/android-emulator-runner@v2` API 33 + KVM + cached AVD. Runs on every PR touching `lib/`/`pubspec.yaml`/`integration_test/`/`android/`. **Known gap** (documented): first-login change-password flow not covered — would need service-role in CI to provision a fresh rep per run, deferred with Option C2 graduation. Runbook: [docs/PATROL-RUNBOOK.md](docs/PATROL-RUNBOOK.md). **Before first CI run (pending Marwan):** (1) provision durable test rep in prod (`+201099990000`), rotate its temp password, (2) add `PATROL_TEST_PHONE` + `PATROL_TEST_PASSWORD` GH secrets, (3) trigger workflow manually for first-run AVD cache warm-up. |

### P2 — Nice to Have

| # | Task | Status | Assigned | Notes |
|---|------|--------|----------|-------|
| 1 | Fuzzy dedup on name + phone | TODO | — | Postgres trigram / levenshtein. Warn on likely duplicate. |
| 2 | Bulk CSV import (admin) | TODO | — | Upload existing spreadsheet. |
| 3 | Per-rep quota dashboard | TODO | — | Home screen widget. |
| 4 | Offline lead draft queue | TODO | — | If field-rep scenario confirmed post-pilot. |
| 5 | Business merchant support (commercial registration) | TODO | — | Add `document_type` column (`national_id` \| `commercial_reg`), extend validation trigger with commercial-registration format. Deferred from V1 scope decision 2026-04-14. |
| 6 | Evolve beyond lead capture — full merchant profile + KYC | TODO | — | Post-POC evolution: KYC image capture (ID front/back, selfie), storage bucket with RLS, image compression, full merchant profile screen, reveal-with-audit pattern. Re-activates former P0-8 + P1-5. Scope to be re-planned after pilot learnings. |
| 7 | Post-pilot: move keystore + passwords to proper password manager | IN_PROGRESS | — | **Half done 2026-04-17 (evening):** service-role key migration complete — dev + prod keys rotated, stored in Bitwarden items `Aman Supabase [Dev|Prod] service_role`, `.env.admin` now resolves via `bw get password` with hardcoded `$BW_CLI` path; no plaintext JWTs in the tree. **Still TODO — keystore half:** plaintext `aman-keystore-password.txt` next to `.jks` (encrypted 7z + cloud + USB). Attach `.jks` + keystore/key passwords to a Bitwarden item (paid tier needed for file attachments; free tier only works with a `Secure Note` of the password + keystore stored elsewhere). Original hard triggers (prod rollout beyond pilot cohort OR second admin) still apply as backstops for the keystore half. |
| 8 | APK size trim — under 50 MB for WhatsApp distribution | DONE 2026-04-17 | — | Solved via `--split-per-abi` in [`.github/workflows/build-pilot-apk.yml`](.github/workflows/build-pilot-apk.yml) ([PR #5](https://github.com/marwanhamedahmedmaher-sudo/Jawaker/pull/5), merged 2026-04-17). CI now emits three separately-signed APKs — `armeabi-v7a` **16.7 MB**, `arm64-v8a` **19.0 MB** (what pilot reps install), `x86_64` **20.5 MB** — all well under the 50 MB WhatsApp cap. Signature verify + secret scan now loop over all three; ABI list hoisted to a job-level `$ABIS` env var so future additions cannot silently skip a step. Secret scan also extended to hard-block keystore-credential markers (`storePassword` / `keyPassword` / `KEYSTORE_PASSWORD` / `KEY_PASSWORD`) and 14-digit Egyptian NID pattern (`\b[23][0-9]{13}\b`). R8 shrink/minify not needed for the pilot; leave on the shelf. |
| 9 | ~~Supabase Dashboard bug: phone-only users invisible in Auth → Users~~ | NOT-A-BUG 2026-04-17 | — | Resolved: filter was set to "Email address" search, which correctly excludes phone-only users. Not a Dashboard bug. Clearing the filter or switching to "Phone" surfaces the row. No runbook change needed. |

---

## Blockers

| Blocker | Blocking Task(s) | Owner | Since | Resolution |
|---------|------------------|-------|-------|------------|
| MENA data residency (PDPL Law 151/2020) — monitoring, not blocking | P0-1 (Supabase project setup) — deferred until legal confirms, but build work on portable SQL (P0-16a/b) proceeds | Marwan + legal | 2026-04-14 | Downgraded from CRITICAL 2026-04-14 per Marwan. Risk surface reduced (POC = lead capture only; Supabase Vault at rest). Awaiting legal review of PDPL Article 14 against narrower scope. Graduation path if in-region required: AWS Bahrain / on-prem. Not flagging further — will revisit when legal responds. |
| ~~Temp-password delivery channel (admin → rep)~~ | ~~P0-18 (runbook)~~ | Marwan | 2026-04-14 → RESOLVED 2026-04-14 | **Resolved:** Email + WhatsApp, sent manually by admin during pilot. Runbook (P0-18) should document both channels and note manual send. |
| ~~Egypt National ID format spec~~ | ~~P0-7, P0-16, P1-1~~ | Marwan | 2026-04-14 → RESOLVED 2026-04-14 | **Resolved:** Egyptian individuals only for V1 — 14-digit National ID. Businesses deferred to P2-5. |

---

## Session Log

Most recent first. Cap at 5 entries — archive older to `CLAUDE.archive.md`.

### Session: 2026-04-17 (late evening) — Patrol regression harness wired: golden-path on Android emulator
**Duration:** ~45m
**Focus:** Stand up the first automated regression test so the pilot pipeline has a gate in front of the signed-APK step. Previous sessions left this as the top Next Session item — user picked Patrol over Maestro/Appium.
**Completed:**
- **Patrol 3.x + integration_test wiring**:
  - `patrol: ^3.13.0` + `integration_test` added to dev_dependencies in [pubspec.yaml](pubspec.yaml); `patrol:` config block names the Android package so the CLI can discover the test runner.
  - Android test instrumentation: [android/app/build.gradle.kts](android/app/build.gradle.kts) gets `testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"` + `clearPackageData=true` + `ANDROIDX_TEST_ORCHESTRATOR` execution + `androidx.test:orchestrator` util dep. Parameterized runner stub at [android/app/src/androidTest/java/com/aman/aman_sales_app/MainActivityTest.java](android/app/src/androidTest/java/com/aman/aman_sales_app/MainActivityTest.java).
- **Golden-path test** [integration_test/patrol_test.dart](integration_test/patrol_test.dart) covers, in order:
  1. Phone entry (11-digit Egyptian mobile, normalized from `PATROL_TEST_PHONE` if supplied as E.164) → tap "تسجيل الدخول".
  2. Password entry from `PATROL_TEST_PASSWORD` → tap "دخول".
  3. Defensive biometric opt-in dialog dismiss (3-second wait, tap "لاحقا" if surfaced — CI emulators lack biometric hw so it's usually absent).
  4. Home assertion (Arabic "أهلا" greeting visible).
  5. New-lead form — all 3 products checked (`Microfinance` with `50000` amount, `BP POS`, `Acceptance POS` with `3` devices), plus tagged name/notes carrying the run's `patrolRunTag`.
  6. Submit → success screen "تم تسجيل العميل بنجاح" → "العودة للرئيسية".
  7. Home stats card tap "تم إنشاؤهم هذا الأسبوع" → merchant list.
  8. Tap tagged row → profile "بيانات العميل".
  9. NID pre-reveal: assert 14 bullets `*************`. Tap "عرض". Post-reveal: regex-assert `^28501010\d{6}$` (fixed prefix from the test NID generator).
- **Test data generators** [integration_test/helpers/test_data.dart](integration_test/helpers/test_data.dart):
  - `patrolRunTag` = `PATROL-TEST-<UTC yyyymmdd-hhmmss>-<6-hex>` — unique per run, survives parallel runs, trivially globbable for cleanup.
  - `generateTestPhone()` → `0109999XXXX` (Vodafone 010 prefix, 9999 non-allocated bucket, 4 random digits).
  - `generateTestNationalId()` → `28501010` (century 2 + 1985-01-01 + Cairo gov 01) + 6 random digits. Passes migration 003's trigger (century, YYMMDD, governorate, digit-count) without needing a real checksum since V1 accepts any digit for position 14.
- **Cleanup** [integration_test/helpers/test_cleanup.dart](integration_test/helpers/test_cleanup.dart): `tearDown` calls `cleanupMerchantsByTag(patrolRunTag)` which runs a `DELETE FROM merchants WHERE notes LIKE '%<tag>%'` via the authenticated rep's JWT. RLS confines the delete to the rep's own rows, so **no service-role key is needed in CI**. `audit_log` rows are retained by design (V1 forensic record).
- **CI workflow** [.github/workflows/patrol-regression.yml](.github/workflows/patrol-regression.yml): Ubuntu + `reactivecircus/android-emulator-runner@v2` API 33 google_apis x86_64 on a Pixel 6 profile. KVM enabled for ~30s emulator boot (vs minutes with swiftshader). Two-phase emulator step — first creates+caches the AVD snapshot, second runs Patrol against the warm snapshot. Triggers on PR when `lib/`/`pubspec.yaml`/`pubspec.lock`/`integration_test/`/`android/`/the workflow itself changes; also manual `workflow_dispatch`. Concurrency group per ref so parallel PR runs don't collide on prod's dedup constraints. All 4 secrets fail-fast validated before the Patrol invocation. Failure uploads `patrol-failure-logs` artifact with 14-day retention.
- **Runbook** [docs/PATROL-RUNBOOK.md](docs/PATROL-RUNBOOK.md) covers: one-time test-rep provisioning via `scripts/provision_rep.sh` + password rotation, GH secret setup, local `patrol test` invocation, recovery SQL for crashed-run leftovers, common failure modes.
**Decisions:**
- **Prod Supabase, not dev.** User directive — accept the cost of polluting prod `audit_log` with a trickle of test rows in exchange for testing what actually ships. Tag-based row cleanup keeps `merchants` clean; audit retention is V1 policy anyway.
- **No service-role key in CI.** Cleanup uses the rep's own JWT + RLS. Cheaper security posture than adding another long-lived admin credential to the Actions secret store.
- **Skip first-login change-password in golden path.** Documented as a known gap. Covering it would require provisioning a fresh rep every run (service-role in CI) or running it as an optional workflow triggered only when the change-password code is touched. Revisit when admin graduates to Option C2 (Edge Function).
- **Durable test rep, rotation-free.** A fresh-per-run rep would make change-password coverage trivial but doubles the provisioning blast radius. One rep, one post-rotation password stored in GH secrets, rotated manually when Marwan wants.
- **Anchor finders on Arabic strings + widget types, not widget keys.** Keeps the test readable in context and avoids littering feature code with `Key('...')` nodes just for testing. Tradeoff: if a screen's Arabic copy changes the test breaks — the runbook lists this as the #1 failure mode.
- **Use existing pilot APK at runtime (debug-signed from Patrol's flutter-build).** No keystore needed for the test build; Patrol uses a debug signature which doesn't conflict with any release install because the emulator is wiped between AVD cache warmups.
**Backlog impact:**
- **P1-14 added — IN_PROGRESS.** Not pilot-blocking (pilot can ship without it) but the highest-ROI infra investment before rollout scales. Status stays `IN_PROGRESS` until the first green CI run lands.
- No other backlog changes.
**Blockers now:** 0 active.
**Files changed:**
- `pubspec.yaml` (+7 lines — patrol/integration_test deps + patrol config block)
- `android/app/build.gradle.kts` (+7 lines — instrumentation runner + orchestrator)
- `android/app/src/androidTest/java/com/aman/aman_sales_app/MainActivityTest.java` (new, ~35 lines — Patrol JUnit runner stub)
- `integration_test/patrol_test.dart` (new, ~170 lines — golden path)
- `integration_test/helpers/test_data.dart` (new, ~35 lines — generators)
- `integration_test/helpers/test_cleanup.dart` (new, ~25 lines — rep-JWT delete)
- `.github/workflows/patrol-regression.yml` (new, ~115 lines — CI)
- `docs/PATROL-RUNBOOK.md` (new, ~155 lines)
- `CLAUDE.md` (P1-14 row, this entry, rotation)
- `CLAUDE.archive.md` (rotated 2026-04-16 late-late-night entry)
**Pending user action (required before first CI run):**
1. Provision the durable Patrol test rep against **prod** — follow [docs/PATROL-RUNBOOK.md](docs/PATROL-RUNBOOK.md) § "One-time setup". Suggested phone: `+201099990000`. Log in with the temp password from `scripts/provision_rep.sh`, rotate it, save the final password.
2. Add 2 new GitHub Actions secrets: `PATROL_TEST_PHONE` and `PATROL_TEST_PASSWORD` (the rotated password, not the temp). `SUPABASE_URL` and `SUPABASE_ANON_KEY` are already set from the build workflow — reused, no duplication needed.
3. Trigger `Patrol Regression` workflow manually from `main` first — this warms the AVD cache (~15–20 min cold). Subsequent runs are ~5–8 min.
4. When the first run is green, flip P1-14 from `IN_PROGRESS` to `DONE <date>`.
**Next Session:**
1. **Pentest automation** — now that regression is wired, stand up the security layer. Two parallel tracks recommended: (a) MobSF Docker step inside `.github/workflows/build-pilot-apk.yml` after the existing `apktool` decompile (hard-fail on High/Critical, baseline Flutter-framework false positives in a yaml allowlist); (b) RLS fuzzing via a Dart script that walks a matrix of PostgREST calls with differently-signed rep JWTs to prove cross-rep reads/writes get rejected.
2. **Two CodeRabbit follow-ups still unopened from 2026-04-17 afternoon** — Security Definer hardening (`SET search_path` + `set_claim` internal-only) and the RTL fix in `forgot_password_screen.dart:19`. File before pilot traffic accumulates.
3. If Patrol stabilizes and proves useful, expand the golden path into feature-specific tests triggered by path filters (e.g. tasks feature test only on `lib/providers/tasks_provider.dart` changes) — keeps individual runs fast while widening coverage.

### Session: 2026-04-17 (post-prod-smoke) — Product analytics wired: Mixpanel + vendor-neutral Analytics facade
**Duration:** ~40m
**Focus:** Stand up pilot product analytics so rep-behaviour funnels are observable from day one of rollout. Previous sessions already proved the prod pipeline works; now we need telemetry to actually learn from pilot usage.
**Completed:**
- **Vendor choice**: Mixpanel over PostHog — both now ship session replay (PostHog and Mixpanel launched it 2024), and Mixpanel's free tier (20M events/mo) is ~20× PostHog's at this volume. Residency was the usual blocker (Mixpanel is US-hosted), but per product call it's acceptable because **rep-behaviour events carry no merchant PII** — merchant NIDs, phones, and names stay in Supabase's eu-west-1 under the existing PDPL posture. See new Current Decisions entry.
- **Vendor-neutral `Analytics` facade** in [lib/services/analytics.dart](lib/services/analytics.dart): sink abstraction with `_MixpanelSink` + `_NoopSink`, `init`/`identify`/`track`/`reset` surface, and a debug-mode `assert` that throws `StateError` on any property key matching `national_id|nid_hash|\bnid\b|phone|password|merchant_name|full_name`. The noop sink prints to `debugPrint` so local dev shows events without needing a token. Token arrives via `--dart-define=MIXPANEL_TOKEN`; empty string → NoopSink. Swap-out stays a single-file change if we ever migrate to PostHog / self-hosted / Amplitude.
- **SDK wiring**: `mixpanel_flutter: ^2.3.1` added to `pubspec.yaml`, resolved to `2.6.2`. `flutter pub get` clean.
- **Event coverage** — auth funnel + lead funnel + merchant interactions:
  - `auth_provider.dart`: `login_succeeded` / `login_failed` (with `reason`: `no_user` / `auth_exception` / `unexpected`), `identify(repId)` on success, `password_changed` (with `was_forced` captured before the flag flips), `password_change_failed`, `biometric_enabled`, `biometric_login_attempted` / `biometric_login_failed` (with `reason`: `user_cancelled` / `no_credentials`), `logged_out` + `reset()`.
  - `merchant_provider.dart` (LeadProvider): `lead_product_selected` / `lead_product_deselected`, `lead_submit_attempted` (captures product list, optional-field presence, `notes_length`), `lead_submit_succeeded` (products + count), `lead_submit_failed` (with `reason`: `duplicate_nid` / `invalid_phone` / `invalid_nid` / `postgrest_other` / `unexpected`, plus `pg_code`).
  - `new_lead_screen.dart`: `lead_form_opened` (with `from_task` bool), `lead_validation_failed`.
  - `merchant_list_provider.dart`: `nid_revealed` (with `merchant_id` UUID only — complements the server-side `audit_log` row for the same intent), `nid_reveal_failed`.
  - `merchant_list_screen.dart`: `merchant_list_viewed`.
  - `merchant_profile_screen.dart`: `merchant_profile_viewed` (with status + product count).
  - `main.dart`: `app_started` on boot.
- **CI wiring**: [.github/workflows/build-pilot-apk.yml](.github/workflows/build-pilot-apk.yml) passes `MIXPANEL_TOKEN` via `--dart-define`. Secret is optional — if unset, the build still succeeds and events route to NoopSink. Existing secret-scan gate (`service_role|supabase_service_role|SERVICE_ROLE_KEY`) needs no changes — Mixpanel project tokens are non-secret (like Supabase anon keys) and don't match the blocklist.
- **`flutter analyze` clean** after all wiring.
**Decisions:**
- **Residency explicitly not a concern for rep behaviour events.** Recorded as a Current Decision. Merchant PII stays in Supabase eu-west-1; Mixpanel only ever sees rep UUIDs + event names + non-PII properties. The debug-mode `assert` keeps the line durable even if future call sites drift.
- **Facade over direct SDK calls everywhere** — no `Mixpanel.instance.track(...)` in feature code. This is load-bearing for future vendor swaps and for the PII-scrub guarantee.
- **`forgot_password_screen` deliberately not instrumented** — stateless screen, would need a stateful wrapper for a clean initState firing, and the signal (how often reps hit "forgot password") is already implicit in admin password-reset frequency which the Dashboard captures.
- **Skipped Firebase Analytics** despite its generous free tier — adds ~3–5 MB (Google Play Services pull), which would worsen the existing 52 MB APK size (P2-8) and nudge us further over WhatsApp's 50 MB cap. Mixpanel SDK is ~1–2 MB.
**Backlog impact:**
- **P1-13 added (DONE 2026-04-17)**: Mixpanel integration with event list. This is infrastructure for pilot learning, not a pilot-blocking feature — hence P1 not P0.
- No status changes to existing rows.
- **New Current Decisions entry** documents the vendor choice + PII-scrub rule + facade pattern.
**Blockers now:** 0 active.
**Files changed:**
- `pubspec.yaml` (+1 dep)
- `lib/services/analytics.dart` (new, ~95 lines)
- `lib/main.dart` (+6 lines — init + app_started)
- `lib/providers/auth_provider.dart` (+ ~20 lines of `Analytics.track` / `identify` / `reset`)
- `lib/providers/merchant_provider.dart` (+ ~30 lines across `toggleProduct` + `submit`)
- `lib/providers/merchant_list_provider.dart` (+ `nid_revealed` / `nid_reveal_failed`)
- `lib/screens/lead/new_lead_screen.dart` (+ `lead_form_opened` / `lead_validation_failed`)
- `lib/screens/merchant/merchant_list_screen.dart` (+ `merchant_list_viewed`)
- `lib/screens/merchant/merchant_profile_screen.dart` (+ `merchant_profile_viewed`)
- `.github/workflows/build-pilot-apk.yml` (+ `MIXPANEL_TOKEN` env + `--dart-define`)
- `CLAUDE.md` (Current Decisions entry, P1-13 row, this session entry, rotation)
- `CLAUDE.archive.md` (rotated 2026-04-16 late-night entry)
**Pending user action:**
1. Create Mixpanel project (free tier) → grab the project token (32-char hex). Region: pick US (default) — we're not routing PII here.
2. Add `MIXPANEL_TOKEN` to GitHub repo Settings → Secrets and variables → Actions. Build will pick it up on the next `workflow_dispatch`.
3. Optionally run `flutter run --dart-define=MIXPANEL_TOKEN=<token>` locally to smoke-test events land in Mixpanel before the next pilot APK cut.
4. In Mixpanel, create one saved cohort ("Pilot reps") and one funnel report (`lead_form_opened` → `lead_submit_attempted` → `lead_submit_succeeded`) so the most important signal is one click away when pilot traffic starts.
**Next Session:**
1. **Regression automation** — stand up Patrol against the pilot APK. Golden-path test script (phone → password → change-password → new lead per product variant → merchant list → profile → NID reveal → `audit_log` assert via Supabase client). Wire into `.github/workflows/` as a gate before the signed-APK step; Linux runner + headless emulator is fiddly, recommend a macOS runner.
2. **Pentest automation** — highest risk-reduction-per-hour is RLS fuzzing + MobSF in CI. Script PostgREST calls with varied JWTs to prove RLS rejects cross-rep reads. Add MobSF docker step to `build-pilot-apk.yml` after the existing `apktool d` + `grep` secret scan; hard-fail on High/Critical.
3. **Two CodeRabbit follow-ups from 2026-04-17 afternoon session still unopened** — Security Definer hardening (`SET search_path` + internal `set_claim` access control) and RTL fix in `forgot_password_screen.dart:19`. File before pilot traffic accumulates.

### Session: 2026-04-17 (evening) — First live prod smoke test + service-role keys migrated to Bitwarden
**Duration:** ~2h (spread across a lot of interactive paste-back iterations)
**Focus:** Prove the signed pilot APK works against prod end-to-end, provision the first real pilot rep, and close the service-role-key half of P2-7 (move keys out of `.env.admin` plaintext into Bitwarden).
**Completed:**
- **APK onto emulator**: `gh run download 24584445426 --repo marwanhamedahmedmaher-sudo/Jawaker` → `aman-v1.0.0-pilot.apk` (52 MB) into [build/pilot-apk/](build/pilot-apk/). Uninstall-reinstall dance needed on the `android_emulator` AVD because the prior debug-signed install collided on signature (keystore was regenerated 2026-04-17 afternoon). App boots, Flutter Impeller GL backend initializes, RTL Arabic renders, phone-entry screen matches the Figma reference.
- **Bitwarden CLI migration (P2-7 half-close)**:
  - Installed `bw` via `winget install --id Bitwarden.CLI` (version 2026.3.0). Winget modified Windows PATH but existing Git Bash didn't inherit it — worked around by hardcoding `$BW_CLI` to the full winget install path in `.env.admin`.
  - **Leaked-session incident**: on first `bw login` Marwan pasted the full stdout back into chat. Bitwarden's "example" output after login embeds the **real** `BW_SESSION` token, not a placeholder. Killed the session with `bw logout` + re-login before any secret touched the wire. Updated working rules: master password / session tokens / service-role keys stay on Marwan's keyboard, transcript only carries non-secret outputs (UUIDs, yes/no, status).
  - Rotated **both** dev and prod service-role keys in the Supabase Dashboard (Settings → API → Generate new secret key). Stored the fresh values in Bitwarden items `Aman Supabase Dev service_role` and `Aman Supabase Prod service_role`.
  - Rewrote `.env.admin`: LF-normalized, uses `export BW_CLI="/c/Users/marwan.haahmed/AppData/Local/Microsoft/WinGet/Packages/Bitwarden.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe/bw.exe"` and `export SUPABASE_SERVICE_ROLE_KEY="$("$BW_CLI" get password 'Aman Supabase Prod service_role')"`. Kept a commented DEV block so target-swap is a two-line toggle. Active target is now prod.
- **First real pilot rep provisioned via prod** — `scripts/provision_rep.sh --phone +201128835459 --name "marwan hamed" --employee-id 121264 --role sales_rep`. Returned auth user UUID `036b62f1-4413-4ec1-949f-d1da3f29f9cd`. Verified via MCP SQL: `auth.users.phone_confirmed_at` set (Admin-API pre-confirm path worked), `public.users` has role + `must_change_password=true`, `set_claim('role','sales_rep')` returned void (success).
- **Prod smoke test end-to-end (evidence captured via MCP SQL against `yflwudkmhqwoscipscbb`)**:
  - Login blocker surfaced: app returned `"Phone logins are disabled"` on first attempt. The Auth → Providers → Phone toggle was actually OFF on prod at session start (the 2026-04-16 "confirmed by Marwan" note in Current Decisions references a different settings page than the one gating phone-as-username login). Marwan toggled it ON + saved. Login went through on the next tap with no re-type needed.
  - Change-password screen fired correctly: `auth.users.last_sign_in_at` at 23:25:24 (first sign-in with temp), `updated_at` at 23:26:04 (~40s later — password rotation via `updateUser()`), `public.users.must_change_password` flipped to `false` at the same tx.
  - Home dashboard rendered RTL-native with "أهلا marwan!" welcome + Cairo region + "0 merchants this week" card.
  - Lead submission: merchant row `79dfa87f-2dfc-4985-b445-fb483b8b25c3` with phone E.164-normalized to `+201128835458` (trigger fired), NID hashed to `3eaa47ad3d2fbb421cad9a6bafdd588edc9cdb3062ace2de5c422ad74e0c4286`, `products = ["Microfinance","BP POS","Acceptance POS"]`, `microfinance_amount = 100000`, `created_by` = rep UUID, `status = lead`.
  - Audit capture: `audit_log` row `1974a66d-8392-47c3-bdd6-77322f22d087`, `action = INSERT`, `table_name = merchants`, `actor_id` = rep UUID, `record_id` matches the merchant row, same timestamp as the merchant insert (confirms the AFTER trigger is inside the same tx — P0-14 wired correctly).
- **Dashboard UI "bug" turned out to be a filter** (non-issue): the Authentication → Users search was set to "Email address", which correctly excludes phone-only users. Not a Dashboard defect. P2-9 closed as NOT-A-BUG.
**Decisions:**
- **Per-user instruction, NOT correcting the 2026-04-16 "auth settings confirmed (phone ON)" note** even though phone provider was actually OFF this session. Session log carries the factual event; Current Decisions / P0-1 confirmation stay as-is.
- **Service-role key resolution pattern locked in** — `$BW_CLI` hardcoded path + `bw get password` at source-time. Avoids PATH propagation issues and keeps the pattern usable from PowerShell, Git Bash, and any future WSL shell. Documented inline in `.env.admin` header.
- **Both keys rotated at migration time**, not just prod — the dev key sat in plaintext for days, and the prod one would have followed suit the moment it touched `.env.admin`. Cheaper to roll both now than to reason about exposure windows later.
- **`bw login` output treated as secret** going forward — the "example" block it prints embeds the real session token.
**Backlog impact:**
- **P0-1 note extended**: "First real pilot rep provisioned + full prod smoke test green 2026-04-17 (evening)".
- **P2-7 → IN_PROGRESS**: service-role key half closed; keystore password half still TODO.
- **P2-8 added**: APK size trim — 52 MB currently, over WhatsApp's 50 MB attachment cap. Options: R8 `shrinkResources`, `--split-per-abi`, or drop unused locales/icon densities.
- **P2-9 added and immediately closed** as NOT-A-BUG: Auth → Users "empty" state was an email-filter artifact, not a Dashboard defect. No runbook change needed.
- **Current Decisions — "Provisioning model — Option C1"** rewritten to reflect Bitwarden resolution pattern.
**Blockers now:** 0 active.
**Files changed:**
- `.env.admin` (plaintext JWT removed, `$BW_CLI` + `bw get password` wired in, prod target active, dev target commented).
- `CLAUDE.md` (Current Decisions "Provisioning model" update, P0-1 note extended, P2-7 → IN_PROGRESS + half-done note, P2-8 + P2-9 added, this entry, rotation).
- `CLAUDE.archive.md` (rotated 2026-04-16 "night" keystore entry).
- [build/pilot-apk/aman-v1.0.0-pilot.apk](build/pilot-apk/aman-v1.0.0-pilot.apk) (new, gitignored — downloaded artifact).
**Next Session:**
1. **Regression automation** — stand up Patrol against the pilot APK. Golden-path test script (phone → password → change-password → new lead per product variant → merchant list → profile → NID reveal → `audit_log` assert via Supabase client). Wire into `.github/workflows/` as a gate before the signed-APK step; Linux runner + headless emulator is fiddly, recommend a macOS runner.
2. **Pentest automation** — highest risk-reduction-per-hour is RLS fuzzing + MobSF in CI. Script PostgREST calls with varied JWTs to prove RLS rejects cross-rep reads. Add MobSF docker step to `build-pilot-apk.yml` after the existing `apktool d` + `grep` secret scan; hard-fail on High/Critical.
3. **Two CodeRabbit follow-ups from 2026-04-17 afternoon session still unopened** — Security Definer hardening (`SET search_path` + internal `set_claim` access control) and RTL fix in `forgot_password_screen.dart:19`. File before pilot traffic accumulates.

### Session: 2026-04-17 (afternoon) — Wave 3 live: signed pilot APK via GitHub Actions; keystore regenerated after lost password
**Duration:** ~3h (spread across iterations)
**Focus:** Get a signed, distributable pilot APK end-to-end. Pivot from local Windows build to GitHub Actions CI after hitting a corp-laptop environmental blocker, survive the CodeRabbit pre-merge review gauntlet, recover from a forgotten keystore password mid-flight, land a green build.
**Completed:**
- **Local release build attempts failed** with `java.io.IOException: Unable to establish loopback connection`. Root cause: corp-managed Windows hosts file (`C:\Windows\System32\drivers\etc\hosts`) has been stripped of default `127.0.0.1 localhost` / `::1 localhost` entries — only internal `aman.local` AD hosts remain. Gradle worker daemon can't bind `InetAddress.getByName("localhost")`, fails fast. No admin rights to fix hosts.
- **Pivoted to GitHub Actions CI**: new workflow `.github/workflows/build-pilot-apk.yml` (manual `workflow_dispatch`, Ubuntu runner, decodes `KEYSTORE_BASE64` secret → writes `key.properties` via `printf` block → `flutter analyze` gate → `flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` → `apksigner verify --print-certs` → `apktool d` + `grep -rlE service_role` hard gate → signed APK uploaded as 30-day artifact).
- **CodeRabbit review — 8 iterations on the PR** ([#1 `ci/github-actions-pilot-build` → squash-merged `56800fa`](https://github.com/marwanhamedahmedmaher-sudo/Jawaker/pull/1)): added `permissions: contents: read` (least-privilege), replaced heredoc with `printf` block for `key.properties` (CodeRabbit's heredoc-corruption diagnosis was wrong — YAML strips common indent before bash sees the script — but refactored anyway for unambiguous readability), quoted `--dart-define` secret expansions, replaced JWT-match line-print with a count (avoid echoing JWT-shaped strings into CI logs), sanitized `inputs.version_name` against path traversal, added empty-guard for `apksigner` path, added `:?` fail-fast guards on `SUPABASE_URL` / `SUPABASE_ANON_KEY`, **and critically swapped the secret-scan `grep -rniE` (which prints matching lines before failing the step) to `grep -rlE` (filenames only) so a genuine leak does not end up verbatim in the log**. Two repo-wide pre-merge gates (Security Definer Hardening, RTL-Safe UI) flagged false positives on pre-existing code unrelated to this PR — ignored.
- **Also opened & merged [PR #2 `fix/flutter-version-pin`](https://github.com/marwanhamedahmedmaher-sudo/Jawaker/pull/2)**: first CI run failed at `flutter pub get` because `flutter-version: 3.24.x` ships Dart 3.5.4 while `pubspec.yaml` requires Dart `^3.11.4`. Pinned exact to `3.41.6` (matches local dev Flutter) for byte-reproducibility.
- **Second CI run failed on keystore signing** — `keystore password was incorrect`. Root cause: Marwan forgot the memorized keystore password between generation (2026-04-16 night) and first CI sign attempt.
- **Keystore regenerated** — deleted old `C:\Users\marwan.haahmed\aman-release.jks` + any backups. Generated fresh one via Android Studio's bundled `keytool.exe` (RSA 4096, 10000 days, alias `aman`, same DN). Used a 20-char cryptographically-random alphanumeric password (`tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20`), passed to keytool via `-storepass:env KSPASS` to keep it out of command-line args. Password saved to plaintext `C:\Users\marwan.haahmed\aman-keystore-password.txt` for reliable backup alongside the `.jks`.
- **Third CI run green** ✅ — signed `aman-v1.0.0-pilot.apk` produced as GitHub Actions artifact. Pilot distribution pipeline is live.
**Decisions:**
- **Release APK builds via GitHub Actions only** (documented in Current Decisions) — local Windows builds kept for debug APK + `flutter analyze` but cannot produce signed releases.
- **Never rely on memorized keystore passwords for the pilot again** — password file co-located with keystore, backed up in same encrypted 7z. P2-7 (password manager migration) upgrade trigger treated as effectively met. Added to Current Decisions.
- **Ignore Node 20 deprecation warnings on the workflow** — GitHub's June 2026 forced-switch is ~6 weeks out; revisit mid-May when `actions/checkout@v5` etc. stabilize. Chasing warnings now risks breaking a working pipeline for no pilot benefit.
- **Ignore CodeRabbit repo-wide false-positive gates on infra PRs** — the Security Definer Hardening + RTL-Safe UI pre-merge gates scan the whole repo, not the PR diff, so they flag pre-existing code on every infra/CI/docs PR. Two follow-up issues drafted (not yet filed) to address the real underlying concerns: (a) in-CREATE `SET search_path` + `set_claim()` internal role check, (b) `AlignmentDirectional.centerStart` fix in `lib/screens/auth/forgot_password_screen.dart:19`.
**Backlog impact:**
- P0-1 note updated: "First signed pilot APK built via GitHub Actions 2026-04-17".
- P2-7 note rewritten: upgrade trigger now effectively met due to forgot-password incident; treat as overdue rather than "before production rollout".
- No status transitions (no DONE rows). Two new **Current Decisions** added (CI builds, keystore password storage). No new backlog rows — the CI workflow is infrastructure for the existing P0-1 / Wave-3 goal, not a standalone feature.
**Blockers now:** 0 active.
**Files changed:**
- `.github/workflows/build-pilot-apk.yml` (new — via [PR #1](https://github.com/marwanhamedahmedmaher-sudo/Jawaker/pull/1) and [PR #2](https://github.com/marwanhamedahmedmaher-sudo/Jawaker/pull/2))
- `android/gradle.properties` (IPv4 JVM flag added then reverted within the same PR — didn't fix the hosts-file issue, kept PR single-purpose)
- `C:\Users\marwan.haahmed\aman-release.jks` (regenerated, not tracked)
- `C:\Users\marwan.haahmed\aman-keystore-password.txt` (new, not tracked — Marwan's encrypted laptop)
- `CLAUDE.md` (Current Decisions × 2, P0-1 + P2-7 notes, this entry, rotation)
- `CLAUDE.archive.md` (rotated 2026-04-16 evening entry)
**Pending user action:**
1. **Create the new encrypted 7z** containing both `aman-release.jks` and `aman-keystore-password.txt`, copy to cloud drive + USB. The 2026-04-16 night backup plan referenced the old (lost-password) keystore and is now stale.
2. **Smoke-test the APK** on Marwan's own Android phone — install via WhatsApp/email sideload, provision a test rep account via Supabase Dashboard, run the golden path (phone → password → forced change-password → new lead with products → merchant list → profile → NID reveal), verify `merchants` row + `audit_log` rows.
3. **Draft + file the two CodeRabbit follow-up issues** (Security Definer hardening + `set_claim` access control; RTL fix in `forgot_password_screen.dart:19`) — drafts already written in conversation.
**Next Session:**
1. After smoke test passes: provision the real pilot rep accounts via `scripts/provision_rep.sh` (or Dashboard Auth UI) per [docs/P0-DASHBOARD-RUNBOOK.md](docs/P0-DASHBOARD-RUNBOOK.md). One phone number + temp password per rep, `must_change_password=true`.
2. WhatsApp the `aman-v1.0.0-pilot.apk` + install instructions to each rep; send temp credentials in a separate message (+email backup per dual-channel decision).
3. Monitor Supabase Dashboard for first real rep submissions; verify `audit_log` captures `merchant_created` + `national_id_revealed` events as expected.
4. File the two CodeRabbit follow-up issues before pilot traffic accumulates.

### Session: 2026-04-17 (morning) — GitHub repo push: `Jawaker` origin set up
**Duration:** ~10m
**Focus:** Create git remote + initial push of full pilot baseline to GitHub (new repo `https://github.com/marwanhamedahmedmaher-sudo/Jawaker`). Harden gitignore for editor/tooling config that had been tracked incorrectly.
**Completed:**
- **Pre-push secrets scan**: no tracked `.env*` / `.jks` / `key.properties` / `service_role` files. Found Supabase **dev + prod anon keys** embedded in `.claude/launch.json` + `.claude/settings.local.json` (4 Bash allowlist entries). Low severity — anon keys are public by design (RLS-protected) — but editor state shouldn't be in version control regardless.
- **Gitignore hardened**: added `.claude/` and `.obsidian/` to root `.gitignore`. Removed `.claude/settings.local.json` from the index via `git rm --cached` (working copy preserved). `.obsidian/` was never tracked — ignore-only.
- **Branch rename** `master` → `main` (GitHub default; matches repo convention referenced in earlier session logs).
- **Pilot baseline commit** (`ac7b720`): 51 files, +5006/-463. Rolls up every uncommitted change since `ae9fc1a` — P0-21, P1-6/9/10/11/12, tasks module migrations 013-016, prod Supabase artifacts, Android signing config, provisioning scripts, pilot checklist + Day 1 execution plan.
- **Force push to `origin/main`**: remote had only an auto-generated `# Jawaker\nJawaker app` README stub (commit `a19b097`). Discarded via `--force`. Local `main` now tracks `origin/main`.
**Decisions:**
- **`.claude/` and `.obsidian/` ignored wholesale** — even though anon keys are RLS-protected, editor/tooling config is user-specific and shouldn't live in a shared repo. If project-wide Claude config is ever needed (e.g. `.claude/commands/`), add it as an explicitly un-ignored subpath rather than loosening the directory-level rule.
- **Force push over `--allow-unrelated-histories` merge** — remote had nothing meaningful, so force push kept history linear. Would not be acceptable on a repo with collaborators; flagging here so future sessions don't copy the pattern blindly.
**Backlog impact:** No new/closed rows. Activates the dormant CodeRabbit config (P1-12) since the GitHub App can now be installed on the live repo.
**Blockers now:** 0 active.
**Files changed:**
- `.gitignore` (added `.claude/`, `.obsidian/`)
- `.claude/settings.local.json` (removed from tracking)
- `CLAUDE.md` (GitHub repo reference in Current Decisions, this entry, rotation)
- `CLAUDE.archive.md` (rotated 2026-04-16 morning entry)
**Next Session:**
1. Install CodeRabbit GitHub App at https://github.com/apps/coderabbitai → authorize on `Jawaker` repo. Open a throwaway PR to confirm it reads `.github/REVIEW_CONTEXT.md` + `CLAUDE.md`.
2. **Marwan manual** (before Wave 3): back up `.jks` to cloud + USB.
3. **Wave 3 — release APK build**: `flutter build apk --release --dart-define=SUPABASE_URL=https://yflwudkmhqwoscipscbb.supabase.co --dart-define=SUPABASE_ANON_KEY=<prod-anon-key>`. Verify with `apksigner verify --print-certs`. Rename to `aman-v1.0.0-pilot.apk`. Confirm size < 50MB for WhatsApp.
4. **Agent J — decompile + secret-scan**: `apktool d aman-v1.0.0-pilot.apk -o decompiled/` then `grep -ri "service_role\|supabase_service\|password" decompiled/`. Only `SUPABASE_ANON_KEY` permitted; any `service_role` hit is pilot-blocking.

*(Older entries archived to `CLAUDE.archive.md`.)*