# Field-Visit Logging — Implementation Plan

**Goal (supervisor feedback, 2026-06-29):** turn each of the 3 fixed daily field tasks from a *single GPS check-in* into an entry point to a **multi-visit log**. Each task opens its own page where the rep taps **«أدخل زيارة»** and fills a per-mission form (many times). Each visit captures GPS + a photo + counts + notes.

**Base branch:** `feat/field-visit-logging` (off `origin/claude/hopeful-euler-9gs6od` — the live field-task build). New migrations start at **022**.

**Decisions locked with Marwan:**
- Photos → **real Supabase Storage** (private bucket + RLS), not capture-and-stub.
- "government rate" = **governorate (المحافظة)** — seed Egypt's 27.
- Mission 3 (Aman branch) visits **also** capture GPS + photo.
- This *extends* the live build; the onboarding/passport line (`ci/split-per-abi`, migrations 017–026) is a separate "deploy later" prototype and is untouched.

---

## 1. The three missions (form spec)

| Field | M1 — Govt / Schools | M2 — Acceptance / Microfinance | M3 — Aman Branch |
|---|---|---|---|
| Visit cap | unlimited (≥10) | unlimited (≥10) | **max 2** |
| Discriminator | نوع: مدرسة / مؤسسة حكومية | المنتج: تمويل / Acceptance / كلاهما (checkbox ≥1) | الفرع (dropdown) |
| Name(s) | اسم المنشأة | اسم التاجر + اسم النشاط | — |
| Governorate | dropdown ✓ | dropdown ✓ | — (branch implies it) |
| GPS | ✓ required | ✓ required | ✓ required |
| Photo | ✓ required | ✓ required | ✓ required |
| # contacted (تم التواصل) | int ≥0 | int ≥0 | int ≥0 |
| # onboarded (تم التسجيل) | int ≥0, ≤ contacted | same | same |
| Notes | optional | optional | optional |

Template slugs already in `task_templates` (migration 019): `gov_schools_hospitals`, `merchants_acceptance_finance`, `aman_branch_visit` — used as the form discriminator.

---

## 2. Data model (DB)

Mirror the existing codebase idiom: **one wide table + per-category CHECK constraints** (same pattern as `merchants.microfinance_amount` / `acceptance_device_count` in migration 011) and **SECURITY DEFINER RPC as the only write path** (mirror `record_task_checkin` in 018).

### Migration `022_governorates.sql`
- `public.governorates (id smallint PK, name_ar text UNIQUE NOT NULL, sort_order int)`. Seed 27. RLS: authenticated SELECT, admin write (mirror `activity_types`, migration 012).

### Migration `023_aman_branches.sql`
- `public.aman_branches (id uuid PK, name_ar text NOT NULL, governorate_id smallint FK, active bool default true, created_at)`. RLS: authenticated SELECT, admin write. Seed with placeholder branches (real list comes from ops — documented in runbook).

