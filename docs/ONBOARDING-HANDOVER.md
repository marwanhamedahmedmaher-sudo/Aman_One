# Aman One — Unified Merchant Onboarding · Developer Hand-over

**Audience:** the developer team taking the onboarding prototype to production (real eKYC vendor, real document storage, normalized persistence).
**Status of the artifact being handed over:** working prototype on branch `ci/split-per-abi` (APK `v1.1.0-onboarding`). Demoable on emulator with a mock eKYC service. **Not** distributed to reps — prod reps run the simple lead form (`release/prod-simple`).
**This document contains:** (A) the optimized target flow, (B) the Figma design spec + link, (C) EPICs and INVEST user stories, (D) the integration map to real systems.

> One-line summary for the team: **the data model is already built and normalized; the work is (1) trimming the flow to 5 steps, (2) wiring the UI to the existing draft + `submit_application` RPC + Storage seams, and (3) swapping the mock eKYC for the real vendor behind the Edge Function.**

---

## Part A — Optimized Flow

### A.1 Current flow (what the prototype does today)

Source: [`card_application_wizard.dart`](../lib/screens/acceptance/card_application_wizard.dart) rendering [`card_application_spec.dart`](../lib/models/card_application_spec.dart).

For an Egyptian individual, one product → **7 steps**; all three products → **9 steps**:

| # | Step | Fields | Issue |
|---|------|--------|-------|
| 0 | Identity doc (nationality + customer-type toggles + ID/passport scan) | 2–3 | OK — decisions up front, OCR triggers here |
| 1 | Personal data | 8–10 (OCR-prefilled) | OK — a review screen in practice |
| 2 | Business & branch | **~16** | ⚠️ Overloaded; many optional EN-name/secondary-contact duplicates |
| 3 | Settlement / bank | 3 | ⚠️ Near-empty screen earns its own step |
| 4…n | One module **per product** | 2–4 each | ⚠️ Fans out; Acceptance + BP POS repeat device type/count/id |
| n+1 | Documents (deduped) | varies | OK |
| n+2 | Review & submit | — | OK |

**The friction is field density and step fan-out, not screen count per se.** Three levers fix it without dropping any data.

### A.2 Target flow — **5 steps, flat regardless of product count**

| # | Step | What changed | Rationale |
|---|------|--------------|-----------|
| 1 | **Start** — nationality + customer type + scan ID | unchanged | Decisions up front; OCR autofill happens here |
| 2 | **Confirm identity** — personal data | Present as a *review* of the scan; low-confidence OCR fields flagged | OCR makes this a confirm, not a typing step |
| 3 | **Business & settlement** | **Merge** the 3 settlement fields into business; collapse optional fields (EN names, secondary phones, EN address, sub-specialty) behind «**بيانات إضافية (اختياري)**» | Kills the 16-field wall and the empty settlement screen |
| 4 | **Products & documents** | **One** combined product screen for all selected products; **shared device block** (type/count/id) captured once for Acceptance+BP; deduped docs on the same screen | Removes per-product fan-out and the duplicate device entry |
| 5 | **Review & submit** | unchanged | |

**Result: 5 steps whether the merchant takes one product or all three.** Down from 7–9. No field removed — optional fields are *collapsed*, settlement is *merged*, product modules are *unified*.

> Design principle being protected: the pilot validated that **simplicity is Aman's moat** (reps said the app is easier than competitors). Every added field/step must clear a "would a rep in the field thank us for this?" bar.

### A.3 Field-level decisions (the source of truth for Figma + stories)

Legend: **R** = required · **O** = optional (always visible) · **C** = collapsed under «بيانات إضافية» · **OCR** = pre-filled by scan (rep reviews).

**Step 1 — Start**
- Nationality toggle (مصري / أجنبي) — R · drives ID-vs-passport + identity fields
- Customer type toggle (فردي / شركات) — R · drives KYB + company docs
- ID front (Egyptian) / passport image (foreigner) — R · **OCR trigger**
- ID back (Egyptian) — O

**Step 2 — Confirm identity** (all OCR-prefilled, rep reviews)
- first / family name — R · second / third name — O
- National ID (Egyptian, 14-digit) **or** passport number + nationality country (foreigner) — R
- birth date — R · address — R
- EN first / family name — **C**

**Step 3 — Business & settlement**
- shop name — R · activity type — R · governorate — R · city — R · branch address (AR) — R
- merchant mobile — R · capacity (الصفة) — R
- bank name — R · bank account number — R · account holder — R
- *(company track only)* commercial register — R · tax card — R · both **OCR-fetched** from the doc images in step 4 (prefill, editable)
- EN shop name, EN legal name, sub-specialty, branch name, secondary mobile, work phone, email, EN branch address — **C**

