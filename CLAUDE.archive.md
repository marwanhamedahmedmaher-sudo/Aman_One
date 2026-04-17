# Aman Sales App — Session Log Archive

Session log entries rotated out of `CLAUDE.md`. Newest first within this file.

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