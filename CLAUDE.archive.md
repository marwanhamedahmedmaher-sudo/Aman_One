# Aman Sales App — Session Log Archive

Session log entries rotated out of `CLAUDE.md`. Newest first within this file.

---

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

---

### Session: 2026-04-14 — Project state restructure
**Duration:** ~15m
**Focus:** Splitting project docs for better token efficiency.
**Completed:**
- Moved static reference (tech stack, architecture, commands, conventions) to `ARCHITECTURE.md`
- Rewrote `CLAUDE.md` to hold only dynamic state (backlog, blockers, session log, velocity)
**Decisions:**
- CLAUDE.md capped at ~80 lines steady-state; session log rotates at 5 entries
- ARCHITECTURE.md is stable reference — only re-read when touching code
**Next Session:**
- Seed backlog with real P0/P1/P2 tasks from current prototype status