**Step 4 — Products & documents**
- **Shared device block** (shown if Acceptance POS and/or BP POS selected): device type — R · device count — R · device id — O
- Acceptance POS delta: payment service (دفع/تقسيط) — R
- BP POS delta: bill service (كهرباء/مياه/…) — R
- Microfinance delta: amount — R · loan purpose — O
- Documents (deduped union; see `requiredDocs`): contract (all) — R; commercial reg + tax card (company, **OCR-fetch**) — R; shop photo (Acceptance/BP) — R; device receipt (Acceptance) — R; income proof (Microfinance) — O

**Step 5 — Review & submit** — grouped read-only summary + “X of Y documents uploaded” + «إرسال الطلب».

---

## Part B — Figma Design Spec

> A generated Figma file of the 5-step flow accompanies this doc (link added on generation). This section is the written spec it was built from — it is the authority your designer refines against.

### B.1 Visual system (from the app's `app_theme.dart`)
- **Direction:** RTL-first (Arabic). Every screen mirrors; use `start`/`end`, never left/right. Typeface **Alexandria**.
- **Palette:** Aman brand — primary green (header/active/progress), teal accents (success/captured/OCR-extracted chips), red (errors), neutral input background + border greys. White cards on a light background.
- **Components reused across all steps:**
  - **App bar** — primary green, centered title, back chevron (points *forward* in RTL).
  - **Progress** — `خطوة N من M` label + linear bar (primary fill).
  - **Toggle chips** — two-up segmented control (nationality, customer type). Selected = primary fill + white text.
  - **Text field / dropdown / date** — label (with `*` when required), rounded input, right-aligned text, hint.
  - **Image/scan tile** — rounded card; states: empty (add-photo icon, «تصوير»/«مسح»), busy (spinner), captured (teal check, «إعادة»); OCR-extracted chip below («تم استخراج الرقم: …»).
  - **Collapsible section** — «بيانات إضافية (اختياري)» expander for collapsed fields.
  - **Footer** — sticky; secondary «السابق/إلغاء» + primary «متابعة/إرسال الطلب».
  - **Error banner** — light-red pill above the footer.

### B.2 Frames to design (the deliverable in Figma)
1. **Step 1 – Start** (two variants: Egyptian = ID front/back; Foreigner = passport)
2. **Step 1 – Scanning state** (spinner on the scan tile) + **scanned summary chip** («ذكر • القاهرة • 1990»)
3. **Step 2 – Confirm identity** (Egyptian vs Foreigner field set; one low-confidence field highlighted)
4. **Step 3 – Business & settlement** — collapsed default + expanded «بيانات إضافية»
5. **Step 4 – Products & documents** — show 1-product and 3-product compositions; shared device block; doc tiles incl. an OCR-fetch tile (commercial reg)
6. **Step 5 – Review & submit**
7. **Cross-cutting states:** validation error banner, duplicate-identity error, submit spinner, success screen, **draft “resume where you left off”** entry (see D — drafts).

### B.3 Notes for the designer
- Optional fields **collapsed by default** — the expanded state is the exception, not the norm.
- The scan tile is the hero of step 1 — make “مسح” (scan) visually primary over manual entry; manual is the fallback.
- Company track adds KYB fields + 2 docs; individual track hides them. Design both; don't design a third “empty” state.
- Confidence: when an OCR field is low-confidence, mark it for review (e.g. amber underline + helper text) rather than blocking.

---

## Part C — EPICs & INVEST User Stories

Stories are INVEST (Independent, Negotiable, Valuable, Estimable, Small, Testable). Persona **التاجر**’s data is captured by the **مندوب المبيعات (rep)**; **back-office** verifies. Acceptance criteria are the testable core, not exhaustive.

### EPIC 1 — Onboarding shell & resumable drafts
*Goal: a reliable multi-step container a rep can exit and resume.*
- **1.1** As a rep, I can move through the onboarding as a stepped wizard with a clear “step N of M” progress, so I always know how much is left. *AC: progress reflects the composed step list; back on step 1 exits.*
- **1.2** As a rep, my progress autosaves on every step so I never lose work if I exit or lose signal. *AC: each step UPSERTs `onboarding_applications.payload` + `current_step`; row status `draft`.* → wires migration [032].
- **1.3** As a rep, I see a “drafts / resume” list on home and can reopen an application exactly where I left off. *AC: home lists my `status='draft'` rows; reopening restores fields + step.*
- **1.4** As a rep, I can cancel a draft. *AC: soft-cancel (`status='cancelled'` or `deleted_at`); it leaves the drafts list.*

