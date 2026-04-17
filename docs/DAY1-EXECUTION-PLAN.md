# Day 1 Execution Plan — Parallel Agent Architecture

**Goal:** Take Aman from dev-only Flutter web app → signed Android release APK pointing at prod Supabase.
**Method:** 3 waves of Claude Code agents. Agents within each wave run in parallel. Each wave gates on the previous.

---

## Dependency Graph

```
WAVE 1 (all parallel — zero dependencies between agents)
├── Agent A: Fix AndroidManifest.xml (permissions + label)
├── Agent B: Update build.gradle.kts (signing config + minSdk)
├── Agent C: Add keystore to .gitignore + create key.properties template
├── Agent D: Audit Dart code for dev artifacts (hardcoded URLs, debug prints, TODOs)
└── Agent E: Create prod Supabase project + apply all 15 migrations (MCP)

    ↓ merge all Wave 1 changes

WAVE 2 (parallel — depends on Wave 1 merge)
├── Agent F: Run flutter analyze + fix any issues from Wave 1 edits
├── Agent G: Generate Android keystore (bash keytool command)
└── Agent H: Verify prod Supabase — run security advisors + test RLS (MCP)

    ↓ keystore exists, code clean, prod DB verified

WAVE 3 (sequential — depends on Wave 2)
├── Agent I: Build release APK (flutter build apk --release with --dart-define)
└── Agent J: Decompile APK + security scan (runs after I completes)
```

---

## Wave 1 — ✅ COMPLETED (2026-04-16)

All 5 agents ran. Some had issues — fixed manually in-session.

| ID | Agent Name | Status | Notes |
|----|-----------|--------|-------|
| A | android-manifest-fix | ✅ DONE | INTERNET + USE_BIOMETRIC permissions, label = "أمان" |
| B | gradle-signing-config | ✅ DONE (fixed) | Agent output was truncated — rebuilt manually with signing config + minSdk=23 |
| C | gitignore-keystore | ✅ DONE (fixed) | `key.properties.example` created by agent, `.gitignore` entries added manually |
| D | dart-code-audit | ⚠️ NO REPORT | Agent ran but did not persist output — re-run recommended in Wave 2 |
| E | supabase-prod-setup | ✅ DONE | Prod project `yflwudkmhqwoscipscbb` created, all 15 migrations applied, security advisors clean, RLS verified on 6 tables, 10 activity types seeded, 5 RPCs confirmed |

### Agent A — Android Manifest Fix

**Prompt:**
```
You are working on a Flutter app at the repo root. Edit the file
android/app/src/main/AndroidManifest.xml to make these 3 changes:

1. Add these permissions BEFORE the <application> tag:
   <uses-permission android:name="android.permission.INTERNET"/>
   <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
   <uses-permission android:name="android.permission.USE_FINGERPRINT"/>

2. Change android:label from "aman_sales_app" to "أمان"

3. Leave everything else untouched.

Read the file first, make the edits, then read it again to verify.
Do NOT touch any other files.
```

### Agent B — Gradle Signing Config

**Prompt:**
```
You are working on a Flutter Android app. Edit the file
android/app/build.gradle.kts to add release signing configuration.

Current state: the release buildType uses debug signing
(signingConfigs.getByName("debug")). We need it to use a real keystore
loaded from a key.properties file.

Make these changes:

1. At the top of the android {} block (before compileOptions), add:
   val keystorePropertiesFile = rootProject.file("key.properties")
   val keystoreProperties = java.util.Properties()
   if (keystorePropertiesFile.exists()) {
       keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
   }

2. Inside android {}, before buildTypes, add a signingConfigs block:
   signingConfigs {
       create("release") {
           if (keystorePropertiesFile.exists()) {
               keyAlias = keystoreProperties["keyAlias"] as String
               keyPassword = keystoreProperties["keyPassword"] as String
               storeFile = file(keystoreProperties["storeFile"] as String)
               storePassword = keystoreProperties["storePassword"] as String
           }
       }
   }

3. Change the release buildType to:
   release {
       signingConfig = if (keystorePropertiesFile.exists()) {
           signingConfigs.getByName("release")
       } else {
           signingConfigs.getByName("debug")
       }
   }

4. Pin minSdk in defaultConfig:
   minSdk = 23
   (This is required for biometric auth via local_auth. Replace
   flutter.minSdkVersion with the literal 23.)

Read the file first, make edits, read again to verify valid Kotlin syntax.
Do NOT touch any other files.
```