### Migration `024_task_visits.sql`
```
public.task_visits (
  id              uuid PK default gen_random_uuid(),
  task_id         uuid NOT NULL REFERENCES field_tasks(id) ON DELETE CASCADE,
  rep_id          uuid NOT NULL REFERENCES auth.users(id),     -- forced = auth.uid()
  template_slug   text NOT NULL,                                -- discriminator
  -- location (every visit)
  lat             double precision NOT NULL,
  lng             double precision NOT NULL,
  accuracy_m      real,
  recorded_at     timestamptz NOT NULL,
  in_window       boolean NOT NULL,                             -- computed server-side
  -- shared
  governorate_id  smallint REFERENCES governorates(id),
  photo_path      text,                                         -- Storage object path
  notes           text DEFAULT '',
  contacted_count int  NOT NULL DEFAULT 0 CHECK (contacted_count >= 0),
  onboarded_count int  NOT NULL DEFAULT 0 CHECK (onboarded_count >= 0),
  -- M1
  place_kind      text,                                         -- 'school' | 'gov_institution'
  place_name      text,
  -- M2
  products        text[],                                       -- subset of {microfinance, acceptance}
  merchant_name   text,
  business_name   text,
  -- M3
  branch_id       uuid REFERENCES aman_branches(id),
  created_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT chk_onboarded_le_contacted CHECK (onboarded_count <= contacted_count),
  CONSTRAINT chk_visit_shape CHECK (
    (template_slug = 'gov_schools_hospitals'
       AND place_kind IN ('school','gov_institution') AND place_name IS NOT NULL
       AND governorate_id IS NOT NULL
       AND products IS NULL AND merchant_name IS NULL AND business_name IS NULL AND branch_id IS NULL)
 OR (template_slug = 'merchants_acceptance_finance'
       AND products IS NOT NULL AND array_length(products,1) >= 1
       AND merchant_name IS NOT NULL AND business_name IS NOT NULL AND governorate_id IS NOT NULL
       AND place_kind IS NULL AND place_name IS NULL AND branch_id IS NULL)
 OR (template_slug = 'aman_branch_visit'
       AND branch_id IS NOT NULL
       AND place_kind IS NULL AND place_name IS NULL AND products IS NULL
       AND merchant_name IS NULL AND business_name IS NULL)
  )
)
```
- Index on `(task_id)`, `(rep_id)`, `(template_slug)`.
- **RLS:** SELECT for `rep_id = auth.uid() OR is_supervisor() OR is_admin()`. **No** INSERT/UPDATE/DELETE policy — writes go only through the RPC.
- **RPC `record_task_visit(...)`** SECURITY DEFINER, `SET search_path = public`, mirrors `record_task_checkin`:
  - auth + sales-rep-only + active + `location_consent` gate (same as 018).
  - validate coords, validate task belongs to caller.
  - **Mission-3 cap:** if `template_slug='aman_branch_visit'` and `COUNT(*) visits for this task >= 2` → `RAISE EXCEPTION` (Arabic: «الحد الأقصى زيارتين لهذه المهمة»).
  - compute `in_window` from `field_tasks` window.
  - INSERT a new `task_visits` row (NOT upsert — many per task).
  - set `field_tasks.status='completed'` on first visit (rep can keep adding).
  - write `audit_log` row (`action='task_visit_added'`).
  - return the new `visit_id` + `in_window`.
  - REVOKE from public/anon, GRANT EXECUTE to authenticated.

### Migration `025_task_visit_photos_storage.sql`
- Create private bucket `task-visit-photos`.
- `storage.objects` RLS policies (path convention `{rep_id}/{task_id}/{uuid}.jpg`):
  - INSERT/SELECT where `(storage.foldername(name))[1] = auth.uid()::text` (rep owns own folder).
  - SELECT for supervisor/admin (oversight).
  - No UPDATE/DELETE for reps (immutable proof).

### Migration `026_visit_report_view.sql`
- `v_visit_report` (security_invoker) flattening `task_visits + field_tasks + users + governorates + aman_branches` → Arabic-headed export with a Google-Maps link per visit, contacted/onboarded, product/place/branch, photo path. Supersedes `v_checkin_report` for the new flow (keep the old view for historical check-ins).
- Add supervisor SQL snippets (per-rep daily onboarded totals, per-governorate coverage) — extend `020_performance_snippets.sql` style.

> `task_checkins` (one-per-task, migration 018) is **left intact** — historical data stays. The app simply stops writing it and writes `task_visits` instead. No destructive change.

---

## 3. App changes (Flutter)

### Dependencies / platform
- `pubspec.yaml`: add `image_picker: ^1.1.2` (gallery + camera). `geolocator` already present.
- `AndroidManifest.xml`: add `android.permission.CAMERA` (gallery needs none on Android 13+ photo picker). Location perms already present.
- `ios/Runner/Info.plist`: add `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` (Arabic copy). Location key already present.

### Models (`lib/models/`)
- `task_visit.dart` — `TaskVisit` value object + `fromJson`, `VisitKind`/product enums.
- `governorate.dart`, `aman_branch.dart` — lookup value objects.

### Services (`lib/services/`)
- Reuse `location_service.dart` as-is (one fix per call).
- `visit_photo_service.dart` (new) — pick/capture via `image_picker`, downscale, upload to `task-visit-photos` at `{uid}/{taskId}/{uuid}.jpg`, return the object path. (Keep Supabase calls out of the widget.)

