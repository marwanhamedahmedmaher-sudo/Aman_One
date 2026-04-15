# Aman Sales App (أمان) — Project State

Single source of truth for project status. Static reference (tech stack, architecture, commands, conventions) lives in `ARCHITECTURE.md`.

**Session rules:**
- Read this file at the start of every session.
- Update it at the end of every session.
- Never delete backlog items — mark `DONE` with date.
- Keep only the last 5 session log entries here; archive older entries to `CLAUDE.archive.md`.

---

## Current Decisions

- **Backend:** Supabase (Postgres + Auth + Storage + Edge Functions).
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

---

## Backlog

Status markers: `TODO` | `IN_PROGRESS` | `DONE` | `BLOCKED`

### P0 — Must Ship (pilot blockers)

| # | Task | Status | Assigned | Notes |
|---|------|--------|----------|-------|
| 1 | Supabase project setup (dev + prod) | TODO | — | Auth, Postgres, Storage, Edge Functions. Enable RLS on all tables. |
| 2 | Postgres schema: `users`, `merchants`, `audit_log` | TODO | — | `merchants.national_id` via Supabase Vault (pgsodium TCE). `merchants.national_id_hash text UNIQUE` plaintext for dedup. Columns: `name`, `phone`, `national_id` (Vault), `national_id_hash`, `notes`, `status`, `created_by`, `created_at`, `deleted_at`. No image columns (descoped for POC). |
| 3 | Role model: `sales_rep`, `admin` via custom claims | TODO | — | Set via SQL function, enforced in RLS policies. |
| 4 | Auth wiring: `signInWithPassword` + `must_change_password` flag | TODO | — | Existing screens in `lib/screens/auth/`. Remove mock OTP logic. |
| 5 | Prototype rework: remove OTP screen, adjust routing | TODO | — | ~0.5 days. Phone entry = login, not signup. Password screen = first-login rotation. |
| 6 | Biometric fast-path via `local_auth` package | TODO | — | Post-first-login opt-in prompt. Fallback to phone+password. |
| 7 | Lead registration: Postgres insert + National ID dedup | TODO | — | Insert into `merchants` (name, phone, national_id, notes, status). Trigger normalizes + validates + computes hash. UNIQUE(`national_id_hash`) catches dedup. Surface Arabic error on duplicate. No image uploads in POC. |
| 8 | ~~KYC image upload to Supabase Storage~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped from POC. Lead-capture-only scope — KYC handled by downstream systems. Revisit when Aman grows into full merchant profile (P2-6). |
| 9 | RLS policies: reps see own records, admins see all | TODO | — | Test with both roles. |
| 10 | ~~Admin screen: provision rep~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped. Provisioning via Supabase Dashboard Auth UI. See Dashboard runbook (P0-18). |
| 11 | ~~Admin screen: list reps, suspend/reactivate~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped. Use Dashboard "Ban user" toggle + `users.status` trigger sync. |
| 12 | ~~Admin screen: list merchants with filters~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped. Use Supabase Table Editor (filter/sort UI, no SQL). |
| 13 | ~~CSV + Excel export via Edge Function~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped. Replaced by saved SQL snippets (P0-17). |
| 14 | Audit log triggers (rep actions only) | TODO | — | Rep-side actions → `audit_log`. Admin actions logged by Supabase Dashboard for V1. |
| 15 | Testing + hardening | TODO | — | RLS test matrix, dedup race test, biometric fallback, phone/National-ID trigger tests. |
| 16a | Phone normalization & format trigger | TODO | — | Postgres trigger on `auth.users` — strip non-digits, normalize to E.164 (`+20xxxxxxxxxx`), **hard-reject** malformed Egyptian mobile (must be 11 digits starting with `01`) with Arabic error `رقم الموبايل غير صحيح`. Unblocked. |
| 16b | National ID normalization & format trigger | TODO | — | Postgres trigger on `merchants` — validate Egyptian 14-digit National ID: structural rules (century digit, YYMMDD birthdate, governorate code 01–35 or 88, serial, checksum). **Hard-reject** with Arabic error `رقم القومي غير صحيح`. Compute SHA-256 → `national_id_hash` for dedup. Scope: **individuals only** for V1. |
| 17 | Saved SQL snippets for admin exports | TODO | — | 3–4 snippets in Supabase SQL Editor: all active merchants, last 30 days, by rep, full audit dump. Arabic column headers, joined rep names, hide internal columns. One-click CSV download. |
| 18 | Dashboard operator runbook (Arabic + English) | TODO | — | 1-pager covering: create rep, suspend rep, reset password, run export snippet, access 2FA setup. Distributable to any future admin. |
| 19 | Change-password screen (logged-in user) | TODO | — | Flutter screen: current password + new password + confirm. Calls `auth.updateUser({ password })`. Serves first-login rotation (`must_change_password`), voluntary rotation, and post-admin-reset rotation. |