### EPIC 2 — Identity capture & eKYC/OCR
*Goal: scan-first identity with manual fallback.*
- **2.1** As a rep, I choose nationality and customer type up front so the right document and fields are shown. *AC: Egyptian→NID, foreigner→passport; company→KYB fields/docs appear.*
- **2.2** As a rep, I scan the ID/passport and the personal fields pre-fill. *AC: scan calls `EkycService`; name/NID-or-passport/DOB/address populate; rep can edit.*
- **2.3** As a rep, low-confidence extracted fields are flagged so I double-check them. *AC: fields with confidence < threshold are visually marked; not blocking.*
- **2.4** As a rep, if a scan fails I get a clear Arabic message and can retry or type manually. *AC: `EkycException`→snackbar; manual entry always available; OCR never required.*
- **2.5** As a rep onboarding a company, capturing the commercial register / tax card image auto-fills those numbers. *AC: `ocrFetchDocs` maps doc→field via `scanCommercialRegister`/`scanTaxCard`.*

### EPIC 3 — KYC/KYB data capture (optimized layout)
*Goal: the 5-step field layout from Part A.*
- **3.1** As a rep, I confirm identity on a review-style screen rather than retyping. *AC: step 2 shows prefilled fields; required = name + identifier + DOB + address.*
- **3.2** As a rep, business and settlement are one screen with only essential fields shown. *AC: required set per A.3; settlement merged in.*
- **3.3** As a rep, optional details are collapsed behind one expander so the screen stays short. *AC: collapsed fields (A.3 “C”) hidden until «بيانات إضافية» expanded; values still persist.*
- **3.4** As a rep onboarding an individual, I never see company-only fields. *AC: track filter hides KYB fields + commercial/tax.*

### EPIC 4 — Products & documents (unified)
*Goal: one product+docs screen, no fan-out, no duplicate device entry.*
- **4.1** As a rep, all selected products are captured on one screen instead of one screen each. *AC: single step composes deltas for every selected product.*
- **4.2** As a rep, when a merchant takes both POS products I enter device type/count/id once. *AC: shared device block; Acceptance adds payment service, BP adds bill service.*
- **4.3** As a rep, required documents are deduped — a doc needed by several products appears once. *AC: `requiredDocs` union by type; contract always present.*
- **4.4** As a rep, the review screen shows “X of Y documents uploaded” before I can submit. *AC: count reflects captured docs; optional docs don't block.*

### EPIC 5 — Document storage (real upload)
*Goal: replace capture-and-stub with real Storage.*
- **5.1** As a rep, captured documents upload to secure storage, not just a local “captured” flag. *AC: image → `merchant-documents/<merchant_id>/<doc_type>.<ext>`; row in `merchant_documents` with `storage_path`.* → wires migration [035].
- **5.2** As a rep, I can only ever access my own merchants' documents. *AC: Storage RLS path-scoped to `created_by`; verified by the RLS fuzzer.*
- **5.3** As the back-office, each document carries a verification status. *AC: rows default `pending`; admin can set `verified`/`rejected`.*
- **5.4** As a rep on poor connectivity, uploads retry / queue without losing the captured image. *AC: failed upload is retryable; submit not silently lost.* (Negotiable: defer to fast-follow.)

### EPIC 6 — Review, submit & normalized persistence
*Goal: atomic materialization via the existing RPC.*
- **6.1** As a rep, submitting creates the merchant + all related records atomically (no orphans). *AC: call `submit_application(app_id)`; partial failure rolls back.* → wires migration [036].
- **6.2** As the back-office, each product enrollment has its own lifecycle status. *AC: `merchant_products` rows `pending`; independently approvable.* → migration [033].
- **6.3** As the back-office, applicant identity (KYC) and business identity (KYB) are stored separately. *AC: `kyc_profiles` always; `kyb_profiles` company-only.* → migration [034].
- **6.4** As a rep, a duplicate national ID / passport is rejected with a clear Arabic message. *AC: unique-violation → «هذا الرقم القومي/الجواز مسجل بالفعل».*

