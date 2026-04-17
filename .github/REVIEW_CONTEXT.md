# Aman Sales App — Code Review Context

> **Audience:** Any AI or human code reviewer (CodeRabbit, Claude, Copilot, Greptile, or a human teammate).
> **Purpose:** Give the reviewer enough context to produce a fintech-realistic, pilot-grade review of this repo **before** production sign-off.
> **Read this first**, then read `CLAUDE.md` (project state) and `ARCHITECTURE.md` (tech stack).

---

## 1. What this app is (1-paragraph brief)

Aman (أمان) is an **Arabic-first, RTL** Flutter mobile/web app used by a small number of **admin-provisioned sales reps** to capture merchant leads for a fintech in Egypt. Reps submit a name, phone, Egyptian National ID (NID), products of interest, and a few optional business fields. Leads are pulled out of Supabase by other teams via saved SQL snippets for downstream KYC. The app is **pilot-stage (20–50 reps)**, not production, and under **Egyptian PDPL Law 151/2020** constraints (data residency currently in EU — see Blockers in `CLAUDE.md`).

**What this app deliberately does not do** (do NOT flag as missing):
- No public sign-up (admin-only provisioning via Supabase Dashboard + `scripts/provision_rep.sh`).
- No OTP, no SMS. Phone-provider ON for phone-as-username; SMS-provider must stay OFF.
- No KYC image capture (ID cards, selfies) — descoped for POC. See P0-8 in `CLAUDE.md`.
- No in-app admin screens — admin actions happen in Supabase Dashboard (see `docs/P0-DASHBOARD-RUNBOOK.md`).
- No English UI — Arabic-only, RTL is a correctness requirement.
- No business / commercial-registration merchants — Egyptian individuals only in V1.

Every item above is an explicit, documented scope decision in `CLAUDE.md › Current Decisions`. Do not re-open these unless the PR itself changes scope.

---

## 2. Review priorities (in order)

1. **Security & PDPL** — this is a fintech app handling Egyptian NIDs. Over-report here; false positives are cheap.
2. **Supabase / Postgres correctness** — migrations, RLS, triggers, SECURITY DEFINER RPCs. A broken migration is a pilot-ending incident.
3. **Flutter & Dart quality** — RTL correctness, state management, error handling, async lifecycles.
4. **General maintainability** — naming, duplication, dead code, test coverage.

If you can only raise five comments, they should be drawn from (1) and (2).

---

## 3. Security & PDPL — what to surface

### 3.1 NID / merchant data handling (highest risk)

**Must flag:**
- Any `SELECT national_id` against `public.merchants` from client-side Dart code. The **only** permitted client path to plaintext NID is the `reveal_national_id(uuid)` RPC (see `supabase/migrations/010_reveal_national_id_rpc.sql`). Any other path bypasses the audit row.
- Any Dart code that stores the plaintext NID in `SharedPreferences`, `flutter_secure_storage`, in-memory caches that outlive a screen, logs, analytics events, or crash-reporter breadcrumbs.
- Any SQL that reads `merchants.national_id` into a view, materialized view, temp table, or export snippet without encryption-aware handling. The V1 exports (`006_export_snippets.sql`) intentionally return `national_id_hash`, **not** plaintext — flag any new snippet that exposes plaintext.
- Any code that writes to `audit_log` with a bypass path (service-role from client, raw SQL wrapper, etc.). `migration 009` deliberately skips audit when `auth.uid()` is NULL — do NOT treat that as a bug; it exists so Dashboard/migration writes don't blow up.
- Any removal of the `national_id_hash UNIQUE` constraint or the normalization trigger. Dedup is enforced at the DB, not in Dart.

**Must NOT flag (these are deliberate):**
- `merchants.national_id` stored in Supabase Vault (pgsodium TCE) rather than an external KMS — this is the documented POC security posture. Client-side encryption / external KMS is deferred pending PDPL legal response.
- Hard-reject on malformed phone/NID surfacing Arabic errors instead of flag-and-save.

### 3.2 Authentication & session

**Must flag:**
- Any code path that sets `must_change_password = false` client-side without an actual password rotation. The forced-rotation flow is the only protection on admin-issued temp passwords.
- `signInWithPassword` called with a raw phone that hasn't been run through `_toE164()` in `auth_provider.dart`.
- Biometric-unlock code that skips the Supabase session refresh (biometric fast-path in `auth_provider.dart` must re-validate the Supabase session, not just unlock the app shell).
- Any storage of passwords (even "temp" passwords) in plain text anywhere — including UI state, route arguments, or logs.
- Any hardcoded Supabase URL or anon key in Dart source. They must come via `--dart-define`. Service-role keys must **never** appear in client code.