### P1 — Should Ship (pilot quality)

| # | Task | Status | Assigned | Notes |
|---|------|--------|----------|-------|
| 1 | National ID format validation | TODO | — | Client regex + server check. Egypt-specific rules TBD. |
| 2 | Soft delete for merchants | TODO | — | `deleted_at` column. Preserves dedup history. |
| 3 | Excel (.xlsx) export option | TODO | — | Alongside CSV. |
| 4 | Forgot password flow (admin-mediated) | DONE-BY-DESIGN 2026-04-14 | — | Rep messages admin → admin resets in Supabase Dashboard → rep rotates via change-password screen (P0-19). No in-app self-serve flow for V1. |
| 5 | ~~Image compression before upload~~ | DONE-BY-DESIGN 2026-04-14 | — | Descoped — no image uploads in POC. Revisit with P2-6 (full merchant profile + KYC). |
| 6 | UI masking + reveal-with-audit for National ID | TODO | — | Merchant detail screen shows `********1234` by default. Explicit "Reveal" button → full ID displayed + writes `national_id_revealed` entry to `audit_log`. Dependency: merchant profile screen must exist first (post-POC). |

### P2 — Nice to Have

| # | Task | Status | Assigned | Notes |
|---|------|--------|----------|-------|
| 1 | Fuzzy dedup on name + phone | TODO | — | Postgres trigram / levenshtein. Warn on likely duplicate. |
| 2 | Bulk CSV import (admin) | TODO | — | Upload existing spreadsheet. |
| 3 | Per-rep quota dashboard | TODO | — | Home screen widget. |
| 4 | Offline lead draft queue | TODO | — | If field-rep scenario confirmed post-pilot. |
| 5 | Business merchant support (commercial registration) | TODO | — | Add `document_type` column (`national_id` \| `commercial_reg`), extend validation trigger with commercial-registration format. Deferred from V1 scope decision 2026-04-14. |
| 6 | Evolve beyond lead capture — full merchant profile + KYC | TODO | — | Post-POC evolution: KYC image capture (ID front/back, selfie), storage bucket with RLS, image compression, full merchant profile screen, reveal-with-audit pattern. Re-activates former P0-8 + P1-5. Scope to be re-planned after pilot learnings. |

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

