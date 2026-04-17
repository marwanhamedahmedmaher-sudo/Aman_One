# Aman Sales App (أمان) — Architecture Reference

Arabic RTL sales-rep lead-capture app built with Flutter + Supabase.

## Tech Stack

- **Framework:** Flutter (SDK ^3.11.4) — Web + mobile (Android/iOS)
- **Language:** Dart
- **State Management:** Provider (`ChangeNotifierProvider`)
- **UI:** Material 3 with custom theme (`AppTheme.lightTheme`)
- **Fonts:** Google Fonts
- **Auth:** Supabase Auth — phone-as-username + password; biometric fast-path via `local_auth`
- **Backend:** Supabase (Postgres 17, RLS, Vault/pgsodium, Edge Functions) — region `eu-west-1`, dev project `yynhcrtdzgcgedkolgxw`
- **Secrets:** `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` wired via `run_dev.sh`; admin service-role key in `.env.admin` sourced from password manager

## Architecture

```
lib/
├── main.dart                  # App entry, routing, Arabic RTL locale, Supabase init
├── theme/app_theme.dart       # Material 3 theme
├── models/                    # User, Merchant/Lead
├── providers/                 # AuthProvider, MerchantProvider (LeadProvider)
├── widgets/                   # Reusable widgets (AuthHeader, etc.)
└── screens/
    ├── auth/                  # phone_entry, password, change_password (NO OTP — descoped)
    ├── main/                  # MainShell, HomeScreen, TasksScreen, ProfileScreen
    └── lead/                  # new_lead_screen.dart — single-screen lead form

supabase/migrations/           # Numbered SQL migrations, applied via MCP or supabase db push
scripts/                       # provision_rep.sh, reset_password.sh, test/
docs/                          # P0-DASHBOARD-RUNBOOK, P0-IMPLEMENTATION-GUIDE, P0-TEST-MATRIX
```

## Data Model

- `auth.users` — Supabase-managed. Phone-as-username. Admin-provisioned only (public signup OFF).
- `public.users` — app profile (employee_id, role, status, must_change_password). FK to `auth.users.id`.
- `public.merchants` — lead records. Columns: `name`, `phone` (E.164), `national_id` (Vault TCE), `national_id_hash` (SHA-256 UNIQUE for dedup), `notes`, `products text[]` (≥1 from {Microfinance, BP POS, Acceptance POS}), `status`, `created_by`, timestamps.
- `public.audit_log` — app-user actions only (INSERT/UPDATE/SOFT_DELETE/DELETE on merchants). Dashboard/service-role writes skip audit by design (see migration 009).

## Security Model

- **RLS on all 3 tables.** Reps see only their own merchants; admins see all. `is_admin()` helper in 004.
- **Claims-based roles** via `set_claim()` RPC; enforced in RLS.
- **Vault TCE** on `merchants.national_id` — ciphertext at rest, transparent decrypt for authorized reads.
- **Hard-reject triggers** for malformed phone / National ID at DB level — Arabic errors surfaced to client.
- **2FA mandatory** on Supabase Dashboard accounts. Dashboard member list kept to ≤2.

## Commands

```bash
flutter pub get                   # Install dependencies
./run_dev.sh                      # Run Chrome with SUPABASE_URL + ANON_KEY env
flutter analyze                   # Static analysis
flutter test                      # Run tests

./scripts/provision_rep.sh ...    # Admin: create rep/admin via Admin API (no SMS)
./scripts/reset_password.sh ...   # Admin: rotate password + force change
./scripts/test/run_sql.sh FILE    # Execute SQL test fixtures against live DB
```

## Migration Conventions

- Numbered sequentially (`001_*.sql` → `009_*.sql`). Applied via Supabase MCP `apply_migration` or `supabase db push`.
- **Always reproducible from empty DB.** Ad-hoc Dashboard SQL must be folded back into a numbered migration before session close.
- **Audit trigger must be toggled off during data backfills in migrations.** Migrations run without `auth.uid()`; migration 009 now auth-gates the trigger so this is only necessary for backfills that predate 009, but the pattern (`ALTER TABLE ... DISABLE TRIGGER trg_merchants_audit_update;` → UPDATE → `ENABLE TRIGGER`) is documented in 008 as the reference approach.
- `SET search_path` pinned on every `SECURITY DEFINER` function (see migration 007) — required to pass Supabase security advisors.

## Conventions

- **Language:** Arabic-only, RTL layout enforced via `Directionality` wrapper.
- **Locale:** `Locale('ar')` with Material/Cupertino/Widgets localization delegates.
- **State:** Provider pattern — data models in `models/`, state in `providers/`.
- **Screens:** Organize by feature under `lib/screens/`.
- **No OTP, no KYC images in V1.** Scope is lead capture only — see CLAUDE.md "Current Decisions".
