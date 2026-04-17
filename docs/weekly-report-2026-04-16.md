# Weekly Report — Aman Sales App (أمان)

**Week:** 2026-04-13 → 2026-04-19 (week-to-date through Thu 2026-04-16)
**Owner:** Marwan (solo PM + dev)
**Report generated:** 2026-04-16

---

## Summary

First working week of the project, and it was a sprint in every sense. The entire **P0 pilot-blocker backlog (21 items) closed** in three working days (Apr 14–16), along with **9 of 12 P1 items**. Prod Supabase is live in eu-west-1 with all 15 migrations applied, provisioning scripts work end-to-end, RLS/dedup test suites are green, and the code-review agent is wired up. **The pilot is materially ready — what's left is Android packaging, manual Supabase Auth settings in Prod, and a security pass on the release APK.** Top risk: MENA/PDPL residency question is still outstanding with legal, though it is explicitly in "monitor, not block" mode pending a narrower scope (lead-capture only).

---

## Completed

Grouped by work stream. Dates are DONE-dates from the backlog.

### Backend (Supabase)

- **P0-1** Dev + Prod Supabase projects provisioned (2026-04-14 dev, 2026-04-16 prod). Both eu-west-1, Postgres 17. Prod project `yflwudkmhqwoscipscbb` has all 15 migrations applied, 6 tables with RLS, 10 activity types seeded, 5 RPCs verified, security advisors clean.
- **P0-2** Schema: `users`, `merchants`, `audit_log` + Vault TCE on `national_id` + `national_id_hash UNIQUE` for dedup (2026-04-14).
- **P0-3** Role model (`sales_rep`, `admin`) via custom JWT claims (2026-04-14).
- **P0-9** RLS policies for all 3 tables + `is_admin()` helper (2026-04-14).
- **P0-14** Audit log AFTER triggers on merchants (2026-04-14).
- **P0-16a / P0-16b** Phone + National ID normalization/validation triggers with hard-reject and Arabic errors (2026-04-14).
- **P0-17** Saved SQL export snippets with Arabic column headers (2026-04-14).

### Auth + Provisioning

- **P0-4** Supabase auth wiring (`signInWithPassword` + `must_change_password`) (2026-04-14).
- **P0-6** Biometric fast-path via `local_auth` (2026-04-14).
- **P0-19** Change-password screen (first-login rotation + voluntary change) (2026-04-14).
- **P0-20** Provisioning scripts (Option C1 — `provision_rep.sh`, `reset_password.sh`, Admin API, `phone_confirm: true`, no SMS) (2026-04-15).
- **P0-18** Dashboard operator runbook v1.1 (bilingual Arabic/English, SMS-off hard rule, script-first) (2026-04-14).

### App (Flutter)

