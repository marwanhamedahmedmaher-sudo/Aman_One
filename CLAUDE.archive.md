# Aman Sales App — Session Log Archive

Session log entries rotated out of `CLAUDE.md`. Newest first within this file.

---

### Session: 2026-04-16 (late-late night) — Wave 2 Agent F: `flutter analyze` clean
**Duration:** ~5m
**Focus:** Run `flutter analyze` to confirm zero static-analysis issues before Wave 3 release APK build.
**Completed:**
- `flutter analyze` → **No issues found!** (ran in 46.9s). 18 packages have newer versions but all locked behind dependency constraints — not pilot-relevant.
- Wave 2 Agent F → done. Wave 2 fully complete (G keystore + F analyze + H Dashboard auth all green).
**Decisions:** None — confirmation step only.
**Backlog impact:** No backlog row — Day 1 Wave plan only. Pilot APK build (Wave 3) is now unblocked.
**Blockers now:** 0 active.
**Files changed:**
- `CLAUDE.md` (this entry, rotation)
- `CLAUDE.archive.md` (rotated entry)
**Next Session:**
1. **Wave 3 — release APK build**: `flutter build apk --release --dart-define=SUPABASE_URL=https://yflwudkmhqwoscipscbb.supabase.co --dart-define=SUPABASE_ANON_KEY=<prod-anon-key>`. Verify with `apksigner verify --print-certs`. Rename to `aman-v1.0.0-pilot.apk`. Confirm size < 50MB for WhatsApp.
2. **Agent J — decompile + secret-scan**: `apktool d` then grep for `service_role` / `supabase_service` / `password`. Only `SUPABASE_ANON_KEY` permitted; any `service_role` hit is pilot-blocking.
3. **Marwan manual** (before Wave 3): back up `.jks` to cloud + USB.
4. Install CodeRabbit GitHub App on the repo.

---