### Session: 2026-04-14 (EOD) — Phase 1 scope match to Figma + P0 implementation guide
**Duration:** ~30m
**Focus:** Align Phase 1 build scope exactly to the Figma reference flow. Produce a step-by-step P0 implementation guide. Confirm hard-reject for National ID. Resolve remaining blockers.
**Completed:**
- Read current Flutter code end-to-end (`main.dart`, `auth_provider.dart`, all auth screens, merchant 3-step flow, `Merchant` model).
- Produced code-level gap analysis: current state vs. target POC flow. Identified 12 concrete deltas across routing, auth provider, merchant model/flow, and dependency cleanup.
- Wrote **`docs/P0-IMPLEMENTATION-GUIDE.md`** — 4-phase build order (A backend SQL, B Flutter auth, C lead capture rework, D testing) with dependency graph, time estimates, and acceptance criteria per step.
- Downgraded MENA data residency from 🚩 CRITICAL to monitoring-only per Marwan. No longer flagged each session.
- Resolved temp-password delivery channel blocker: email + WhatsApp, admin sends manually. Decision promoted into Current Decisions.
- Confirmed **hard-reject** behavior for malformed phone and National ID at DB trigger level. Updated Current Decisions + P0-16a/b notes accordingly.
- Flagged that visual Figma verification could not happen in-session (Figma JS prototype not renderable via WebFetch; Chrome extension offline; no Flutter SDK in sandbox). Guide includes explicit verification step for user.
**Decisions:**
- **Phase 1 scope locked** to: phone → password → (change-password if flagged) → home → single-screen lead form. Captured in Current Decisions with Figma link.
- **Hard-reject** confirmed for trigger validation. Arabic errors: `رقم الموبايل غير صحيح` / `رقم القومي غير صحيح`.
- **Residency** treated as monitoring-only going forward; will not be re-flagged session-to-session until legal responds.
- **Phase A (Postgres SQL) can proceed in parallel** with Phase B/C (Flutter rewrite) — portable SQL, deployable once P0-1 unblocks.
**Backlog impact:** No new items; existing P0 items gain a concrete dependency-ordered build plan in the guide.
**Blockers now:** 0 active.
**Next Session:**
- Kick off Phase A: draft P0-16a + P0-16b SQL as a single paste-ready file with test fixtures (now unblocked with hard-reject confirmed).
- In parallel, draft P0-2 schema SQL (includes Vault setup for `national_id` + `national_id_hash` UNIQUE).
- User to do visual pass on Figma prototype against the guide's target flow; flag any screen the guide missed.

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

### Session: 2026-04-14 (PM) — Merchant identity scope + data residency elevation
**Duration:** ~20m
**Focus:** Resolve National ID spec blocker; clarify what "normalization trigger" means; elevate data residency risk before next build session.
**Completed:**
- Explained the concept chain: National ID spec → what a Postgres trigger does → why one blocks the other. User now understands the validator can't be written until the ID format is nailed down.
- Locked V1 merchant identity scope: **Egyptian individuals only**, 14-digit National ID. Businesses / commercial registration deferred to post-pilot.
- Split P0-16 into 16a (phone, unblocked) and 16b (National ID, now unblocked). Both buildable immediately.
- Walked through the Egyptian 14-digit structural rules (century digit, YYMMDD, governorate code, serial, checksum) that the 16b trigger will enforce.
- Elevated **MENA data residency** blocker: marked CRITICAL, tied explicitly to PDPL Law 151/2020 Article 14, noted it blocks P0-1 and could push project setup by 2–6 weeks if in-region hosting is required.
**Decisions:**
- **Merchant identity scope (V1):** Egyptian individuals only (14-digit National ID). Added to Current Decisions.
- **P2-5 added:** Business merchant support via commercial registration, explicitly deferred.
- **National ID blocker resolved** — struck through in Blockers table with resolution note.
- **Next build:** draft 16a and 16b trigger SQL with paired test blocks and Arabic error messages.
**Open questions flagged for next session:**
- Hard-reject vs. flag-and-save behavior for bad National ID (recommending hard-reject).
- Whether to prevent a rep from entering their own ID as a merchant's (2-line addition to trigger).
- Data residency answer from legal — drives whether P0-1 can even start on Supabase hosted infra.
**Blockers now:** 2 active (data residency 🚩 critical, temp-password channel). Was 3.
**Next Session:**
- Draft P0-16a phone trigger SQL + tests.
- Draft P0-16b National ID trigger SQL + tests (pending hard-reject confirmation).
- One-page setup note for pasting into Supabase SQL Editor.
- Await legal response on PDPL before touching P0-1.