### Providers (`lib/providers/`)
- `field_tasks_provider.dart` — extend: fetch `visit_count` per task (embed `task_visits(count)`), expose `visitsFor(taskId)`, `addVisit(...)` calling `record_task_visit`, refresh task on return. Keep the consent gate it already has.
- `lookups_provider.dart` (new) — load governorates + active branches once, cache.

### Screens / widgets
- `lib/widgets/field_tasks_section.dart` — card button changes from «تسجيل الموقع» to **«الزيارات (n) ›»** / «أدخل زيارة» → `Navigator.push` to the visits page. (Consent dialog moves to first "add visit".)
- `lib/screens/field/task_visits_screen.dart` (new) — header (task title + window + in/out-of-window summary), list of logged visits (compact cards), FAB «أدخل زيارة». RTL + `ResponsiveContainer`.
- `lib/screens/field/add_visit_screen.dart` (new) — the per-mission form, rendered by `template_slug`. Sub-widgets: governorate dropdown, branch dropdown, segmented place-kind, product checkboxes, GPS capture row (reuses `LocationService` + shows lat/lng + accuracy), photo capture (thumbnail + retake), contacted/onboarded steppers, notes. Client validation mirrors the DB CHECK; submit → `addVisit` → pop.

### Analytics
- Extend the PII blocklist regex in `analytics.dart` to also reject `lat|lng|location` (and continue rejecting `merchant_name`/`full_name` — so visit events must **not** carry merchant/place names).
- New events: `field_visit_add_opened`, `field_visit_added` (props: `template_slug`, `in_window`, `governorate_id`, `contacted_count`, `onboarded_count`, `has_photo` — **no names, no lat/lng**), `field_visit_failed`.

---

## 4. Ops / supervisor (Story E parity)
- `scripts/seed_aman_branches.sh` **or** documented Dashboard Table-Editor flow for `aman_branches`.
- Extend `scripts/rls_fuzzer.sh`: rep cannot read another rep's `task_visits`; rep cannot forge `rep_id`/`task_id` via `record_task_visit`; M3 cap enforced; non-rep cannot write; anon blocked; Storage path-prefix isolation holds.
- `docs/P0-DASHBOARD-RUNBOOK.md`: "Manage branches & read the visit report" section (Arabic + English) — `SELECT * FROM v_visit_report`.
- `CLAUDE.md`: Current Decisions entry (multi-visit field logging + Storage posture) + backlog row + session log.

---

## 5. Build order
1. **022 → 026** migrations (apply to **dev** first; verify CHECK + RLS + RPC + Storage policies; `get_advisors` clean).
2. `image_picker` + manifest/plist perms.
3. Models + `lookups_provider` + `visit_photo_service`.
4. Extend `field_tasks_provider` (+ analytics blocklist).
5. `task_visits_screen` + `add_visit_screen` + card-button swap.
6. `flutter analyze` clean; Patrol shallow path (login → tasks → open mission → add one visit → assert).
7. RLS fuzzer cases + runbook + CLAUDE.md.
8. Build Pilot APK (CI) → verify MobSF/secret gates pass with `image_picker` added.

## 6. Decisions (locked 2026-06-29)
1. **Photo: required for all 3 missions.** DB: `photo_path NOT NULL`; client blocks submit without a photo.
2. **Counts: required.** `contacted_count`/`onboarded_count` required in the form (still `>=0`, `onboarded <= contacted`).
3. **Completion: explicit "done" button.** `record_task_visit` sets the task to **`in_progress`** (new status value), NOT completed. A separate `complete_field_task(p_task_id)` RPC (rep-only, own task, requires ≥1 visit) flips it to `completed`. Home/progress counter counts only `completed`.
4. **Branch list: Marwan will provide.** `aman_branches` created empty; seeding deferred (M3 dropdown empty until seeded). Does not block the rest.
5. **Per-visit `in_window`: yes**, recorded per visit (unchanged).

**Status model change:** `field_tasks.status` CHECK extends to `('pending','in_progress','completed','skipped')`. Migration 024 alters the constraint.
