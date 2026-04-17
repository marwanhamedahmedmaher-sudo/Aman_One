# Aman Pilot Readiness — What Ships Now, What Phases Later

**Purpose:** Strategic one-pager. Use `PILOT-DEPLOYMENT-CHECKLIST.md` for operational line-items; this file answers *"what must we do before April 19, and what can wait?"*

**Pilot window:** April 16 → April 19, 2026 (3 working days left).
**Scope:** 20–50 reps, direct APK sideload, Android only.
**Guiding principle:** Anything that isn't a pilot-blocker is phase-later. Don't add surface area.

---

## 🟥 MUST DO BEFORE PILOT (April 16 → 19)

Ordered by day. Each item has an **owner**: `Marwan` (manual), `Claude-assisted`, or `done`.

### Day 1 (today, April 16 — evening)

1. **Prod Supabase Dashboard auth config** — `Marwan` (manual, 5 min in Dashboard) — **DONE 2026-04-16**
   Phone provider ON, SMS provider UNCONFIGURED, "Allow new users to sign up" OFF, 2FA on all admin accounts. **This was the single biggest pilot-breaking risk.** Confirmed by Marwan. Documented in `P0-DASHBOARD-RUNBOOK.md`.
2. **Generate release keystore** — `Marwan` (manual with `keytool`) → backup strategy. — **DONE 2026-04-16**
   RSA 4096, 10k-day validity, alias `aman`, at `C:\Users\marwan.haahmed\aman-release.jks`. Backup pattern: encrypted 7z + cloud + USB, password memorized. **Password-manager upgrade deferred to post-pilot** (see P2-7 in CLAUDE.md).
3. **Create `android/key.properties`** from `android/key.properties.example`. — **DONE 2026-04-16**
   Forward-slash Windows path wired, passwords substituted, gitignored via `android/.gitignore:12` + root `.gitignore` catches `*.jks`.
