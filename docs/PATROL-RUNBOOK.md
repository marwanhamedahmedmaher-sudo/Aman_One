# Patrol Regression Test — Runbook

Golden-path end-to-end regression test on a real Android emulator against
**prod** Supabase. Triggered automatically on every PR touching `lib/`,
`pubspec.yaml`, `integration_test/`, or Android build files; manually via
`workflow_dispatch` on `Patrol Regression`.

The test creates exactly one merchant row per run, tagged in its `notes`
field with `PATROL-TEST-<timestamp>-<random>`, and deletes that row via
the rep's JWT at `tearDown`. Per the V1 audit policy, `audit_log` rows
are retained — they carry no PII beyond the merchant UUID.

---

## What this test covers

1. Phone entry → password login with a durable pilot test rep.
2. Biometric opt-in dialog dismissal (when the emulator surfaces it —
   usually skipped since CI emulators lack biometric hardware).
3. Lead form with all three products (`Microfinance`, `BP POS`,
   `Acceptance POS`) — exercises every conditional detail field
   (`microfinance_amount`, `acceptance_device_count`) and the Arabic
   RTL rendering path.
4. `phone_trigger` and `national_id_trigger` acceptance of
   checksum-valid fixtures, plus SHA-256 dedup hash.
5. Lead success screen → merchant list → merchant profile navigation.
6. NID reveal RPC + `audit_log` row creation (the list+profile path
   calls `reveal_national_id` which is `SECURITY DEFINER`).
7. RLS: only the test rep's own merchants appear in the list.

## What this test does NOT cover (known gaps)

- **First-login forced change-password.** The flow fires only once per
  rep lifetime; a durable test rep has already rotated past it. Covering
  it would require provisioning a fresh rep every CI run, which needs
  `SUPABASE_SERVICE_ROLE_KEY` in GitHub Actions — a security budget we
  are not spending for V1. Revisit when the admin surface graduates to
  an Edge Function (Current Decisions: "Provisioning model — Option C2").
- **Phone / NID rejection paths.** Bad-input Arabic errors raised by the
  Postgres triggers. Covered by SQL fixtures in
  [`002_phone_trigger.sql`](../supabase/migrations/002_phone_trigger.sql) and
  [`003_national_id_trigger.sql`](../supabase/migrations/003_national_id_trigger.sql) — no
  UI regression gap.
- **Biometric enrollment.** Would need `adb` fingerprint enrollment on
  the CI emulator; skipped for V1.
- **Tasks / cross-sell assignment flow.** Separate test target —
  revisit once the tasks feature lands pilot traffic.

---

## One-time setup (Marwan)

### 1. Provision the durable test rep in prod

Run **once** on your admin laptop. Reuse every CI run thereafter.

```bash
# Load prod service-role key from Bitwarden into the current shell.
export BW_SESSION=$("$BW_CLI" unlock --raw)
source .env.admin   # active target: prod

./scripts/provision_rep.sh \
  --phone "+201099990000" \
  --name "Patrol Test Rep" \
  --employee-id "PATROL-001" \
  --role sales_rep \
  --region "Cairo"
```

The script prints a temp password once. **Copy it**, then immediately:

1. Install the pilot APK on any device or emulator.
2. Log in as `+201099990000` with the temp password.
3. Rotate the password when prompted (this flips
   `must_change_password=false` so CI skips the forced-rotation screen).
4. Save the **final** password — this is `PATROL_TEST_PASSWORD`.

The phone number `+201099990000` is a deliberately-chosen non-allocated
Vodafone bucket (010-9999-XXXX) unlikely to collide with real merchants.
Use a different number if you have reason to expect collision.

### 2. Add GitHub Actions secrets

Repo → Settings → Secrets and variables → Actions → New repository secret:

| Name | Value |
|------|-------|
| `SUPABASE_URL` | `https://yflwudkmhqwoscipscbb.supabase.co` (already set for the build workflow — reuse) |
| `SUPABASE_ANON_KEY` | Already set for the build workflow — reuse |
| `PATROL_TEST_PHONE` | `+201099990000` (or whatever you used in step 1) |
| `PATROL_TEST_PASSWORD` | The **rotated** password from step 1.3 — NOT the temp password |

No `SUPABASE_SERVICE_ROLE_KEY` in CI. Cleanup runs via the rep's own JWT.

### 3. Trigger the first run

Actions → Patrol Regression → Run workflow (from `main`). First run takes
~15–20 minutes because the AVD cache is cold; subsequent runs are
~5–8 minutes.

---

## Local development

Running Patrol locally against a connected emulator:

```bash
# Activate CLI once per machine.
dart pub global activate patrol_cli 3.9.1

# Start an emulator (or attach a device).
flutter emulators --launch <avd_name>

# Run the golden path.
patrol test \
  --target integration_test/patrol_test.dart \
  --dart-define=SUPABASE_URL="https://yflwudkmhqwoscipscbb.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="<prod anon key>" \
  --dart-define=PATROL_TEST_PHONE="+201099990000" \
  --dart-define=PATROL_TEST_PASSWORD="<rotated password>"
```

Corp-laptop note: the same Gradle `localhost` loopback issue that blocks
local release builds (see Current Decisions — "Release APK builds via
GitHub Actions CI") may affect Patrol's Gradle build. If it does, the
fix is the same as for CI: run Patrol from CI rather than locally.
`flutter analyze` and unit tests still work locally regardless.

---

## Recovery — cleanup when a run crashes

If a Patrol run crashes mid-test and leaves a tagged merchant row behind,
run this one-off SQL in the Supabase SQL Editor (prod project
`yflwudkmhqwoscipscbb`):

```sql
-- Show leftover Patrol test rows.
SELECT id, name, notes, created_at
FROM merchants
WHERE notes LIKE '%PATROL-TEST-%'
ORDER BY created_at DESC;

-- Delete them (retains audit_log rows, per V1 audit policy).
DELETE FROM merchants
WHERE notes LIKE '%PATROL-TEST-%';
```

Do not delete `audit_log` rows — they are the system of record for rep
actions and policy bars their removal.

---

## When the test fails

1. Check the `patrol-failure-logs` artifact on the workflow run — it
   contains the Flutter test logs and any Patrol stack traces.
2. Common failure modes and fixes:
   - **"Phone logins are disabled"** on login: someone toggled the Auth →
     Providers → Phone setting in the Supabase Dashboard. Turn it back on
     (see [docs/P0-DASHBOARD-RUNBOOK.md](P0-DASHBOARD-RUNBOOK.md)).
   - **`must_change_password=true` redirect**: the test rep's password
     got admin-reset. Log in manually, rotate, update
     `PATROL_TEST_PASSWORD` secret.
   - **"رقم القومي غير صحيح"** submit error: the NID generator drifted —
     verify [integration_test/helpers/test_data.dart](../integration_test/helpers/test_data.dart)
     still matches the trigger rules in
     [003_national_id_trigger.sql](../supabase/migrations/003_national_id_trigger.sql).
   - **Widget finder timeout on Arabic text**: a screen's Arabic copy
     changed. Update the finder in
     [integration_test/patrol_test.dart](../integration_test/patrol_test.dart)
     (strings are encoded as `\uXXXX` escapes — search for the old
     codepoints).
3. If the Patrol/Flutter SDK is the culprit, bump `patrol` in
   `pubspec.yaml` and `patrol_cli` version in
   `.github/workflows/patrol-regression.yml` **together** — they must
   match major versions.