### 3.3 RLS & policy discipline

**Must flag:**
- Any new table without RLS enabled + explicit policies. `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` is not optional.
- Any `SECURITY DEFINER` function without `SET search_path = public` pinned. This is a Supabase security-advisor requirement — `migration 007` was specifically created to fix this across earlier functions.
- Any new `SECURITY DEFINER` function that returns sensitive data without manually enforcing ownership (`created_by = auth.uid() OR is_admin()`) — RLS is bypassed inside SECURITY DEFINER, so policy has to be re-written by hand. See `010_reveal_national_id_rpc.sql` for the canonical pattern.
- Any policy that uses `true` as a USING or WITH CHECK expression on user-facing tables.
- Any role grant broader than `authenticated` on RPCs that touch merchant data. `anon` must remain locked out of all three tables (`users`, `merchants`, `audit_log`).

### 3.4 Secrets & config

**Must flag:**
- `.env.admin`, `credentials-temp.txt`, or anything containing a service-role key appearing outside `.gitignore`. These are local-only during POC.
- Service-role keys passed to any client-facing code, including Flutter web.
- Any new CI workflow that prints secrets or stores them outside GitHub Actions secrets.

---

## 4. Supabase / Postgres correctness

### 4.1 Migration hygiene

**Must flag:**
- Any migration that is not numbered sequentially (`NNN_name.sql`) in `supabase/migrations/`.
- Any migration that is not idempotent (missing `IF NOT EXISTS`, `CREATE OR REPLACE`, etc.) when it could be.
- Any migration that performs a data backfill with the audit trigger enabled **and** without `auth.uid()` context, unless it explicitly disables/re-enables the trigger. See `ARCHITECTURE.md › Migration Conventions` and migration 008 as the reference.
- Any ad-hoc Dashboard SQL referenced in a PR that is not folded into a numbered migration. Every DB change must be reproducible from an empty DB.
- Any destructive column drop on `merchants`, `users`, or `audit_log` — these are pilot-critical. At minimum require a two-step migration (deprecate-then-drop across releases).

### 4.2 Trigger & function correctness

**Must flag:**
- New triggers on `merchants` that do not handle NULL `auth.uid()` — Dashboard and migration-time writes have no session context and will break (see 009 for the pattern).
- Phone / NID validation logic added in Dart that is not mirrored by (or redundant against) the DB triggers. The DB is the final authority. If Dart does pre-validation for UX, fine, but the DB must still reject bad data.
- New RPCs that write to `audit_log` with a row shape that diverges from existing audit rows (actor_id, action, table_name, record_id, old_data, new_data).

### 4.3 Query & index correctness

**Must flag:**
- `SELECT *` from `merchants` on the client when the NID column is in scope (it is) — this leaks Vault-decrypted NIDs down to the client unnecessarily. Enumerate needed columns, exclude `national_id`. `merchant_list_provider.dart` already follows this pattern.
- New indexes on `national_id` plaintext. The hash column is indexed via UNIQUE; plaintext indexing would create a ciphertext-index covariance channel.
- Missing index on new foreign-key columns (e.g., `activity_type_id` has one; new FKs should too).

---

## 5. Flutter & Dart quality

### 5.1 RTL correctness (non-negotiable)

The app is Arabic-first. This is a correctness requirement, not cosmetic.

**Must flag:**
- Use of `EdgeInsets.only(left: …, right: …)` instead of `EdgeInsetsDirectional.only(start: …, end: …)`.
- Use of `Alignment.centerLeft` / `Alignment.centerRight` instead of `AlignmentDirectional.centerStart` / `centerEnd`.
- Hardcoded `TextDirection.ltr` anywhere outside genuinely LTR content (e.g., a raw phone number input field — arguably OK, but call it out).
- Icons that have an implied direction (e.g., `Icons.arrow_forward`) without a RTL-aware swap or without `Transform.flip`.
- New strings added in English to user-facing UI. All user-visible strings must be Arabic.
- Removal of the `Directionality(textDirection: TextDirection.rtl)` wrapper or `Locale('ar', 'EG')` from `main.dart`.

### 5.2 State, async, lifecycle

**Must flag:**
- `setState()` or `notifyListeners()` called after `dispose()` without a `mounted` / `!_isDisposed` guard.
- `async` gaps in widget code that use `BuildContext` after the `await` without checking `context.mounted`.
- Provider instances created inside `build()` (should be at app or route root, typically `MultiProvider` in `main.dart`).
- Swallowed exceptions in providers (a `try/catch` that eats the error without surfacing user-friendly Arabic feedback and without logging — biometric, auth, and Supabase calls all need error surfaces).
- Missing `await` on a `Future` that has observable side effects.