### Session: 2026-04-14 — Admin provisioning model locked (Option A + mitigations)
**Duration:** ~30m
**Focus:** How admin creates/manages users on Supabase. Evaluated 3 approaches (Dashboard-only, in-app admin + Edge Function, separate web portal) with benefit/effort/scope scoring.
**Completed:**
- Compared Options A (Dashboard), B (in-app admin + Edge Function), C (separate web portal).
- Walked through Option A's operator UX for a non-SQL admin: Auth UI for provisioning, Table Editor for listing, saved SQL snippets for CSV export (3 clicks, no SQL typed after setup).
- Identified two risks with Option A and designed mitigations: (1) phone/National-ID format drift → normalization + format triggers on write; (2) no self-serve forgot password → admin-mediated reset paired with in-app change-password screen.
- Rejected the "post-insert dedup job" idea in favor of write-time normalization triggers (prevents bad data vs. detecting it).
**Decisions:**
- **Option A locked for pilot.** Admin workflow lives entirely in Supabase Studio. No in-app admin screens in V1.
- **Descoped 4 P0 items:** P0-10, P0-11, P0-12, P0-13 marked DONE-BY-DESIGN. Descoped P1-4 (forgot password).
- **Added 4 new P0 items:** P0-16 (normalization triggers), P0-17 (saved SQL export snippets), P0-18 (Dashboard runbook), P0-19 (change-password screen).
- Net backlog impact: ~4–6 days of build effort removed; ~1–1.5 days added. Pilot scope lighter by ~3–5 days.
- Graduation path: revisit Option B (in-app admin + Edge Function) after pilot if multi-admin or richer audit is required.
**Accepted gaps (pilot-only):**
- Admin actions not captured in in-app `audit_log` — Supabase Dashboard logs are the system of record for admin activity in V1.
- Anyone with Supabase project access is effectively super-admin. Mitigated by keeping member list tight (1–2 people) and requiring 2FA.
- Rep locked out after-hours if admin unreachable — acceptable for sales team with WhatsApp access to manager.
**Next Session:**
- Resolve 2 remaining blockers: data residency, temp-password delivery channel. National ID spec now also blocks P0-16.
- Draft P0-16 trigger SQL (phone normalization) — does not require National ID spec to start; can ship phone half first.
- Draft P0-17 export snippets (starter set of 3) and P0-18 runbook skeleton.
- Decide whether to kick off P0-1 (Supabase project setup) before or after data-residency blocker resolves.

### Session: 2026-04-14 — Backend decision + auth architecture
**Duration:** ~90m
**Focus:** Backend choice (Firebase vs Supabase vs hybrid), auth flow, SMS provider, cost optimization.
**Completed:**
- Ran 3-agent war room (Firebase advocate, Supabase advocate, reviewer) against the Figma prototype at https://kale-wired-82468678.figma.site.
- Evaluated hybrid Firebase Auth + Supabase data pattern — rejected (doesn't solve OTP-once-then-password, adds sync complexity).
- Evaluated SMS providers (Twilio, MessageBird, Unifonic) and WhatsApp OTP via Meta Business Authentication templates.
- Identified that app is **sales-reps-only** (not merchant-facing), which eliminates consumer auth requirements entirely.
**Decisions:**
- **Backend: Supabase.** Postgres UNIQUE constraint on National ID, RLS for admin gating, PostgREST for CSV export, native `signInWithPassword`.
- **Auth: admin-provisioned accounts. No OTP. No SMS.** Rep auth = phone + password with biometric fast-path. Forgot password = admin-mediated reset.
- **Merchants are records, not users.** Identity verification happens via rep in-person onboarding + KYC images, not via phone OTP on the merchant.
- Eliminates Twilio setup, NTRA Egypt sender ID registration (1-4 week calendar blocker), Meta WhatsApp approval, and ~$300-1,400/year SMS cost.
- Admin UX stays in-app for pilot; extract to web portal post-pilot.
**In Progress:**
- —
**Next Session:**
- Resolve 3 open blockers (data residency, temp-password channel, National ID spec).
- Decide: draft Postgres schema as a concrete first pass (P0-2) to react to, OR wait until blockers resolve. Open question left with Marwan at end of session.
- Kick off P0-1 (Supabase project setup) once region is confirmed.

---

## Weekly Velocity

| Week       | Completed | Remaining | Blockers | Tasks/Week |
|------------|-----------|-----------|----------|------------|
| 2026-W16   | 6 (by design) + 2 blockers resolved + 1 downgraded | 25        | 0 active | —          |