- **P0-5** Removed OTP screen + rewired routing to match Figma flow (2026-04-14).
- **P0-7** Single-screen lead form with dedup error surfacing (2026-04-14).
- **P0-21** Product-interest capture on lead form (Microfinance / BP POS / Acceptance POS, ≥1 required) (2026-04-15).
- **P1-7** Client-side guard: submit disabled when zero products selected (2026-04-15).
- **P1-8** App-wide RTL enforcement confirmed (locale `ar_EG`, Directionality wrapper, directional-aware widgets) (2026-04-15).
- **P1-9** Merchant list + profile screens (view-only, rep's own merchants) (2026-04-15).
- **P1-6** NID masking + reveal-with-audit via SECURITY DEFINER RPC (`reveal_national_id`), folded into P1-9 delivery (2026-04-15).
- **P1-10** Product-specific conditional fields (Microfinance amount, Acceptance device count) (2026-04-15).
- **P1-11** Merchant info fields (`avg_monthly_sales`, `business_address`, `activity_type_id` FK) + activity types lookup seeded with 10 values (2026-04-15).

### Testing + Hardening

- **P0-15** End-to-end smoke test passed (phone login → forced change → lead submit → Supabase verification) (2026-04-15). **D1 RLS matrix: 15/15 PASS. D2 dedup race: 4/4 PASS.**

### Tooling / Pilot Readiness

- **P1-12** Pre-pilot code review agent: `.coderabbit.yaml` + `.github/REVIEW_CONTEXT.md`, assertive profile, 5 hard pre-merge gates (RLS, SECURITY DEFINER hardening, no plaintext NID, secrets hygiene, RTL) (2026-04-16).
- Day 1 pilot prep Wave 1 (2026-04-16): Android manifest permissions + label fix, `build.gradle.kts` release signing config + `minSdk=23`, `.gitignore` keystore hardening, `key.properties.example`, Prod Supabase spin-up, pilot deployment checklist + Day 1 execution plan docs.

### Descoped (DONE-BY-DESIGN)

- **P0-8** KYC image upload — descoped to post-POC (see P2-6).
- **P0-10/11/12/13** In-app admin screens — replaced by Supabase Dashboard + saved SQL snippets.
- **P1-4** Forgot password flow — admin-mediated in Dashboard.
- **P1-5** Image compression — descoped with image upload.

**Total:** 21/21 P0 closed (14 built, 5 descoped, 2 with design intent), 9/12 P1 closed.

---

## Remaining

### Immediate next (pilot path)

Nothing left in P0. What remains before pilot distribution is execution of the Day 1 plan (Wave 2 + Wave 3) and manual Dashboard config — none of it is backlog-gated:

| Item | Type | Owner | Why it matters |
|---|---|---|---|
| Wave 2 — `flutter analyze` (F), generate release keystore (G), Prod Auth settings (H: phone ON, SMS OFF, signup OFF, 2FA) | Deploy step | Marwan | Prerequisite for signed release APK |
| Wave 3 — Build release APK with `--dart-define` for Prod creds (I), decompile + security scan (J) | Deploy step | Marwan | Last line of defence before distribution |
| Pilot-grade keystore password is acceptable for POC; **must be upgraded before any true production cut** | Risk | Marwan | Flagged for post-pilot |

### Open backlog (explicitly deprioritized for pilot)

| # | Task | Priority | Status | Recommendation |
|---|------|---|---|---|
| P1-1 | National ID format validation (client-side) | P1 | TODO | DB trigger already hard-rejects — client-side is UX polish. **Ship without. Revisit after first 2 weeks of pilot feedback.** |
| P1-2 | Soft delete for merchants | P1 | TODO | No business driver yet. **Defer until a rep asks to "undo" a lead.** |
| P1-3 | Excel (.xlsx) export option | P1 | TODO | CSV export works. **Defer unless a stakeholder explicitly asks.** |
| P2-1 | Fuzzy dedup on name + phone | P2 | TODO | Post-pilot. |
| P2-2 | Bulk CSV import (admin) | P2 | TODO | Post-pilot. |
| P2-3 | Per-rep quota dashboard | P2 | TODO | Needs pilot learnings first. |
| P2-4 | Offline lead draft queue | P2 | TODO | Only if field-rep scenario confirmed. |
| P2-5 | Business merchant support (commercial registration) | P2 | TODO | Depends on pilot scope expansion. |
| P2-6 | Full merchant profile + KYC | P2 | TODO | Post-POC evolution. |

---

## Blockers

**0 active.**

Monitoring only:

| Item | Status | Since | Recommendation |
|---|---|---|---|
| MENA data residency (PDPL Law 151/2020) | Monitoring | 2026-04-14 | Downgraded from CRITICAL. Narrow POC scope (lead-capture only) + Supabase Vault at rest de-risks the legal exposure. Graduation path if in-region storage is required: AWS Bahrain / on-prem. **Action: confirm legal's written read on PDPL Art. 14 before pilot hits >50 users or any commercial-registration / business data enters the schema.** |

### Risks to flag

1. **Service-role key storage** — still in `.env.admin` plaintext on the solo dev's laptop. Acceptable for POC. **Hard upgrade trigger already documented: move to password manager (`op read` / `bw get`) the day a second admin joins OR prod provisioning begins.** Prod is now live (2026-04-16), so this trigger is active — recommend upgrading this week.
2. **Pilot keystore** — pilot-grade passwords. Not a blocker for sideload pilot, but note that signed APKs cannot be re-signed with a stronger key without forcing a reinstall.
3. **Admin audit gap** — admin actions are logged by Supabase Dashboard only, not in-app `audit_log`. Documented, accepted for POC. Revisit before true production launch.
4. **Prod Auth settings still manual** — phone-ON / SMS-OFF / signup-OFF / 2FA must be toggled in the Dashboard; nothing automatically enforces this today. Risk of drift if Marwan forgets or if a second admin joins later.

---

## Velocity

**Completed this week:** ~30 backlog items closed (built or DONE-BY-DESIGN) across 3 working days.
**Rate:** ~10 items/day — not sustainable, but reflective of a cold-start project where the SQL layer, Flutter rewrite, auth, RLS, and test harness all landed in one compressed burst.

**Trend:** n/a — no prior week to compare against. This is the baseline.

**Expected next week:** single-digit item count. Pilot distribution, rep training, and field feedback will dominate. Expect backlog growth (pilot learnings) to outpace backlog closure, which is healthy at this stage.

---

## Recommendations (opinionated)

1. **Do not start new P1 work.** P1-1/2/3 are speculative polish. Ship the pilot, let real usage drive priority.
2. **Upgrade service-role key storage to a password manager TODAY.** Prod went live this morning — that is the documented hard trigger. This is ~10 minutes of work and removes a credential at rest on a laptop.
3. **Toggle Prod Auth settings (phone-ON / SMS-OFF / signup-OFF / 2FA) before building the release APK.** If you ship APK first and toggle later, any accidental signup window is permanent in `auth.users`.
4. **Commit the `.coderabbit.yaml` + `.github/REVIEW_CONTEXT.md` work to `main` and install the GitHub App** before the first pilot PR lands. The agent only adds value on PRs opened after installation.
5. **Frame the Day 2–4 of pilot distribution as a narrow checklist (already exists in `docs/PILOT-DEPLOYMENT-CHECKLIST.md`).** Do not let scope creep in.
6. **Close the PDPL legal thread in writing this week.** The longer it stays in "monitor" mode, the higher the risk it bites you right before the pilot goes live. A one-line email confirmation from counsel is cheap insurance.
7. **Prepare a "pilot ops log"** (simple daily markdown) for the pilot window — crashes, login failures, trigger rejections, NID reveals. Feeds next week's retro.

---

## File map (this week's new/changed)

- `supabase/migrations/001_schema.sql` → `015_*.sql` (15 migrations)
- `lib/` — full rebuild of auth + lead + merchant flows, merchant list/profile screens, providers, RTL wrapping
- `scripts/provision_rep.sh`, `scripts/reset_password.sh`, `.env.admin.example`
- `scripts/test/d1_rls_tests.sql`, `d2_dedup_race_test.sql`, `d3_trigger_fixtures.sql`, `run_sql.sh` (gitignored)
- `docs/P0-IMPLEMENTATION-GUIDE.md`, `P0-DASHBOARD-RUNBOOK.md`, `P0-TEST-MATRIX.md`, `PILOT-DEPLOYMENT-CHECKLIST.md`, `DAY1-EXECUTION-PLAN.md`
- `.coderabbit.yaml`, `.github/REVIEW_CONTEXT.md`
- `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `android/key.properties.example`
- `CLAUDE.md`, `CLAUDE.archive.md`