### Agent C — Gitignore + Keystore Template

**Prompt:**
```
You are working on a Flutter Android app repo.

Task 1: Edit .gitignore to add these entries at the bottom under a
new "# Android signing" comment:
  # Android signing
  *.keystore
  *.jks
  android/key.properties

Task 2: Create a new file android/key.properties.example with this
exact content:
  # Copy this to key.properties and fill in your values.
  # NEVER commit key.properties — it is gitignored.
  storePassword=<your-keystore-password>
  keyPassword=<your-key-password>
  keyAlias=aman
  storeFile=../aman-release.keystore

Read .gitignore first, then edit it. Then create the new file.
Do NOT touch any other files.
```

### Agent D — Dart Code Audit

**Prompt:**
```
You are auditing a Flutter app (lib/**/*.dart) for production readiness
before an Android release build. This is a READ-ONLY audit — do NOT
edit any files.

Search for and report:

1. HARDCODED URLS: Any "http://" or "https://" URLs that aren't the
   Supabase placeholder. Flag dev/staging/localhost references.

2. DEBUG PRINTS: Any print(), debugPrint(), or developer.log() calls
   that would leak data in production.

3. HARDCODED CREDENTIALS: Any strings that look like API keys, tokens,
   passwords, or secrets.

4. TODO/FIXME COMMENTS: List all // TODO and // FIXME comments with
   file paths and line numbers. Flag any that are blockers for pilot.

5. PLACEHOLDER VALUES: Look in main.dart for the Supabase.initialize()
   call. Confirm it reads SUPABASE_URL and SUPABASE_ANON_KEY from
   String.fromEnvironment (compile-time --dart-define), NOT hardcoded.

Output: A structured report with severity (CRITICAL / WARNING / INFO)
for each finding. Keep it under 300 words. If the code is clean, say so.
```

### Agent E — Supabase Prod Project Setup

**Prompt:**
```
You are setting up a production Supabase project for the Aman Sales App.

Step 1: Use the Supabase MCP tool create_project to create a new project:
  - name: "aman-sales-prod"
  - region: "eu-west-1" (or closest to Egypt — check available regions)
  - Get the organization ID first via list_organizations

Step 2: Wait for the project to be ready (check via get_project).

Step 3: Once ready, apply ALL migrations in order. Read each file from
supabase/migrations/ (there are 15, from 001 through 015) and execute
each one via execute_sql against the new prod project. Apply them
strictly in numeric order. If any migration fails, STOP and report
the error — do not skip.

The migration files are:
  001_schema.sql, 002_phone_trigger.sql, 003_national_id_trigger.sql,
  004_rls_policies.sql, 005_audit_triggers.sql, 006_export_snippets.sql,
  007_pin_function_search_paths.sql, 008_add_products_column.sql,
  009_audit_skip_no_auth.sql, 010_reveal_national_id_rpc.sql,
  011_product_details_columns.sql, 012_activity_types_and_merchant_fields.sql,
  013_cross_sell_tasks.sql, 014_cairo_timezone_tasks.sql,
  015_refill_rep_tasks.sql

Step 4: After all migrations, verify:
  - list_tables shows: users, merchants, audit_log, activity_types
  - execute_sql: SELECT count(*) FROM activity_types; (expect 10)
  - Run get_advisors (security advisors) and report findings

Step 5: Report the prod project's URL, anon key (via get_project or
get_publishable_keys), and project ref. These are needed for the
Android build.

IMPORTANT: Do NOT disable RLS on any table. Do NOT change auth settings
via SQL — those are configured manually in the Dashboard.
```

---

## Wave 2 — Parallel (3 agents, after Wave 1 merges)

Depends on: all Wave 1 file edits merged to working branch.

| ID | Agent Name | Depends On | Isolation | Est. Time |
|----|-----------|------------|-----------|-----------|
| F | flutter-analyze | A, B, C merged | none | 2 min |
| G | generate-keystore | C (.gitignore ready) | none | 1 min |
| H | supabase-prod-verify | E (prod project exists) | none | 3 min |

### Agent F — Flutter Analyze

**Prompt:**
```
Run these commands in sequence and report results:

1. cd to the Flutter project root.
2. Run: flutter analyze
3. If there are any errors or warnings, fix them. The likely sources:
   - build.gradle.kts changes from Wave 1
   - Any deprecation warnings in lib/ code
4. After fixing, run flutter analyze again to confirm 0 issues.
5. Run: flutter build apk --debug (quick sanity check that Gradle resolves)
   This is just a build test — the real release build happens in Wave 3.

Report: pass/fail for analyze, list of fixes made, build test result.
```