### 5.3 Error UX

**Must flag:**
- Supabase errors surfaced as raw English `PostgrestException` text in the UI instead of mapped Arabic messages (examples: `رقم الموبايل غير صحيح`, `رقم القومي غير صحيح`, `هذا العميل مسجل مسبقًا`).
- Network-failure paths with no retry affordance or visible error state.
- Loading states that don't visibly clear on error (spinner-forever bug).

---

## 6. General maintainability

**Should flag:**
- Duplicated form-field widgets across `new_lead_screen.dart` and the merchant profile screen. Factor into a shared widget if the duplication grows.
- Magic strings for `products` values (`'Microfinance'`, `'BP POS'`, `'Acceptance POS'`) — prefer a shared enum/constants file.
- Magic strings for `status` values (`'lead'`, `'qualified'`, `'rejected'`, `'converted'`) — same treatment.
- New providers that don't extend `ChangeNotifier` or that expose mutable state publicly without getters.
- New files > 300 LOC that mix widgets, state, and API calls into one file.
- TODOs / FIXMEs introduced without an owner or a linked CLAUDE.md backlog entry.

**Should NOT flag (pilot-appropriate trade-offs):**
- Low unit-test coverage — this is a POC; RLS and trigger tests (`scripts/test/`) are the system of record. Mention once if a truly critical path is untested; don't belabor.
- Use of `print()` in debug-only code paths. Fine for POC.
- Missing dartdoc on every public member.

---

## 7. What a good review comment looks like on this repo

**Good:**

> `lib/providers/merchant_list_provider.dart:42` — this new `fetchMerchantById` helper runs `.select('*')` which will pull `national_id` (plaintext after Vault TCE decrypt) down to the client. That bypasses the audit row written by `reveal_national_id()`. Either enumerate columns and exclude `national_id`, or route through the RPC. See `REVIEW_CONTEXT.md §3.1`.

**Bad:**

> Consider adding more tests to this provider.

The first is actionable, cites the file + line, names the actual rule being violated, and references the governing doc. The second is noise. Prefer the first pattern.

---

## 8. Quick reference — files that define the rules

| Concern | File |
|---|---|
| Project scope + decisions | `CLAUDE.md` |
| Tech stack + architecture | `ARCHITECTURE.md` |
| Schema | `supabase/migrations/001_schema.sql` |
| Phone / NID triggers | `supabase/migrations/002_phone_trigger.sql`, `003_national_id_trigger.sql` |
| RLS policies | `supabase/migrations/004_rls_policies.sql` |
| Audit triggers | `supabase/migrations/005_audit_triggers.sql`, `009_audit_skip_no_auth.sql` |
| NID reveal RPC (SECURITY DEFINER exemplar) | `supabase/migrations/010_reveal_national_id_rpc.sql` |
| `search_path` pinning | `supabase/migrations/007_pin_function_search_paths.sql` |
| Auth flow | `lib/providers/auth_provider.dart` |
| Lead form | `lib/screens/lead/new_lead_screen.dart` |
| Merchant profile (reveal UX) | `lib/screens/merchant/merchant_profile_screen.dart` |
| Admin runbook | `docs/P0-DASHBOARD-RUNBOOK.md` |
| Pilot deployment gate | `docs/PILOT-DEPLOYMENT-CHECKLIST.md` |

---

## 9. Pre-production (pilot) review checklist

Before a PR is eligible to be part of the pilot cut, the reviewer should be able to answer **yes** to each of the following:

1. RLS is enabled on every new table, with policies that distinguish rep from admin.
2. Every new `SECURITY DEFINER` function pins `search_path` and enforces ownership manually.
3. No new Dart path reads plaintext `national_id` outside the `reveal_national_id` RPC.
4. Every new trigger on `merchants` tolerates NULL `auth.uid()`.
5. Every new user-visible string is Arabic and renders correctly under `TextDirection.rtl`.
6. `flutter analyze` is clean.
7. No new file in `supabase/migrations/` is out of sequence, and no ad-hoc Dashboard SQL is referenced without being folded into a numbered migration.
8. No secret (service-role key, password, temp credential) appears in source, logs, or CI output.
9. The CLAUDE.md backlog is updated — a new feature has a backlog row; a bug fix references one.
10. If the change touches NID, auth, or RLS, a human (not just the AI reviewer) has signed off.

Items 1–8 can be enforced by CodeRabbit custom pre-merge checks. Items 9–10 are process.
