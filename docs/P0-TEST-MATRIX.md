# P0 Test Matrix

## D1. RLS Test Matrix
- [ ] Create 2 reps (A, B) + 1 admin via Supabase Dashboard
- [ ] Rep A inserts a lead -> visible to Rep A
- [ ] Rep B queries leads -> cannot see Rep A's lead
- [ ] Admin queries leads -> sees all leads
- [ ] Unauthenticated request -> zero rows
- [ ] Rep A tries to update Rep B's lead -> rejected
- [ ] Admin updates any lead -> succeeds

## D2. Dedup Race Test
- [ ] Two concurrent inserts with same National ID -> exactly one succeeds
- [ ] Failed insert surfaces Arabic error "هذا الرقم القومي مسجل بالفعل"
- [ ] Same National ID with different formatting (spaces, dashes) -> still caught as duplicate

## D3. Trigger Fixture Tests
- [ ] Phone trigger: valid Egyptian mobile (010, 011, 012, 015 prefixes) -> stored as E.164
- [ ] Phone trigger: invalid phone -> hard-reject with "رقم الموبايل غير صحيح"
- [ ] NID trigger: valid 14-digit Egyptian ID -> hash computed, insert succeeds
- [ ] NID trigger: invalid ID (wrong century, bad month, bad gov code) -> hard-reject with "رقم القومي غير صحيح"
- [ ] NID trigger: duplicate ID -> unique constraint violation on national_id_hash

## D4. Biometric Tests
- [ ] Device without fingerprint sensor -> biometric option not shown
- [ ] User enables biometric -> credentials stored in secure storage
- [ ] Biometric auth succeeds -> auto-login
- [ ] Biometric auth fails -> falls back to phone+password
- [ ] User denies biometric permission -> graceful fallback

## D5. End-to-End Flow
- [ ] Admin provisions rep in Dashboard (phone + temp password + must_change_password=true)
- [ ] Admin sends temp password via email + WhatsApp
- [ ] Rep opens app -> enters phone -> enters temp password -> forced to change password
- [ ] Rep sets new password -> lands on home screen
- [ ] Rep taps "تسجيل عميل جديد" -> lead form opens
- [ ] Rep fills name, phone, national ID, notes -> submits
- [ ] Lead appears in Supabase Table Editor
- [ ] Rep tries duplicate National ID -> Arabic error shown
- [ ] Admin runs export snippet -> CSV contains the lead with Arabic headers
- [ ] Rep logs out -> biometric prompt on next launch (if enabled)

## D6. Pre-Pilot Checklist
- [ ] 2FA enabled on all Supabase Dashboard accounts
- [ ] Dashboard member list <= 2 people
- [ ] Runbook distributed to admin(s)
- [ ] All P0 items marked DONE in CLAUDE.md
- [ ] No hardcoded secrets in codebase (SUPABASE_URL and SUPABASE_ANON_KEY use --dart-define)
- [ ] flutter analyze passes with 0 issues
- [ ] Arabic text renders correctly on Android and iOS
