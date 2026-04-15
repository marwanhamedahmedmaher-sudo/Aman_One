# P0 Implementation Guide — Phase 1 (Pilot POC)

**Date:** 2026-04-14
**Scope:** Step-by-step to bring the current Flutter prototype in line with the locked POC decisions and the Figma reference flow at https://kale-wired-82468678.figma.site.
**Target:** Lead-capture-only sales rep app, Supabase-backed, no OTP, no KYC images.

---

## ⚠️ Visual Verification Required

I could not render the Figma prototype in this session (JS-rendered; no Chrome extension connected; no Flutter SDK in sandbox). This guide is built from:
1. The locked decisions in `CLAUDE.md` (session logs 2026-04-14 x3).
2. The current Flutter code under `lib/`.
3. Standard fintech sales-rep POC patterns.

**Before starting work, you must visually verify the Figma against the target flow below.** If the Figma shows something different (e.g., it still includes OTP screens or 3-step KYC), update this doc before coding. The Figma is the design source of truth; CLAUDE.md captures the product decisions.

To compare live: run `flutter run -d chrome` on the app locally and open the Figma in an adjacent Chrome tab.

---

## Target Flow (Phase 1)

```
[Phone entry] → [Password]          → [Home]  (returning rep, normal path)
[Phone entry] → [Password (temp)]   → [Change password]  → [Home]  (first login / after admin reset)
[Home]        → [Biometric prompt]  → [Home]  (opt-in after first successful login)
[Home]        → [New lead form]     → [Success] → [Home]
```

**Explicitly NOT in Phase 1:**
- OTP screen (any variant)
- First-time signup flow — accounts are admin-provisioned in Supabase Dashboard
- KYC image upload (personal photo, national ID front/back)
- 3-step merchant registration
- Business info fields (business type, address, region, postal code)
- Financial fields (bank, account number, IBAN)
- In-app admin screens (rep list, merchant list, CSV export)

---

## Current vs Target — Gap Analysis

| Area | Current State (code) | Target State (POC) | Action |
|------|----------------------|---------------------|--------|
| Auth routing | `main.dart` routes phone→OTP (first-time) or phone→password | phone→password always; password screen handles `must_change_password` flag | Remove OTP branch |
| OTP screen | `otp_screen.dart` exists, mock code `123456` | Deleted | **Delete** file + all imports |
| Set-password screen | `set_password_screen.dart` used post-OTP | Replaced by change-password screen invoked from `must_change_password` flag | **Rename + rewire** as change-password screen |
| Forgot password | `forgot_password_screen.dart` in-app flow | Admin-mediated reset via Supabase Dashboard; in-app screen just shows "contact your admin" message | **Simplify** to static help screen |
| Biometric | Not wired | `local_auth` opt-in after first successful login; fallback to phone+password | **Build** (P0-6) |
| Auth provider | `_mockOtp`, `_mockUsers`, `verifyOtp`, `checkPhone` | `signInWithPassword` via Supabase client | **Replace** mock layer |
| Merchant model | `Merchant` has photo paths, business fields, bank fields | Lead: `name`, `phone`, `nationalId`, `notes`, `status` | **Strip** to lead shape |
| Merchant flow | 3-step registration with image pickers | Single-screen lead form | **Collapse** to one screen |
| Merchant provider | Multi-step state, image handling | Simple form state + insert | **Simplify** |
| Supabase client | Not integrated | `supabase_flutter` SDK, env config | **Add** dependency + init |
| RLS | N/A | Policies enforce rep sees own leads; admin sees all | **SQL** in Supabase |
| Dedup | N/A | Trigger computes `national_id_hash`; UNIQUE constraint | **SQL** (P0-16b) |
| Format validation | N/A | Postgres triggers (phone E.164, Egyptian 14-digit National ID) | **SQL** (P0-16a + P0-16b) |
| Audit log | N/A | Rep actions written to `audit_log` table | **SQL** + client hook |

---

## Step-by-Step P0 Build Order

Each step is ordered by dependency. Check off as you go.

### Phase A — Backend foundation (Supabase SQL, portable — does not require project provisioning)

**A1. Draft Postgres schema (P0-2)**
- File: `supabase/migrations/001_schema.sql`
- Tables: `auth.users` (Supabase built-in) + public `users` profile, `merchants`, `audit_log`
- `merchants` columns: `id uuid PK`, `name text`, `phone text`, `national_id text` (Vault-encrypted via pgsodium TCE), `national_id_hash text UNIQUE`, `notes text`, `status text default 'lead'`, `created_by uuid FK`, `created_at timestamptz`, `deleted_at timestamptz`
- No image columns.
- Acceptance: schema lints cleanly; can be pasted into Supabase SQL Editor.