### Agent G — Generate Android Keystore

**Prompt:**
```
Generate an Android release keystore for the Aman Sales App.

Run this command:
  keytool -genkey -v \
    -keystore aman-release.keystore \
    -alias aman \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storepass amanpilot2026 \
    -keypass amanpilot2026 \
    -dname "CN=Aman Sales App, OU=Mobile, O=Aman, L=Cairo, ST=Cairo, C=EG"

Then:
1. Move the keystore to the android/ directory:
   mv aman-release.keystore android/

2. Create android/key.properties (NOT the .example — the real one):
   storePassword=amanpilot2026
   keyPassword=amanpilot2026
   keyAlias=aman
   storeFile=../aman-release.keystore

3. Verify the keystore:
   keytool -list -keystore android/aman-release.keystore \
     -storepass amanpilot2026

4. Verify android/key.properties is in .gitignore (it should be from
   Wave 1 Agent C).

Report: keystore SHA-256 fingerprint and confirmation that
key.properties is gitignored.

IMPORTANT: These are pilot-grade passwords. The user MUST change them
before any production release. Flag this in your output.
```

### Agent H — Supabase Prod Verification

**Prompt:**
```
Verify the production Supabase project created in Wave 1 (Agent E).

Use Supabase MCP tools against the PROD project (not the dev project
yynhcrtdzgcgedkolgxw). Get the prod project ID from list_projects —
it should be named "aman-sales-prod".

Run these checks via execute_sql:

1. RLS ENABLED:
   SELECT tablename, rowsecurity FROM pg_tables
   WHERE schemaname = 'public';
   → merchants, users, audit_log, activity_types should all show true.

2. VAULT ACTIVE:
   SELECT count(*) FROM pgsodium.valid_key;
   → Should be ≥ 1 (Vault encryption key exists).

3. TRIGGERS PRESENT:
   SELECT trigger_name, event_object_table FROM information_schema.triggers
   WHERE trigger_schema = 'public';
   → Should show phone normalization, NID validation, audit triggers.

4. RPC EXISTS:
   SELECT proname FROM pg_proc
   WHERE proname IN ('reveal_national_id', 'set_claim', 'is_admin');
   → All 3 should exist.

5. ACTIVITY TYPES SEEDED:
   SELECT name FROM activity_types ORDER BY sort_order;
   → Should return 10 Arabic names.

6. AUTH SETTINGS CHECK (via get_project):
   Confirm phone provider is available. Flag if anything looks wrong.

7. Run get_advisors for security findings. Report any non-informational
   items.

Report: PASS/FAIL for each check. If anything fails, provide the exact
error and recommended fix.
```

---

## Wave 3 — Sequential (2 agents, after Wave 2 completes)

Depends on: keystore exists (G), flutter analyze clean (F), prod Supabase verified (H).

| ID | Agent Name | Depends On | Isolation | Est. Time |
|----|-----------|------------|-----------|-----------|
| I | build-release-apk | F + G + H | none | 5 min |
| J | apk-security-scan | I (APK built) | none | 3 min |

### Agent I — Build Release APK

**Prompt:**
```
Build a signed release APK for the Aman Sales App.

IMPORTANT: You need the prod Supabase URL and anon key. Get them from:
- Check if a file docs/prod-credentials.txt exists (Agent E may have
  written it), OR
- Use the Supabase MCP: list_projects to find "aman-sales-prod", then
  get_project to get the URL, and get_publishable_keys for the anon key.

Then run:
  flutter build apk --release \
    --dart-define=SUPABASE_URL=<PROD_URL> \
    --dart-define=SUPABASE_ANON_KEY=<PROD_ANON_KEY>

After build:
1. Verify APK exists at build/app/outputs/flutter-apk/app-release.apk
2. Report APK file size in MB
3. Copy to a memorable location:
   cp build/app/outputs/flutter-apk/app-release.apk \
      aman-v1.0.0-pilot.apk
4. If size > 50MB, flag it (WhatsApp file send limit).
5. Run: flutter build apk --release --split-per-abi (creates smaller
   per-architecture APKs). Report arm64-v8a size — this is what 95%
   of modern Egyptian Android devices will use.

If the build fails:
- Read the error carefully.
- Common issues: missing key.properties, missing keystore, Gradle
  version mismatch, minSdk conflict.
- Fix and retry. Report what you fixed.
```