4. **Install CodeRabbit GitHub App** on the repo — `Marwan` (2 min at https://github.com/apps/coderabbitai). — **TODO**

### Day 2 (April 17) — Build + Audit

5. **Build release APK** with prod `--dart-define` credentials — `Claude-assisted`.
6. **Decompile APK + grep for leaked secrets** — `Claude-assisted`. Only `SUPABASE_ANON_KEY` should be present. Any `service_role` hit is pilot-blocking.
7. **Pre-pilot Claude Code audit** against `.github/REVIEW_CONTEXT.md` — `Claude-assisted`. One-shot deep audit on `main`. ~30 min. Catches cross-file issues CodeRabbit's diff view misses.
8. **Fix anything either scan surfaces.** Do not defer security findings to post-pilot.

### Day 3 (April 18) — Test + Provision

9. **Functional smoke on 2 physical Android devices** (Android 10+) — `Marwan`. Full auth → lead → merchant list → reveal NID → logout flow. Checklist: `PILOT-DEPLOYMENT-CHECKLIST.md` §2A–2D.
10. **Security smoke test** — `Marwan` with `Claude-assisted` scripts. RLS cross-rep isolation, anon lockout, NID reveal audit row written, no plaintext NID in APK. Checklist: §3A–3D.
11. **Provision rep accounts on prod** — `Marwan` via `scripts/provision_rep.sh`. Temp passwords → password manager + tracking sheet.
12. **Admin runbook rehearsal** — `Marwan` does one end-to-end pass: create rep, suspend, reset password, export CSV. If any step fails, fix runbook before sending APK out.

### Day 4 (April 19) — Rollout

13. **Canary to 5 reps** — verify install, first login, password change, one lead each.
14. **Full rollout** — if canary is clean, send to remaining reps. Watch `audit_log` for 2 hours.

---

## 🟨 PHASE 2 — Week 1-2 post-pilot (April 20 → May 3)

Activated only after pilot is running and you have real failure modes to inform priority.

### Quality / safety nets that are "nice on Day 1, essential by Day 30"

- **Crash reporting (Sentry or Firebase Crashlytics).** You are currently blind to client-side crashes. Acceptable on Day 1 with 20 reps; untenable past that.
- **Integration tests with `integration_test` + Patrol.** Target the biometric flow, login rotation, and lead submission. Don't try for coverage — target the flows that actually regress.
- **Manual P1 backlog items** that were deprioritized for pilot:
  - P1-1 (client-side NID format validation — redundant with server, but better UX)
  - P1-2 (soft delete for merchants — preserves dedup history when admin "deletes")
  - P1-3 (Excel/xlsx export option alongside CSV)
- **Proper app icon** (currently deferred — brand artwork pending).
- **ProGuard / R8 obfuscation** on release builds. Reduces APK size and makes decompile harder.
- **Pilot retrospective** — what broke, what was confusing, what reps asked for. Drives P1/P2 re-ranking.

### Dev-loop hardening

- **CodeRabbit tuning.** After 5-10 real PRs, downgrade any over-triggered gate from `error` to `warning`. Assertive profile is intentional over-report; calibrate down.
- **CI pipeline.** Today you build APKs locally. GitHub Actions workflow that runs `flutter analyze` + `flutter test` on every PR is a 1-hour setup.
- **Second admin on Dashboard.** If anyone else needs to provision reps, switch `scripts/provision_rep.sh` to source the service-role key from `op` / `bw` (documented trigger in CLAUDE.md Current Decisions).

---

## 🟦 PHASE 3 — Post-POC evolution (month 2+)

Activated when pilot graduates from "prove the concept" to "productionize for scale." Do NOT pre-build these before there's a business signal they're needed.

- **P2-6: Full merchant profile + KYC images.** Re-activates former P0-8 + P1-5. Image capture, Storage bucket with RLS, compression, reveal-with-audit for images. This is the biggest scope expansion on the backlog — re-plan from scratch based on pilot learnings.
- **P2-5: Business merchant support** (commercial registration as a second document type). Adds `document_type` column and validation trigger branch.
- **P2-1: Fuzzy dedup** on name + phone (Postgres `pg_trgm` / Levenshtein). Warn, don't hard-reject.
- **P2-2: Bulk CSV import** for admin (upload existing spreadsheet).
- **P2-3: Per-rep quota dashboard** widget on home screen.
- **P2-4: Offline lead draft queue** — only if field-rep use case is confirmed post-pilot.
- **In-app admin screens (Option B).** Graduate from Dashboard-only admin. Rep list, suspend, merchant filtering, export — all in-app.
- **Provisioning via Edge Function (Option C2).** Graduate from local script. Removes the service-role-key-on-laptop pattern entirely.
- **External KMS / client-side NID encryption.** Re-evaluate pending PDPL legal response. Current stack (Supabase Vault at rest) is POC-grade, not production-grade.
- **Data residency migration** (AWS Bahrain / on-prem) if PDPL Article 14 requires in-region storage.
- **Play Store internal track or Firebase App Distribution** for auto-updates. Replaces WhatsApp/Drive APK distribution.
- **Certificate pinning** on Supabase client. Defense against MITM on hostile networks.
- **Rate limiting** on auth endpoints (verify Supabase defaults; tighten if needed).

---

## ⬛ DESCOPED — DO NOT RESURRECT WITHOUT A BUSINESS TRIGGER

These were deliberate scope decisions for V1. Every one of them exists to keep the pilot shippable. Re-opening any of them should require a written scope change, not a passing conversation.

- **OTP / SMS flows.** Phone provider stays ON for phone-as-username; SMS provider stays OFF. Permanent V1 rule.
- **Public sign-up.** Admin-only provisioning, enforced at Auth layer.
- **English UI.** Arabic-only. RTL is a correctness requirement, not a preference.
- **In-app KYC image capture.** Lead capture only in V1. Downstream teams handle KYC via existing tools. This is the defining scope decision that makes the 4-day pilot possible.
- **In-app admin screens for V1.** Supabase Dashboard is the admin surface (Option A).
- **In-app self-serve forgot-password flow.** Admin-mediated via Dashboard reset + change-password screen.
- **Business-merchant onboarding (commercial registration).** Individuals only for V1.
- **Playwright / Espresso.** Wrong tools for Flutter (Flutter web renders to canvas; Flutter Android is a single FlutterView). Use `integration_test` + Patrol if automated tests are added post-pilot.

---

## Tooling stack reference (what's wired up)

| Tool | Role | Status |
|---|---|---|
| CodeRabbit | PR merge gate — diff-level, noise-light | **Config shipped (P1-12).** Needs GitHub App install to activate. |
| Claude Code | Deep pre-pilot audit — full-codebase, on-demand | One-shot run scheduled for Day 2 (April 17). |
| Manual APK smoke | Pilot safety net | Checklist: `PILOT-DEPLOYMENT-CHECKLIST.md` §2A–2D. |
| Supabase security advisors | DB lint — RLS, SECURITY DEFINER, search_path | Clean on prod as of 2026-04-16. Re-run before canary. |
| `flutter analyze` | Dart static analysis | Clean as of P1-9. Re-run before APK build. |

---

## Decision discipline during pilot week

1. **No new features** until canary is clean. Bug fixes only.
2. **No migrations on prod without a corresponding numbered SQL file in `supabase/migrations/`.** Every change reproducible from empty DB.
3. **No Dashboard access for anyone not on the admin list.** ≤2 people. 2FA mandatory.
4. **No merging bypassing CodeRabbit** once it's installed. If it's wrong, fix the config; don't override the gate.
5. **Every user-reported bug lands as a CLAUDE.md backlog row before it gets worked on.** Avoid untracked fixes.

---

*Last updated: 2026-04-16 (end of P1-12 session). Revise after canary rollout.*