### EPIC 7 — Real eKYC vendor integration
*Goal: swap mock for production OCR, key server-side.*
- **7.1** As the platform, the production build calls the real vendor via the `ekyc-scan` Edge Function, not the mock. *AC: `--dart-define=EKYC_ENDPOINT=ekyc-scan`; mock used only when unset.*
- **7.2** As security, the vendor API key never ships in the app bundle. *AC: key in Edge Function secrets; verified by the APK secret-scan gate.*
- **7.3** As the platform, the Edge Function maps the vendor response to the app's `EkycResult`/`PassportResult`/`DocOcrResult` JSON contract. *AC: each `doc_type` returns the documented shape incl. `confidence`.*
- **7.4** As the platform, vendor errors/timeouts degrade gracefully to manual entry. *AC: non-200 → `EkycException`; rep can still proceed manually.*

### EPIC 8 — Merchant profile & reveal-with-audit
*Goal: read back the onboarded merchant.*
- **8.1** As a rep, I can open a read-only profile of a merchant I onboarded (identity, business, products, docs). *AC: reads normalized tables; masked identity by default.*
- **8.2** As a rep, revealing the NID/passport is one tap and writes an audit row. *AC: `reveal_kyc_identity(kyc_id)` returns clear-text + writes `*_revealed` audit row atomically.* → migration [034].

> **Suggested sequencing:** EPIC 1 → 3 → 4 (the optimized UX, all against existing migrations) ship the flow; EPIC 5 → 6 wire real persistence; EPIC 7 swaps the vendor; EPIC 2 (confidence/fallback polish) and EPIC 8 are quality. EPICs 1/3/4 need no NEW backend design — the migrations exist in the repo as `032`–`038` (renumbered 2026-07-03; the old `020`–`026` numbers collided with prod's applied field-visits ledger) but are **NOT applied to any project yet**. Apply them to your dev project first; before any prod apply, note 037's Vault-TCE guard and 038's only-if-absent guards around the prod-owned `users_role_check`/`is_supervisor`.

---

## Part D — Integration Map (UI seam → already-built backend)

The prototype currently does a **direct `merchants` insert with an `onboarding_application` JSONB** ([`card_application_wizard.dart:447`](../lib/screens/acceptance/card_application_wizard.dart)). The production target is the normalized path, **which is already migrated** — this is wiring, not schema design.

| Concern | Built (migration) | UI work to wire it |
|---|---|---|
| Resumable draft + autosave | `onboarding_applications` [032] | UPSERT `payload`/`current_step` per step; drafts list on home |
| Atomic submit | `submit_application(uuid)` RPC [036] | Replace direct insert with: create draft → autosave → `rpc('submit_application')` |
| Per-product enrollment | `merchant_products` [033] | Nothing — RPC writes it from `payload.products[]` |
| Applicant / business identity | `kyc_profiles` / `kyb_profiles` [034] | Nothing — RPC writes them |
| Documents + binaries | `merchant_documents` + private bucket [035] | Upload image to `merchant-documents/<merchant_id>/<doc_type>`; set `storage_path` |
| eKYC / OCR | `EkycService` facade + `ekyc-scan` Edge Function | Implement vendor call in [`supabase/functions/ekyc-scan/index.ts`](../supabase/functions/ekyc-scan/index.ts); set `EKYC_ENDPOINT` |
| Reveal-with-audit | `reveal_kyc_identity(uuid)` RPC [034] | Call from the merchant profile reveal button |

**Payload contract** the wizard must produce for `submit_application` is documented in the RPC header ([036](../supabase/migrations/036_submit_application.sql)): `{ track, nationality, id_document_type, kyc{…}, products[{product,data{…}}], documents[{type,captured}] }`. The current wizard already assembles almost exactly this shape in `_submit()` — redirect it into a draft + RPC instead of a direct insert.

### Open decisions for the dev team
1. **eKYC vendor** — confirm Valify (or alternative) and the response field mapping for NID, passport, commercial register, tax card (incl. per-field confidence).
2. **Document upload timing** — upload per-capture (simpler retry) vs. batch-on-submit (atomic with the RPC). Recommend per-capture with the row's `storage_path` set on success.
3. **Confidence threshold** for flagging low-confidence OCR fields (suggest start at 0.85; tune on real vendor data).
4. **Drafts retention** — how long `draft`/`cancelled` applications live before cleanup.
5. **Legacy dual-write** — `submit_application` still populates `merchants.products[]`/`*_amount`/`*_device_count` for old screens; decide when to drop them after the profile screen reads normalized tables.

---

*Prepared as a hand-over of the `ci/split-per-abi` onboarding prototype. Flow, design spec, and stories all describe the **optimized 5-step target**, not the current 7–9-step prototype.*