### Session: 2026-04-16 (late night) — Day 1 wrap: Dashboard auth confirmed, keystore backup plan locked, P2-7 logged
**Duration:** ~20m
**Focus:** Close out Day 1 pilot prep — confirm Dashboard auth settings done, agree keystore backup pattern, reconcile all three pilot docs (CLAUDE.md / PILOT-DEPLOYMENT-CHECKLIST.md / PILOT-READINESS-TODOS.md), log post-pilot password-manager upgrade as P2-7.
**Completed:**
- **Dashboard auth settings confirmed by Marwan**: phone provider ON, SMS provider UNCONFIGURED, "Allow new users to sign up" OFF, 2FA enabled on admin. P0-1 note updated to reflect confirmation. This was flagged as the single biggest pilot-breaking risk — now closed.
- **Keystore backup pattern agreed**: encrypted 7z archive + cloud drive + USB backup, keystore password memorized. **Bitwarden / 1Password upgrade deferred to post-pilot** (logged as P2-7). Pragmatic pilot-grade decision — matches existing "Pilot-grade keystore passwords acceptable for POC" stance.
- **P2-7 backlog row added** to CLAUDE.md: post-pilot password-manager upgrade covering both (a) keystore file + passwords and (b) service-role key migration from `.env.admin` plaintext. Hard triggers documented: prod rollout beyond pilot cohort OR second admin joining.
- **PILOT-DEPLOYMENT-CHECKLIST.md reconciled**: §1A auth settings items all ticked `[x]` with "DONE 2026-04-16, confirmed by Marwan" stamp. §1B keystore items updated — Generate keystore `[x]`, Store in password manager `[~]` with interim note ("encrypted 7z + cloud + USB backup, password memorized — upgrade deferred to P2-7"), Create `key.properties` `[x]`, update `build.gradle.kts` `[x]`, add `.gitignore` entries `[x]`. Service-role key storage item flagged as deferred to P2-7.
- **PILOT-READINESS-TODOS.md Day 1 reconciled**: items 1 (Dashboard auth), 2 (keystore), 3 (key.properties) all marked DONE 2026-04-16 inline.
**Decisions:**
- **Accept 7z + cloud + USB backup for pilot** instead of password manager — ~30 min saved today, risk bounded to pilot window, upgrade path documented in P2-7. Losing the `.jks` kills future pilot APK updates (cryptographic signature must match across versions), so the cloud + USB redundancy is the mitigation.
- **No new features / scope creep tonight** — reconciliation and doc hygiene only, consistent with PILOT-READINESS-TODOS.md "decision discipline during pilot week" rule #1.
**Backlog impact:** P0-1 note updated (auth settings confirmed). P2-7 added. No DONE transitions beyond those already logged in prior sessions.
**Blockers now:** 0 active.
**Files changed:**
- `CLAUDE.md` (P0-1 auth-settings confirmation note, P2-7 added, this session entry)
- `docs/PILOT-DEPLOYMENT-CHECKLIST.md` (§1A + §1B ticks, P2-7 cross-references)
- `docs/PILOT-READINESS-TODOS.md` (Day 1 items 1-3 marked DONE)
- `CLAUDE.archive.md` (rotated entry)
**Next Session:**
1. **Wave 2 remainder**: run `flutter analyze` (Agent F), confirm clean before APK build.
2. **Wave 3**: build release APK — `flutter build apk --release --dart-define=SUPABASE_URL=https://yflwudkmhqwoscipscbb.supabase.co --dart-define=SUPABASE_ANON_KEY=<prod-anon-key>`. Verify signing with `apksigner verify --print-certs`. Rename to `aman-v1.0.0-pilot.apk`. Check size < 50MB for WhatsApp.
3. **Agent J — decompile + secret-scan**: `apktool d aman-v1.0.0-pilot.apk -o decompiled/` then `grep -ri "service_role\|supabase_service\|password" decompiled/`. Only `SUPABASE_ANON_KEY` permitted. Any `service_role` hit is pilot-blocking.
4. **Install CodeRabbit GitHub App** on the repo (2 min at https://github.com/apps/coderabbitai). Open a throwaway PR to confirm it reads `.github/REVIEW_CONTEXT.md` + CLAUDE.md.
5. Marwan manual: back up `.jks` to cloud + USB before Wave 3.

---

### Session: 2026-04-16 (night) — Wave 2 part 1: release keystore generated + wired
**Duration:** ~15m
**Focus:** Agent G — generate the Android release keystore and wire it into the Gradle build so Wave 3 (release APK build) can sign end-to-end.
**Completed:**
- **Keystore generated**: `C:\Users\marwan.haahmed\aman-release.jks` via Android Studio's bundled `keytool.exe` (`C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`). RSA 4096, validity 10000 days, alias `aman`, DN `CN=Aman Sales, OU=Pilot, O=Aman, L=Cairo, ST=Cairo, C=EG`. File size 4372 bytes (normal for RSA 4096).
- **`android/key.properties` created** and wired to keystore path (`C:/Users/marwan.haahmed/aman-release.jks`, forward slashes for Gradle on Windows) + alias `aman`. Passwords filled in manually by Marwan (kept out of Claude context). Gitignore verified: `android/.gitignore:12` catches `key.properties`; root `.gitignore` catches `*.jks`.
- **`build.gradle.kts` already wired from Wave 1** — `keystoreProperties` loader + `signingConfigs.release` + conditional `buildTypes.release` signing (falls back to debug if `key.properties` missing). No change needed.
- **Keytool path discovery**: `keytool` not on system PATH; located Android Studio's JBR copy and invoked via `& "..."` PowerShell call operator.
**Decisions:**
- **Keystore location outside the repo tree** (`$HOME\aman-release.jks`) — absolute path in `key.properties.storeFile` so the .jks never has to sit inside the project folder. Reduces accidental-commit risk.
- **Same password for keystore and key** (pressed Enter on third prompt) — acceptable for pilot-grade POC, matches existing "Pilot-grade keystore passwords acceptable for POC" decision.
**Backlog impact:** No backlog item directly tracks keystore (it lives under Day 1 Wave plan). Wave 2 Agent G → done.
**Blockers now:** 0 active.
**Pending user action (before Wave 3):**
1. **Back up the .jks in 3 places** — password manager (attach file + store password in same entry), encrypted cloud drive, optional encrypted USB. Losing the keystore kills all future pilot APK updates.
2. Confirm `android/key.properties` has the real password substituted for both `REPLACE_WITH_YOUR_KEYSTORE_PASSWORD` placeholders.
**Files changed:**
- `android/key.properties` (new, gitignored — contains passwords)
- `CLAUDE.md` (session entry, rotation)
- `CLAUDE.archive.md` (rotated entry)
**Next Session:**
1. Wave 2 remainder: Agent F (`flutter analyze`), Agent H (manual: verify prod Dashboard auth settings).
2. Wave 3: build release APK with `flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` (prod credentials), confirm signed with release key via `apksigner verify --print-certs`, decompile + security scan (Agent J).

---

### Session: 2026-04-16 (evening) — Day 1 pilot prep: Wave 1 completed, prod Supabase live
**Duration:** ~30m
**Focus:** Execute Day 1 Wave 1 of parallel pilot deployment plan. Android manifest fix, Gradle signing config, .gitignore hardening, prod Supabase project creation + 15 migrations.
**Completed:**
- **Agent A — AndroidManifest.xml**: Added `INTERNET` + `USE_BIOMETRIC` permissions to main manifest (were only in debug/profile). Changed `android:label` from "aman_sales_app" to "أمان".
- **Agent B — build.gradle.kts**: Added `keystoreProperties` loader, `signingConfigs.release` block, conditional release signing (falls back to debug if no keystore). **Pinned `minSdk = 23`** (required for `local_auth` biometric). Agent output was truncated mid-file — rebuilt manually.
- **Agent C — .gitignore + keystore template**: Created `android/key.properties.example` with template values. Added `*.keystore`, `*.jks`, `android/key.properties` to `.gitignore`. Agent missed the .gitignore edit — fixed manually.
- **Agent D — Dart code audit**: Agent ran but did not persist report. Re-run recommended in Wave 2.
- **Agent E — Prod Supabase setup**: Created prod project `yflwudkmhqwoscipscbb` (eu-west-1, Postgres 17, $0/month free tier). Applied all 15 migrations (001→015) via MCP `execute_sql`. Verified: RLS on 6 tables, 10 activity types seeded, 5 RPCs confirmed (`set_claim`, `is_admin`, `reveal_national_id`, `distribute_daily_tasks`, `refill_rep_tasks`). Security advisors: 0 lints. Prod anon key and URL recorded.
- **Pilot deployment docs created**: `docs/PILOT-DEPLOYMENT-CHECKLIST.md` (full 4-day checklist) + `docs/DAY1-EXECUTION-PLAN.md` (3-wave parallel agent architecture with copy-paste prompts).
**Decisions:**
- **Distribution: direct APK sideload** via WhatsApp/Google Drive. No Play Store, no Firebase App Distribution.
- **Timeline: 3-4 days** (April 16-19). Aggressive — skip nice-to-haves, focus on prod + build + security + provisioning.
- **Pilot-grade keystore passwords** acceptable for POC. Must upgrade before any production release.
**Backlog impact:** P0-1 updated (prod project live). No new P1/P2 items.
**Blockers now:** 0 active.
**Files changed:**
- `android/app/src/main/AndroidManifest.xml` (permissions + label)
- `android/app/build.gradle.kts` (signing config + minSdk)
- `.gitignore` (keystore entries)
- `android/key.properties.example` (new)
- `docs/PILOT-DEPLOYMENT-CHECKLIST.md` (new)
- `docs/DAY1-EXECUTION-PLAN.md` (new)
- `CLAUDE.md` (prod project, P0-1 update, session entry)
- `CLAUDE.archive.md` (rotated entry)
**Next Session:**
1. **Wave 2**: Flutter analyze (F), generate keystore (G), verify prod Supabase auth settings (H — manual by Marwan in Dashboard).
2. **Wave 3**: Build release APK with `--dart-define` for prod credentials (I), decompile + security scan (J).
3. Marwan manual: Dashboard auth settings (phone ON, SMS OFF, signup OFF, 2FA).

---

### Session: 2026-04-16 (morning) — P1-12: pre-pilot code review agent wired up
**Duration:** ~20m
**Focus:** Research AI PR review tools, pick one, and ship a review-context doc + config so any PR going into the pilot cut is reviewed against fintech/PDPL standards before merge.
**Completed:**
- **Research + recommendation.** Compared CodeRabbit, Greptile, GitHub Copilot, Cursor reviewer. Picked **CodeRabbit** — PR-native, assertive profile, best precision-to-noise ratio, $24/dev/mo, honors external markdown guidelines via `knowledge_base.code_guidelines.filePatterns`. Greptile has higher raw catch rate (82%) but much higher noise and $30/dev/mo — not worth it on a 1-dev POC. Copilot code review is thinnest. Documented trade-off in delivery.
- **`.github/REVIEW_CONTEXT.md`** (new, ~9KB): the review ruleset. Covers project brief, explicit "do NOT flag" scope decisions (no OTP, no KYC images, no English UI, etc.), review priorities, and detailed must-flag rules for: NID handling + `reveal_national_id` RPC discipline, auth/session flow, RLS + SECURITY DEFINER + `search_path` pinning, secrets hygiene, migration hygiene, trigger NULL-`auth.uid()` handling, SELECT-* on merchants, RTL correctness, async/`context.mounted`, Arabic error mapping. Includes a good/bad review-comment example, file-level quick reference, and a 10-item pre-pilot reviewer checklist.
- **`.coderabbit.yaml`** (new): assertive profile, auto-review on main+develop, 5 path-scoped `path_instructions` (migrations, providers, screens, scripts, .env*), 5 `pre_merge_checks` as hard gates (RLS enabled on new tables, SECURITY DEFINER hardening, no plaintext NID leak, secrets hygiene, RTL-safe UI as warning). `path_filters` exclude generated + native platform dirs. `knowledge_base.code_guidelines.filePatterns` points at REVIEW_CONTEXT.md + ARCHITECTURE.md + PILOT-DEPLOYMENT-CHECKLIST.md; CodeRabbit also auto-discovers CLAUDE.md.
- **YAML validated** (`python3 -c "yaml.safe_load(...)"` — OK). Fixed a duplicate `reviews:` key on first draft.
**Decisions:**
- **CodeRabbit over Greptile** — precision over raw catch rate on a 1-dev POC, half the monthly cost, zero-config GitHub install.
- **Assertive profile, not chill** — fintech defaults to over-report. Turn down post-pilot if noise becomes a problem.
- **5 hard pre-merge gates, 1 warning** — anything that could leak plaintext NID or break RLS is `error`. RTL is `warning` (catches regressions without blocking non-UI PRs).
**Backlog impact:** P1-12 → DONE 2026-04-16.
**Blockers now:** 0 active. **Activation dependency:** CodeRabbit GitHub App must be installed on the repo for the config to take effect — takes ~2 minutes at https://github.com/apps/coderabbitai.
**Files changed:**
- `.github/REVIEW_CONTEXT.md` (new)
- `.coderabbit.yaml` (new)
- `CLAUDE.md` (P1-12, session entry, rotation)
- `CLAUDE.archive.md` (rotated entry)
**Next Session:**
1. Install CodeRabbit GitHub App on the repo, open a throwaway test PR, confirm it reads REVIEW_CONTEXT.md and posts comments.
2. Tune noise after the first 2-3 real PRs — downgrade any over-triggered gate to `warning`.
3. Consider a follow-on `docs/CODE-REVIEW-ONBOARDING.md` for a second maintainer (when/if one joins).
4. P1-1/2/3 remain open but deprioritized for pilot.

---

### Session: 2026-04-15 (afternoon) — P1-9 implemented: merchant list + profile + reveal RPC
**Duration:** ~25m
**Focus:** Full implementation of P1-9 — merchant list screen, merchant profile screen with masked NID + reveal-with-audit, Supabase RPC, home screen wiring. Also closed P1-6 and P1-8.
**Completed:**
- **Migration 010** (`reveal_national_id`): SECURITY DEFINER RPC. Takes `p_merchant_id`, validates caller owns merchant (or is admin), returns plaintext NID, writes `national_id_revealed` audit row in same transaction. `search_path = public` pinned. GRANT to `authenticated` only. Applied to dev project `yynhcrtdzgcgedkolgxw` — confirmed via `pg_proc` query.
- **MerchantListProvider** (`lib/providers/merchant_list_provider.dart`): `fetchMerchants()` — SELECT excludes `national_id` (plaintext NID only via RPC, per decision). `fetchWeeklyCount()` for home dashboard. `revealNationalId(merchantId)` calls RPC.
- **MerchantListScreen** (`lib/screens/merchant/merchant_list_screen.dart`): ListView with masked phone, Arabic status badges (عميل محتمل / مؤهل / مرفوض / تم التحويل), pull-to-refresh, empty state, tap → profile. RLS-enforced (rep sees own merchants only).
- **MerchantProfileScreen** (`lib/screens/merchant/merchant_profile_screen.dart`): Info cards (name, phone, masked NID `*************`, products, notes, date). "عرض" (Reveal) button → calls RPC → plaintext NID displayed for rest of screen visit. Navigating away re-masks. Loading spinner during RPC call.
- **Home screen wired**: Stats card now shows dynamic `weeklyCount` from `MerchantListProvider` (replaces hardcoded `7`). Card is tappable → navigates to `MerchantListScreen`. Chevron icon added for affordance.
- **`main.dart`**: Upgraded from single `ChangeNotifierProvider` to `MultiProvider` with `AuthProvider` + `MerchantListProvider`.
- **P1-8 confirmed DONE**: `main.dart` already had full RTL setup (locale, delegates, Directionality wrapper). New screens built RTL-native.
- **`flutter analyze` — 0 issues.** Fixed 3 lint warnings (use_build_context_synchronously, unnecessary_underscores).
- **Security advisors clean** — only pre-existing "Leaked Password Protection Disabled" (auth-level, unrelated).
- App launched in Chrome — `Supabase init completed`, no errors.
**Decisions:** None new — implemented per existing decisions (reveal policy, SECURITY DEFINER RPC, NID excluded from normal SELECT).
**Backlog impact:** P1-6 → DONE 2026-04-15, P1-8 → DONE 2026-04-15, P1-9 → DONE 2026-04-15. P1 remaining: P1-1 (NID client validation), P1-2 (soft delete), P1-3 (xlsx export) — all deprioritized for pilot.
**Blockers now:** 0 active.
**Files changed:**
- `supabase/migrations/010_reveal_national_id_rpc.sql` (new)
- `lib/providers/merchant_list_provider.dart` (new)
- `lib/screens/merchant/merchant_list_screen.dart` (new)
- `lib/screens/merchant/merchant_profile_screen.dart` (new)
- `lib/screens/main/home_screen.dart` (dynamic count + tap navigation)
- `lib/main.dart` (MultiProvider + MerchantListProvider import)
**Next Session:**
1. Smoke test merchant list + profile in Chrome (login → home → tap stats card → list → tap merchant → profile → reveal NID).
2. Verify `audit_log` row written on NID reveal via `execute_sql`.
3. Consider `flutter build web --release` for pilot deployment artifact.
*(Rotated from CLAUDE.md on 2026-04-16)*

---

### Session: 2026-04-15 (evening) — E2E smoke test passed, P0 closed
**Duration:** ~20m
**Focus:** End-to-end Chrome smoke test — P0 closed.
*(Rotated from CLAUDE.md on 2026-04-16)*

---

### Session: 2026-04-15 (late morning) — Pilot-readiness re-plan: RTL + merchant profile elevated
**Duration:** ~15m
**Focus:** Morning sync → reprioritization. User pushed back on generic P1 polish and surfaced two real pilot-quality gaps: (1) most screens are not RTL despite Arabic-first user base, (2) reps have no way to view their own merchants — the home dashboard card "7 created this week" is not tappable to anything.
**Completed:**
- Morning sync delivered. Confirmed P0 fully closed; P1-1/2/3 deprioritized as speculative polish.
- Walked user through fintech implications: RTL = correctness for Arabic-first product, not cosmetic. Merchant profile = unblocks P1-6 (mask + reveal-with-audit), which is a PDPL-adjacent control — reps shouldn't see plaintext NID for merchants they don't need to re-view, and every reveal must audit.
- Scoped P1-9 with user: full list (not filtered by "this week"), rep's own only (admin view deferred), view-only V1, simple reveal policy.
- Locked **NID reveal policy**: one tap → plaintext for rest of screen visit; leaving re-masks; each tap writes one audit row via RPC. No timer, no re-prompt.
- Added two new Current Decisions (reveal policy, RTL-first UI, merchant list scope).
- Added **P1-8** (App-wide RTL enforcement) and **P1-9** (Merchant list + profile + reveal RPC) to backlog. Folded P1-6 into P1-9 execution.
**Decisions:**
- **P1-8 before P1-9** — RTL first so new screens are built RTL-native, not rebuilt.
- **Reveal via SECURITY DEFINER RPC** — not a plain SELECT. Ensures audit row is non-bypassable. Plaintext NID must not be reachable through generic row reads on the client.
- **Simple reveal UX** — session-scoped to the screen, no timer, no confirmation dialog.
**Backlog impact:** P1-8 + P1-9 added. P1-6 marked as "folded into P1-9". P1-1/2/3 remain open but explicitly deprioritized for pilot.
**Blockers now:** 0 active.
**Next Session:**
1. **Start P1-8 (RTL).** Add `flutter_localizations` to `pubspec.yaml` if not present. Set `MaterialApp.locale = Locale('ar', 'EG')` + `supportedLocales` + delegates. Audit every screen (`lib/screens/**`) for hardcoded left/right padding, alignment, icon direction, `Row` ordering. Smoke test in Chrome.
2. **Then P1-9.** Migration for `reveal_national_id(merchant_id)` RPC (SECURITY DEFINER, inserts audit row + returns plaintext). Wire up home dashboard card tap → `MerchantListScreen`. Build `MerchantProfileScreen` with masked NID + reveal button + products display. View-only — no edit controls in V1.
3. After both: close P1-6, update CLAUDE.md, build `flutter build web --release` for pilot.
*(Rotated from CLAUDE.md on 2026-04-16 during P1-12 session.)*

---

### Session: 2026-04-15 (night) — P1-11: merchant info fields (avg sales, address, activity type dropdown)
**Duration:** ~20m
**Focus:** Add 3 optional merchant information fields to lead form + activity types lookup table.
*(Rotated from CLAUDE.md on 2026-04-16)*

---

### Session: 2026-04-15 (late afternoon) — P1-10: product-specific fields + dashboard refresh fix
**Duration:** ~20m
**Focus:** Add conditional detail fields per product on lead form + fix home dashboard count not refreshing after lead submission.
**Completed:**
- **Migration 011** (`011_product_details_columns.sql`): Added `microfinance_amount numeric` and `acceptance_device_count integer` columns to `merchants`. 4 CHECK constraints: detail required when product selected (`>= 0`), must be NULL when product not selected. Backfilled existing rows with 0 values. Applied to dev project `yynhcrtdzgcgedkolgxw`.
- **Lead model** (`lib/models/merchant.dart`): Added `microfinanceAmount` (double?) and `acceptanceDeviceCount` (int?) fields. `copyWith()` uses `Function()?` pattern to allow explicit null-setting. `toJson()` and `fromJson()` wired.
- **LeadProvider** (`lib/providers/merchant_provider.dart`): `toggleProduct()` now clears detail when product deselected. New `updateProductDetails()` method. `validate()` returns Arabic errors for missing product details. `isValid` getter updated.
- **Lead form** (`lib/screens/lead/new_lead_screen.dart`): Conditional fields appear inline below each product checkbox. Fields clear when product unchecked. `_handleSubmit` syncs product details before validation.
- **Merchant profile** (`lib/screens/merchant/merchant_profile_screen.dart`): New `_productsCard()` widget with detail lines.
- **Merchant list provider**: SELECT query now includes `microfinance_amount, acceptance_device_count`.
- **Dashboard refresh fix** (`lib/screens/main/home_screen.dart`): `fetchWeeklyCount()` re-runs on nav return.
- **`flutter analyze` — 0 issues.**
**Decisions:** Product-specific data capture added to Current Decisions.
**Backlog impact:** P1-10 → DONE 2026-04-15.

---

### Session: 2026-04-15 (midday) — Stream B housekeeping: migration 007, Flutter pre-flight, test harness
**Duration:** ~15m
**Focus:** Independent housekeeping in parallel with Stream A (Cowork session). Three sub-tasks: B1 migration parity, B2 Flutter smoke, B3 test harness scaffolding.
**Completed:**
- **B1 — Migration 007:** Created `supabase/migrations/007_pin_function_search_paths.sql` matching the ad-hoc migration already applied to dev project. Pins `SET search_path` on all 8 public functions (6 get `public`, 2 NID functions get `public, extensions` for pgcrypto `digest()`). Verified via `list_migrations` — migration present on live DB. Ran security advisors — only lint remaining is "Leaked Password Protection Disabled" (auth-level setting, not function-related). All search-path warnings resolved.
- **B2 — Flutter pre-flight:** `flutter pub get` clean (18 packages have newer compatible versions, no breakage). `flutter analyze` — **0 issues**. `flutter run -d chrome` with `--dart-define` env vars from `.env` — compiled, launched Chrome, **`Supabase init completed`** logged, phone entry screen rendered. No console errors, no missing env vars, no Supabase init failures. App is ready for first login attempt once a rep is provisioned.
- **B3 — Test harness:** Created `scripts/test/` with 4 files: `d1_rls_tests.sql` (RLS matrix with template queries per role), `d2_dedup_race_test.sql` (duplicate NID insert test), `d3_trigger_fixtures.sql` (full DO-block running all phone + NID test helpers — verified passing against live DB via `execute_sql`), `run_sql.sh` (psql runner keyed to `SUPABASE_DB_URL`). Directory gitignored per user instruction.
- Rotated oldest session log entry ("Phase 1 scope match to Figma") to `CLAUDE.archive.md`.
**Decisions:** None new.
**Backlog impact:** None. B1/B2/B3 are housekeeping, not backlog items. P0-15 (test execution) is now better supported by the D3 harness.
**Blockers now:** 0 active.
**Files changed:**
- `supabase/migrations/007_pin_function_search_paths.sql` (new)
- `scripts/test/d1_rls_tests.sql` (new, gitignored)
- `scripts/test/d2_dedup_race_test.sql` (new, gitignored)
- `scripts/test/d3_trigger_fixtures.sql` (new, gitignored)
- `scripts/test/run_sql.sh` (new, gitignored)
- `.gitignore` (added `scripts/test/` entry)
- `CLAUDE.md` (this entry)
- `CLAUDE.archive.md` (rotated entry)

### Session: 2026-04-15 (morning) — Provisioning scripts written + runbook v1.1
**Duration:** ~30m
**Focus:** Execute Stream A of the morning plan: provisioning scripts, runbook update, CLAUDE.md sync. Locked open decisions from prior session.
**Completed:**
- Locked **service-role key storage** to password manager pattern (`op read` / `bw get`). `.env.admin` holds only the URL and the password-manager command, never the raw key. Recommendation accepted by user.
- User confirmed **public signup OFF** in Supabase Auth settings.
- Wrote `scripts/provision_rep.sh` — Admin API call with `phone_confirm: true`, generates 16-char alphanumeric temp password, inserts `public.users` row, calls `set_claim()` RPC, prints temp password once. Argument validation (E.164 phone, role enum), JWT sanity check on service-role key, masked-phone log to `scripts/provision.log`.
- Wrote `scripts/reset_password.sh` — same hardening; looks up user by phone, rotates password, forces `must_change_password = true`.
- Wrote `.env.admin.example` documenting `op` / `bw` runtime sourcing patterns.
- Updated `.gitignore` to explicitly cover `.env.admin` + `scripts/provision.log` (in addition to existing `.env` + `*.log`).
- Updated **P0-18 runbook to v1.1**: prepended a Hard Rules section (no SMS provider in V1, public signup OFF, 2FA, script-first), added Section 1A (script-based provisioning + reset), demoted manual UI provisioning to "fallback only".
- Bash syntax-checked both scripts (`bash -n`). No execution against live API yet — that happens in next session once user pulls service-role key into password manager.
**Decisions:**
- **Provisioning model — Option C1** promoted into Current Decisions.
- **Phone provider ON, SMS provider UNCONFIGURED** promoted as a permanent V1 hard rule (in Current Decisions + runbook).
- **Public signup OFF** promoted into Current Decisions.
- New backlog item **P0-20** added and marked DONE 2026-04-15 (script work itself).
**Backlog impact:** P0-20 added & DONE. P0-15 (test execution) remains the only open P0 — now properly unblocked end-to-end.
**Blockers now:** 0 active.

---

### Session: 2026-04-15 (early AM) — Auth provisioning model resolved (Option C locked)
**Duration:** ~25m
**Focus:** Resolve mismatch between Supabase Dashboard "Add User" UI (email-only) and our phone-first auth design. Decide provisioning approach.
**Completed:**
- Confirmed the Dashboard "Add User" dialog only exposes email+password; phone provisioning requires SMS provider configured, which contradicts our "no SMS in V1" rule.
- Walked through 3 options end-to-end:
  - **A. Synthetic email (`+20...@aman.internal`)** — quick (~15m) but pollutes `auth.users.email` with fake addresses, creates migration debt.
  - **B. Pivot to email login** — rejected; reps don't have work emails, breaks Figma flow.
  - **C. Supabase Admin API with `service_role` key + `phone_confirm: true`** — proper architecture, no SMS, ~45m to script.
- Locked **Option C (specifically C1 — local script on admin laptop)** for pilot. Graduates linearly to C2 (Edge Function) post-pilot.
- Verified Flutter side already calls `signInWithPassword(phone: ..., password: ...)` — no app changes needed.
- User enabled **Phone auth provider** in Supabase (toggle on, no SMS provider configured — exactly the right state). Email provider stays on. Public signup should be disabled per fintech hygiene.
**Decisions:**
- **Provisioning model:** Option C1 — local bash script invoking Admin API + SQL insert. Service-role key lives on admin laptop, gitignored. Graduates to Edge Function (C2) post-pilot.
- **Phone provider enabled, SMS not configured.** Add a runbook warning (P0-18) to NEVER configure an SMS provider during V1 — would introduce billable OTP flows the app isn't designed for.
- **Disable public signup** in Supabase Auth settings (admin-only provisioning).
- **Reject Option A** to avoid `auth.users.email` pollution and downstream migration pain.
**Open decision (carried into next session):** where to store the `service_role` key on admin laptop — plain `.env.admin` (faster) vs. password manager via `op`/`bw` CLI (safer). Pick before script is written.
**Backlog impact:** No status changes. Provisioning script work is part of P0-1 follow-through, not a separate item — will be tracked under P0-15 once script exists and tests run against it.
**Blockers now:** 0 active.

---

### Session: 2026-04-15 (afternoon) — End-to-end provisioning executed + products scope added
**Duration:** ~60m (cumulative across the afternoon)
**Focus:** Stream A execution (real provisioning + smoke test against live Supabase) and a new in-scope lead-form enhancement: product-interest capture.
**Completed:**
- **Provisioning executed live.** `./scripts/provision_rep.sh` created seed admin (`+20101****5678` / ADMIN001, role=admin, auth UUID `83097a6d…`) and first test rep (`+20109****9999` / REP001, role=sales_rep, auth UUID `4f9bf155…`) at 03:38–03:39 UTC. `scripts/provision.log` captures masked-phone audit trail.
- **Password reset path exercised.** `./scripts/reset_password.sh` ran 3 times (04:31 UTC x2, 09:40 UTC x1) — smoke-tests the forced change-password flow and confirms `must_change_password=true` is being written correctly.
- **Migration 008 — `products` column** added to `merchants`. `text[] NOT NULL DEFAULT '{}'`. CHECK constraint enforces `array_length >= 1` AND values ∈ {Microfinance, BP POS, Acceptance POS}. Backfill safely toggled audit trigger off/on to avoid FK violation on existing rows.
- **Migration 009 — `audit_merchants_change()` hardening.** Now early-returns when `auth.uid() IS NULL`. Fixes FK violation that surfaced when Dashboard/service-role ops hit `audit_log.actor_id`. Accepted V1 gap (Dashboard has its own audit trail) already documented in Current Decisions.
- **Flutter lead form — product checkboxes.** `lib/models/merchant.dart` (`Lead.products: List<String>`), `lib/providers/merchant_provider.dart` (`toggleProduct` + products in insert payload), `lib/screens/lead/new_lead_screen.dart` (3 CheckboxListTiles: Microfinance / BP POS / Acceptance POS). **Known gap:** no client-side guard for zero-products — DB CHECK rejects it but UX surfaces as raw Arabic DB error. Logged as P1-7.
**Decisions:**
- **Product interest is POC scope, not post-POC.** Three fixed products — Microfinance, BP POS, Acceptance POS — are captured at lead time. At least one required, enforced both client-side and at DB level. Rationale: downstream teams need the interest signal to route follow-up; collecting it at capture costs ~5s and avoids a second call.
- **Audit log is intentionally auth-gated.** Migration 009 formalizes that `audit_log` only records app-user actions; Dashboard / service-role / migration writes are invisible to `audit_log`. Already consistent with the "Admin actions logged by Supabase Dashboard" decision — migration 009 just removes the FK failure mode.
**Backlog impact:**
- P0-20 already DONE (prior session).
- **New — P0-21 added & DONE 2026-04-15:** product-interest capture on lead form (column + constraint + UI + provider wiring).
- **P0-15 advanced but not closed.** Seed admin + test rep provisioned, forced-change path exercised live. Remaining: execute D1 RLS matrix + D2 dedup race from `scripts/test/` against the two real auth UUIDs, and do an end-to-end Chrome smoke (phone → temp pw → forced change → home → submit lead with products → verify row in Table Editor).
**Blockers now:** 0 active.
**Files changed:**
- `supabase/migrations/008_add_products_column.sql` (new)
- `supabase/migrations/009_audit_skip_no_auth.sql` (new)
- `lib/models/merchant.dart` (+ `products` field on `Lead`)
- `lib/providers/merchant_provider.dart` (+ `toggleProduct`, payload update)
- `lib/screens/lead/new_lead_screen.dart` (+ product checkboxes)
- `scripts/provision.log` (appended during live runs — gitignored)
- `CLAUDE.md` (this entry)
- `CLAUDE.archive.md` (rotated 2026-04-14 post-EOD entry)

---

### Session: 2026-04-14 (late night) — P0-1 executed via Supabase MCP
**Duration:** ~15m
**Focus:** Provision dev Supabase project, apply all migrations, verify via advisors.
**Completed:**
- Discovered user had already created project `yynhcrtdzgcgedkolgxw` ("Aman Sales App") in `eu-west-1`, Postgres 17, ACTIVE_HEALTHY. `pgsodium`, `supabase_vault`, `pgcrypto`, `uuid-ossp` pre-installed — zero Vault setup overhead.
- Applied migrations via `apply_migration` MCP tool:
  - `001_schema` — users, merchants, audit_log + indexes + set_updated_at + set_claim.
  - `002_phone_trigger` — `normalize_phone()` + test helper. BEFORE trigger on merchants.
  - `003_national_id_trigger` — `validate_national_id()` + test helper. Adjusted `digest()` call to `extensions.digest()` (pgcrypto lives in `extensions` schema on Supabase managed Postgres).
  - `004_rls_policies` — RLS + `is_admin()` + all policies.
  - `005_audit_triggers` — AFTER triggers on INSERT/UPDATE/DELETE with SOFT_DELETE detection.
  - `006_export_snippets` — documentation only, no DDL executed.
- Ran security advisors → 8 WARN "Function Search Path Mutable" lints. Created **`007_pin_function_search_paths`** (ad-hoc, not in the repo's numbered set) to `ALTER FUNCTION ... SET search_path` on all 8 public functions. Advisors re-run → clean.
- Smoke-tested triggers via `execute_sql`: `normalize_phone_test('01012345678')` → `+201012345678`; `validate_national_id_test('29001011234567')` → 64-char hex hash. Both pass.
- Retrieved project URL + publishable key. Created `.env` / `.env.example` / `run_dev.sh` (env + script gitignored). Flutter can now connect via `./run_dev.sh`.
**Decisions:**
- Only a dev project was provisioned. Prod creation deferred until after UAT — avoids doubled cost and preserves a clean prod slate.
- `007_pin_function_search_paths` hardening was added out-of-band (not pre-authored). Should be folded into the repo's numbered migration set in a follow-up housekeeping pass so a fresh `supabase db push` reproduces parity.
**Backlog impact:** P0-1 → DONE. Only P0-15 (test execution) remains in P0.
**Blockers now:** 0 active.
**Open items / not-yet-done in-app:**
- Seed admin user + first test rep — must be created via Supabase Dashboard Auth UI, then `set_claim(..., 'role', '"admin"')` run for the admin. Not automatable via MCP.
- Vault TCE manual wiring: Dashboard → Database → Vault → Encrypted Columns → add `public.merchants.national_id`. Extension is installed but the column-level TCE config is a Dashboard step.
- 2FA on Supabase account — user-side.
**Next Session:**
- User performs Dashboard steps above (admin user, Vault TCE, 2FA).
- Execute P0-15 test matrix end-to-end against the live project (`docs/P0-TEST-MATRIX.md`).
- `./run_dev.sh` → visual verification against the Figma reference flow.
- Fold migration 007 into the repo's numbered migration set.

---

### Session: 2026-04-14 (post-EOD) — Housekeeping sync
**Duration:** ~5m
**Focus:** Post-session sync. No new code or SQL changes. File hygiene only.
**Completed:**
- Confirmed no files modified in `lib/`, `supabase/`, or `docs/` since last session (all files present match the "P0 parallel build execution" session output).
- Cleaned stray dangling fragment at end of Session Log (duplicate "Next Session" block left over from a prior edit).
- Rotated oldest entry ("Admin provisioning model locked") to `CLAUDE.archive.md` to hold cap at 5.
**Decisions:** None.
**Backlog impact:** None.
**Blockers now:** 0 active (residency still monitoring-only).
**Next Session:**
- Unchanged from prior session: provision Supabase project when legal clears residency (P0-1), then run migrations 001–006 and execute the P0-15 test matrix against live Supabase. Visual verification via `flutter run -d chrome` against Figma reference flow.

---

### Session: 2026-04-14 (EOD) — Phase 1 scope match to Figma + P0 implementation guide
**Duration:** ~30m
**Focus:** Align Phase 1 build scope exactly to the Figma reference flow. Produce a step-by-step P0 implementation guide. Confirm hard-reject for National ID. Resolve remaining blockers.
**Completed:**
- Read current Flutter code end-to-end (`main.dart`, `auth_provider.dart`, all auth screens, merchant 3-step flow, `Merchant` model).
- Produced code-level gap analysis: current state vs. target POC flow. Identified 12 concrete deltas across routing, auth provider, merchant model/flow, and dependency cleanup.
- Wrote **`docs/P0-IMPLEMENTATION-GUIDE.md`** — 4-phase build order (A backend SQL, B Flutter auth, C lead capture rework, D testing) with dependency graph, time estimates, and acceptance criteria per step.
- Downgraded MENA data residency from CRITICAL to monitoring-only per Marwan. No longer flagged each session.
- Resolved temp-password delivery channel blocker: email + WhatsApp, admin sends manually. Decision promoted into Current Decisions.
- Confirmed **hard-reject** behavior for malformed phone and National ID at DB trigger level. Updated Current Decisions + P0-16a/b notes accordingly.
- Flagged that visual Figma verification could not happen in-session (Figma JS prototype not renderable via WebFetch; Chrome extension offline; no Flutter SDK in sandbox). Guide includes explicit verification step for user.
**Decisions:**
- **Phase 1 scope locked** to: phone -> password -> (change-password if flagged) -> home -> single-screen lead form. Captured in Current Decisions with Figma link.
- **Hard-reject** confirmed for trigger validation. Arabic errors.
- **Residency** treated as monitoring-only going forward; will not be re-flagged session-to-session until legal responds.
- **Phase A (Postgres SQL) can proceed in parallel** with Phase B/C (Flutter rewrite) — portable SQL, deployable once P0-1 unblocks.
**Backlog impact:** No new items; existing P0 items gain a concrete dependency-ordered build plan in the guide.
**Blockers now:** 0 active.

---

### Session: 2026-04-14 (late PM) — POC scope lock + security posture decision
**Duration:** ~45m
**Focus:** Evaluate client-side encryption options (hardcoded key → device-only → password-derived → KMS → Cloudflare Worker) vs. server-side column encryption vs. plaintext. Lock pilot scope as lead-capture-only.
**Completed:**
- Walked through full key-management option space: AWS KMS, device-only, password-derived (PBKDF2), Cloudflare Worker key broker, Supabase Vault, hardcoded-in-APK.
- Surfaced the multi-user + device-loss constraint that kills device-only and password-derived approaches for a multi-rep sales team with admin export.
- Reframed: challenged whether client-side encryption is even needed at pilot scale. Argued for skipping it and relying on Supabase baseline + legal documentation.
- User pushed back on plaintext; landed on **Supabase Vault (pgsodium TCE)** as the pragmatic middle ground — server-side column encryption, zero Flutter changes, ~2h setup.
- Confirmed **lead-capture-only POC scope**: no KYC images, no selfies, no ID photos. Aman feeds downstream KYC systems via SQL export for pilot.
**Decisions:**
- **POC scope:** Lead capture only (name, phone, National ID number, notes, status). Full merchant profile + KYC is a post-pilot evolution (P2-6).
- **Pilot security posture:** Supabase Vault on `merchants.national_id` + plaintext `national_id_hash text UNIQUE` for dedup. TLS + at-rest + RLS + 2FA + audit log baseline.
- **Client-side encryption deferred** to pre-production, pending PDPL legal response. Cloudflare Worker key broker identified as the graduation path if legal demands separation of keys from ciphertext.
- **UI masking + reveal-with-audit deferred** to post-POC (P1-6) — requires dedicated merchant profile screen that doesn't exist yet.
- **Descoped P0-8** (KYC image upload) and **P1-5** (image compression) → DONE-BY-DESIGN. Rolled into P2-6 for post-pilot evolution.
- **Updated P0-2 schema** to reflect Vault + hash columns, no image refs.
- **Updated P0-7** to "Lead registration" (was "Merchant registration") to reflect narrower scope.
- **Residency blocker updated:** risk surface reduced (narrower data scope + Vault), but still CRITICAL until legal confirms.
**Net backlog impact:** 2 items descoped (P0-8, P1-5), 2 items added (P1-6 UI masking, P2-6 full merchant evolution), several items scope-trimmed. Pilot build effort reduced by ~2–3 days.
**Next Session:**
- Draft P0-16a (phone trigger) SQL + tests — portable Postgres, buildable now, independent of residency outcome.
- Draft P0-16b (National ID trigger) SQL + tests — hard-reject confirmed, includes hash computation for Vault + dedup pattern.
- Package both as one paste-ready file for Supabase SQL Editor with test fixtures.
- Await legal response on PDPL with updated (narrower) data scope.

---

### Session: 2026-04-14 (night) — P0 parallel build execution
**Duration:** ~30m (agent wall-clock)
**Focus:** Execute P0 implementation guide via 4 parallelized Claude Code agents. Build all SQL migrations + rewrite Flutter auth + collapse lead form.
**Completed:**
- Initialized git repo (baseline commit) and created `supabase/migrations/` directory.
- **Track A (SQL agent):** Created 6 migration files (001-006) covering schema, phone trigger, NID trigger, RLS, audit, exports. Created bilingual admin runbook.
- **Track B (Flutter auth agent):** Rewrote auth_provider.dart (mock → Supabase signInWithPassword + changePassword + biometric). Updated main.dart with Supabase.initialize(). Updated user.dart model. Rewired phone_entry, password, forgot_password screens. Created change_password_screen. Deleted otp_screen, otp_input, set_password_screen.
- **Track C (Lead capture agent):** Stripped Merchant model to Lead (5 fields). Rewrote MerchantProvider to LeadProvider with Supabase insert + dedup error handling. Created single-