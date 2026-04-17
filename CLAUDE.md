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
- **Provisioning model — Option C1 (script via Admin API):** `scripts/provision_rep.sh` + `scripts/reset_password.sh` call Supabase Admin API with `phone_confirm: true` (no SMS). Service-role key currently lives in `.env.admin` (plain text, gitignored) on solo developer's encrypted laptop — acceptable risk for POC dev project. **Hard upgrade trigger:** move to password manager (`op read` / `bw get`) the day a second admin joins OR the prod Supabase project is provisioned. `.env.admin.example` documents both patterns. Graduates to Edge Function (C2) post-pilot.
- **Phone provider ON, SMS provider UNCONFIGURED — permanent V1 rule.** Phone provider is required for phone-as-username login; SMS provider must remain unconfigured to avoid silently enabling billable OTP flows the app does not implement. Documented as a hard rule in P0-18 runbook.
- **Public signup OFF.** Authentication → Settings → "Allow new users to sign up" → OFF. Admin-only provisioning is enforced at the Auth layer, not just by convention.
- **NID reveal policy (V1):** One tap on "Reveal NID" in the merchant profile screen → plaintext NID visible for the remainder of that screen visit. Navigating away re-masks; returning requires another tap. Each tap writes one `national_id_revealed` row to `audit_log` via RPC. No timer, no re-prompt. Simple, auditable, one-audit-row-per-intent.
- **RTL-first UI:** App is Arabic-first for Egyptian reps. All screens must render RTL by default (`Locale('ar', 'EG')` + locale-driven `Directionality`). New screens built RTL-native; existing screens audited and fixed before pilot.
- **Merchant list + profile scope (V1):** Reps access their own merchants via the home dashboard card ("created this week") → full merchant list (not filtered). View-only. Admin "all merchants" view deferred to post-pilot.
- **Product-specific data capture:** Each product selection on the lead form can trigger additional required fields. Microfinance → "المبلغ" (amount, numeric). Acceptance POS → "عدد الأجهزة" (device count, integer). BP POS → no extra fields. DB CHECK constraints enforce: detail required when product selected, must be NULL when product not selected. Client validates before submit; DB is final authority.
- **Merchant information fields (optional):** Three informational fields on the lead form: `avg_monthly_sales` (numeric, EGP), `business_address` (free text), `activity_type_id` (FK to `activity_types` lookup table). All nullable — not required for lead submission. Activity types managed by admin via Supabase Dashboard Table Editor; seeded with 10 values (سوبر ماركت, صيدلية, مطعم, كافيه, بقالة, ملابس, إلكترونيات, مواد بناء, خدمات, أخرى). RLS: authenticated read, admin write.

---

## Backlog

Status markers: `TODO` | `IN_PROGRESS` | `DONE` | `BLOCKED`

### P0 — Must Ship (pilot blockers)

| # | Task | Status | Assigned | Notes |
|---|------|--------|----------|-------|
| 1 | Supabase project setup (dev + prod) | DONE 2026-04-16 | — | Dev: `yynhcrtdzgcgedkolgxw`. **Prod: `yflwudkmhqwoscipscbb`** — both eu-west-1, Postgres 17. Prod: all 15 migrations applied, RLS on 6 tables, 10 activity types seeded, 5 RPCs verified, security advisors clean. **Auth settings confirmed by Marwan 2026-04-16** (phone ON, SMS OFF, signup OFF, 2FA enabled). |
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

### P2 — Nice to Have

| # | Task | Status | Assigned | Notes |
|---|------|--------|----------|-------|
| 1 | Fuzzy dedup on name + phone | TODO | — | Postgres trigram / levenshtein. Warn on likely duplicate. |
| 2 | Bulk CSV import (admin) | TODO | — | Upload existing spreadsheet. |
| 3 | Per-rep quota dashboard | TODO | — | Home screen widget. |
| 4 | Offline lead draft queue | TODO | — | If field-rep scenario confirmed post-pilot. |
| 5 | Business merchant support (commercial registration) | TODO | — | Add `document_type` column (`national_id` \| `commercial_reg`), extend validation trigger with commercial-registration format. Deferred from V1 scope decision 2026-04-14. |
| 6 | Evolve beyond lead capture — full merchant profile + KYC | TODO | — | Post-POC evolution: KYC image capture (ID front/back, selfie), storage bucket with RLS, image compression, full merchant profile screen, reveal-with-audit pattern. Re-activates former P0-8 + P1-5. Scope to be re-planned after pilot learnings. |
| 7 | Post-pilot: move keystore + passwords to proper password manager | TODO | — | Pilot used encrypted 7z + cloud + USB backup (password memorized). Upgrade to Bitwarden Premium / 1Password before production release — attach `.jks` file + store keystore/key passwords in same entry. Also covers migrating service-role key from `.env.admin` plaintext to `op read` / `bw get`, especially if a second admin joins. Hard trigger: prod rollout beyond pilot cohort OR second admin onboarding, whichever comes first. |

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

*(Older entries archived to `CLAUDE.archive.md`.)*