**A2. Write P0-16a — phone normalization trigger**
- Trigger on `auth.users` insert/update.
- Strip non-digits from phone; enforce 11-digit Egyptian mobile starting `01`; store as E.164 (`+20XXXXXXXXXX`).
- **Hard-reject** invalid input with Arabic error: `رقم الموبايل غير صحيح`.
- Test block with 6 fixtures (3 valid, 3 invalid).

**A3. Write P0-16b — National ID normalization trigger**
- Trigger on `merchants` insert/update.
- Validate Egyptian 14-digit National ID: century digit (2 or 3), YYMMDD birthdate, governorate code (01–35 or 88), 4-digit serial, checksum.
- **Hard-reject** invalid input with Arabic error: `رقم القومي غير صحيح`.
- Compute SHA-256 of normalized ID → `national_id_hash`.
- Test block with 8 fixtures (4 valid, 4 invalid across each structural rule).

**A4. Enable Supabase Vault on `merchants.national_id`**
- Enable pgsodium extension.
- Configure Transparent Column Encryption (TCE) on `national_id` column.
- Verify ciphertext at rest via raw table read; plaintext on authorized RLS read.

**A5. Write RLS policies (P0-9)**
- `merchants` SELECT: rep → `auth.uid() = created_by`; admin → all.
- `merchants` INSERT: authenticated reps only, `created_by = auth.uid()` enforced.
- `merchants` UPDATE: rep → own + status not final; admin → all.
- `audit_log` INSERT: any authenticated; SELECT: admin only.
- Test matrix: rep A cannot see rep B's merchants; admin sees all; unauthenticated sees nothing.

**A6. Write audit triggers (P0-14)**
- Trigger on `merchants` insert/update/delete → writes row to `audit_log` with actor, action, before/after diff.

**A7. Write saved SQL export snippets (P0-17)**
- Snippet 1: All active leads (last 90 days) — joined with rep name, Arabic headers.
- Snippet 2: Leads created in last 30 days.
- Snippet 3: Leads grouped by rep with counts.
- Snippet 4: Full audit dump for a date range.
- Test: each runs in <2s on seed data; CSV export produces clean UTF-8 with Arabic.

**A8. Write Dashboard runbook (P0-18)**
- Sections: Create rep, Suspend/reactivate rep, Reset rep password (→ new temp password → **send manually via email + WhatsApp**), Run export snippet, 2FA setup.
- Arabic + English.
- Target: distributable 1-pager, non-SQL admin can follow.

**Blocked by:** Supabase project provisioning (P0-1) — still monitoring residency. A1–A8 are all portable SQL / docs; draftable now, deployable when P0-1 clears.

---

### Phase B — Flutter auth layer

**B1. Add Supabase SDK**
- `pubspec.yaml`: `supabase_flutter: ^2.x`, `local_auth: ^2.x`, `flutter_secure_storage: ^9.x`.
- `main.dart`: `Supabase.initialize(url, anonKey)` before `runApp`.
- Env config via `--dart-define` (dev / prod URLs + anon keys, no secrets in repo).

**B2. Rewrite `auth_provider.dart`**
- Remove: `_mockOtp`, `_mockUsers`, `_defaultNewUser`, `verifyOtp`, mock `checkPhone` logic.
- Replace `login` with:
  ```dart
  Future<AuthResult> signIn(String phone, String password) async {
    final res = await supabase.auth.signInWithPassword(
      phone: _toE164(phone),
      password: password,
    );
    _user = await _loadProfile(res.user!.id);
    final mustChange = res.user!.userMetadata?['must_change_password'] == true;
    return AuthResult(success: true, mustChangePassword: mustChange);
  }
  ```
- Add: `changePassword(newPassword)` → `supabase.auth.updateUser` + clears `must_change_password` flag.
- Add: `signInWithBiometric()` → pull cached credentials from secure storage, call `signInWithPassword`.

**B3. Rewire `phone_entry_screen.dart`**
- Remove: branching on `isFirstTime` → OtpScreen.
- Always navigate to `PasswordScreen` on continue.
- Keep phone validation client-side (length check); server trigger is authoritative.

**B4. Rewire `password_screen.dart`**
- On successful `signIn`, check `mustChangePassword`:
  - True → push `ChangePasswordScreen` (replaces the screen).
  - False → push `MainShell`.

**B5. Build `change_password_screen.dart` (P0-19)**
- Adapt from existing `set_password_screen.dart`.
- Fields: current password (pre-filled if coming from login, required if voluntary), new password, confirm.
- On submit: `supabase.auth.updateUser(password: newPw)` + update `must_change_password = false` in user metadata.
- On success → `MainShell`.

**B6. Simplify `forgot_password_screen.dart`**
- Replace flow with static screen: "Contact your admin to reset your password" + admin contact info.
- Remove any OTP/email flow.