### Agent J — APK Security Scan

**Prompt:**
```
Security-scan the release APK built by Agent I.

The APK should be at: aman-v1.0.0-pilot.apk (project root)
If not there, check: build/app/outputs/flutter-apk/app-release.apk

Step 1 — Install apktool if needed:
  apt-get update && apt-get install -y apktool || pip install apktool

  If apktool is unavailable, use:
  unzip -o aman-v1.0.0-pilot.apk -d decompiled/

Step 2 — Decompile:
  apktool d aman-v1.0.0-pilot.apk -o decompiled/ -f

Step 3 — Scan for secrets:
  grep -ri "service_role\|service-role\|secret\|password\|Bearer " decompiled/ || true
  grep -ri "supabase" decompiled/ | head -20

  EXPECTED: Only SUPABASE_URL and SUPABASE_ANON_KEY should appear.
  The anon key is PUBLIC by design — this is fine.
  CRITICAL: service_role key must NOT be present.

Step 4 — Check for debug flags:
  grep -ri "debuggable\|debug" decompiled/AndroidManifest.xml || true
  → android:debuggable should be false or absent in release.

Step 5 — Check permissions:
  grep "uses-permission" decompiled/AndroidManifest.xml
  → Should see INTERNET, USE_BIOMETRIC, USE_FINGERPRINT. Nothing else
  unexpected (no CAMERA, READ_CONTACTS, ACCESS_FINE_LOCATION, etc.)

Step 6 — Check for plaintext HTTP:
  grep -ri "http://" decompiled/ --include="*.xml" --include="*.smali" | grep -v "http://schemas" || true
  → Should be empty. All traffic must be HTTPS.

Report: PASS/FAIL per check. For any CRITICAL finding, describe the
exact file and line. Clean up decompiled/ when done.
```

---

## Execution Timeline

```
Hour 0:00  ──────────── WAVE 1 START ────────────
           │ A: Manifest fix ............ (1 min)
           │ B: Gradle signing .......... (2 min)
           │ C: Gitignore + template .... (1 min)
           │ D: Dart code audit ......... (3 min)
           │ E: Supabase prod setup ..... (5 min)
Hour 0:05  ──────────── WAVE 1 DONE ─────────────
           │ (merge Wave 1 file changes)
Hour 0:10  ──────────── WAVE 2 START ────────────
           │ F: Flutter analyze ......... (2 min)
           │ G: Generate keystore ....... (1 min)
           │ H: Supabase prod verify .... (3 min)
Hour 0:15  ──────────── WAVE 2 DONE ─────────────
Hour 0:15  ──────────── WAVE 3 START ────────────
           │ I: Build release APK ....... (5 min)
           │ J: APK security scan ....... (3 min after I)
Hour 0:25  ──────────── WAVE 3 DONE ─────────────

Total: ~25 minutes (vs. ~45 minutes sequential)
```

---

## Manual Steps (Marwan — cannot be automated)

These must be done by you in the Supabase Dashboard AFTER Agent E creates the prod project:

| # | Step | When | Time |
|---|------|------|------|
| M1 | Enable 2FA on your Supabase Dashboard account | After prod project created | 2 min |
| M2 | Auth Settings → Phone provider ON | After M1 | 1 min |
| M3 | Auth Settings → Verify SMS provider is UNCONFIGURED | After M2 | 30 sec |
| M4 | Auth Settings → "Allow new users to sign up" → OFF | After M2 | 30 sec |
| M5 | Enable Vault extension (Dashboard → Extensions → search "vault") | After prod project created | 1 min |
| M6 | Enable pgsodium + pgcrypto extensions (same screen) | After M5 | 1 min |
| M7 | Change keystore passwords from pilot defaults to real ones | Before sharing APK externally | 5 min |

**NOTE:** M5 and M6 may need to happen BEFORE Agent E runs migrations, since
001_schema.sql references Vault. If Agent E reports extension errors, do M5+M6
first, then re-run the failed migration.

---

## Quick Reference — Copy-Paste Prompts

For Claude Code CLI, launch Wave 1 agents in a single message with 5 `/task` calls.
Wave 2 after Wave 1 merges. Wave 3 after Wave 2 completes.

See each agent section above for the full prompt text.