**B7. Delete dead code**
- Delete: `lib/screens/auth/otp_screen.dart`, `lib/screens/auth/set_password_screen.dart`, `lib/widgets/otp_input.dart` (if unused elsewhere).
- Run `flutter analyze` to catch orphaned imports.

**B8. Biometric fast-path (P0-6)**
- After successful first password login, prompt: "Enable biometric login?"
- On opt-in: store phone + encrypted password reference in `flutter_secure_storage`.
- On app launch: if credentials cached, show biometric prompt → on success, skip to MainShell; on fail, fall back to phone+password.
- Test: fallback works when biometric hardware absent / user denies.

---

### Phase C — Lead capture rework

**C1. Strip `models/merchant.dart`**
- Remove: `personalPhotoPath`, `nationalIdFrontPath`, `nationalIdBackPath`, `businessType`, `address`, `region`, `postalCode`, `bankName`, `accountNumber`, `ibanNumber`.
- Add: `nationalId` (text), keep `name`, `phone`, `notes`, `status`, `submittedAt`.
- Rename class to `Lead` (optional; keeps naming honest with POC scope).
- Update `toJson`/`fromJson` accordingly.

**C2. Simplify `merchant_provider.dart`**
- Remove: multi-step state (`currentStep`, `nextStep`, `previousStep`), image setters.
- Add: `submit()` → insert into Supabase `merchants` table; on unique-constraint violation (duplicate `national_id_hash`), surface Arabic error `هذا الرقم القومي مسجل بالفعل`.

**C3. Collapse merchant registration to single screen**
- Delete: `step1_identity_screen.dart`, `step2_business_info_screen.dart`, `step3_financial_screen.dart`, `merchant_registration_screen.dart`, `widgets/step_indicator.dart`.
- Create: `lib/screens/lead/new_lead_screen.dart` with 4 fields (name, phone, national ID, notes) + submit button.
- Client-side validation mirrors server triggers (fast feedback); server is authoritative.
- On success → `RegistrationSuccessScreen` (rename to `LeadSuccessScreen`) → pop to Home.

**C4. Remove image_picker dependency**
- `pubspec.yaml`: remove `image_picker`.
- `flutter pub get`.

---

### Phase D — Testing & hardening (P0-15)

**D1. RLS test matrix**
- Script: create two reps + one admin. Insert merchants as rep A. Verify rep B cannot see, admin can, unauthenticated gets zero rows.

**D2. Dedup race test**
- Script: two concurrent inserts with same National ID. Verify exactly one succeeds; the other surfaces Arabic error.

**D3. Trigger fixtures**
- Run all A2 + A3 fixture cases against deployed Supabase.

**D4. Biometric fallback test**
- Manually on a device without fingerprint sensor; on a device with denied permission.

**D5. Manual end-to-end**
- Provision a rep in Dashboard → temp password sent via email + WhatsApp → rep logs in → forced to change password → lands on home → creates a lead → duplicate National ID rejected → export snippet returns the row.

**D6. Checklist before pilot**
- 2FA enabled on all Supabase Dashboard accounts.
- Dashboard member list ≤ 2 people.
- Runbook distributed to admin(s).
- All P0 items marked DONE in CLAUDE.md.

---

## Dependency Graph (visual)

```
A1 (schema) ─┬─> A2 (phone trig) ──┐
             ├─> A3 (NID trig) ────┤
             ├─> A4 (Vault) ───────┼─> A5 (RLS) ──> A6 (audit)
             │                     │                  │
             │                     │                  └─> A7 (exports) ──> A8 (runbook)
             │                     │
B1 (SDK) ────┼─> B2 (auth prov) ──> B3,B4,B5,B6 (screens) ──> B7 (delete OTP) ──> B8 (biometric)
             │
C1 (model) ──┴─> C2 (prov) ──> C3 (screen) ──> C4 (remove img_picker)

All → D (test)
```

Phase A and Phase B/C are largely parallel. Phase A deploys when residency clears. Phase B/C builds against a local Supabase or mock client until then.

---

## Time Estimate (rough)

- Phase A: 2–3 days (most time in A5 RLS + A3 trigger math).
- Phase B: 2 days (B5 + B8 are the longest).
- Phase C: 0.5 day (mostly deletion).
- Phase D: 1–1.5 days.

**Total: 5.5–7 days** of focused build, assuming residency unblocks Phase A deployment.

---

## Open Items to Confirm Before Starting

1. **Figma visual verification** — open https://kale-wired-82468678.figma.site and confirm the flow above matches. Flag any screens this guide missed.
2. **Hard-reject confirmed for National ID** — ✅ confirmed 2026-04-14.
3. **Temp-password channel** — ✅ email + WhatsApp manual (confirmed 2026-04-14).
4. **Residency** — monitoring; does not block Phase A drafting.
