#!/usr/bin/env bash
#
# reset_reps_aman_2026-06-30.sh — reset passwords for the 18 already-provisioned
# reps from HR's latest sheet (the 2026-04-21 cohort + Hassan Naser), and emit a
# styled xlsx the admin can distribute.
#
# These 18 already exist in prod; this ONLY rotates their passwords (fresh temp +
# must_change_password=true). No accounts are created here.
#
# Notes on two reconciled rows:
#   - Abdelrahman Mohamed Hussien — emp_id shown as 157911 (updated in prod 2026-06-30).
#   - Mohamed Youssry (115071) — reset targets his EXISTING prod phone +201148134259,
#     NOT the sheet's +201282772721 (kept existing per decision).
#
# Prereqs (in this shell, before invoking):
#   export BW_CLI="/c/Users/marwan.haahmed/AppData/Local/Microsoft/WinGet/Packages/Bitwarden.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe/bw.exe"
#   export BW_SESSION=$("$BW_CLI" unlock --raw)
#   source .env.admin         # prod target per Current Decisions
#
# Behavior:
#   - Loops the embedded roster, calls scripts/reset_password.sh per row.
#   - Writes a TSV to docs/pilot_reps_YYYY-MM-DD.tsv as it goes (gitignored).
#   - After the loop, invokes scripts/build_reps_sheet.ps1 to produce
#     docs/pilot_reps_YYYY-MM-DD.xlsx (gitignored, styled), then deletes the TSV.
#
# After running:
#   - Distribute each rep's own line via email/WhatsApp per docs/P0-DASHBOARD-RUNBOOK.md.
#   - Delete the xlsx once every rep has logged in + rotated.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- Sanity: env must already be loaded in parent shell ---------------------
[[ -n "${SUPABASE_URL:-}" ]]              || { echo "ERROR: SUPABASE_URL unset. Did you 'source .env.admin'?" >&2; exit 1; }
[[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]] || { echo "ERROR: SUPABASE_SERVICE_ROLE_KEY unset. Did you unlock BW + source .env.admin?" >&2; exit 1; }
[[ "$SUPABASE_SERVICE_ROLE_KEY" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] \
  || { echo "ERROR: SUPABASE_SERVICE_ROLE_KEY is not a JWT shape." >&2; exit 1; }

# --- Roster (phone<TAB>name<TAB>employee_id) ---
REPS=$'+201092021200\tAhmed Gamal Hussein Hassan\t35908
+201012940013\tHassan Naser Hassan Ali\t151560
+201026035597\tMohamed Hosny Mohamed Ahmed\t154088
+201016919789\tEsraa Hassan Mohamed Saad\t138510
+201061776410\tAhmed Gamal Abd EL Baky Mohamed\t148099
+201097658011\tRoaa Yasser Abd EL Aziz\t136962
+201021021750\tOmar Abdelaziz Shawky Ali\t151548
+201151813631\tSalma Ashraf Farouk Mahmoud\t130231
+201148822497\tKarem Ahemd Abdelal\t135224
+201150272582\tIbrahim Khairy Ibrahim\t136183
+201015359055\tFarouk Yehia Farouk Fahmy\t144744
+201117474687\tSamira Elsayed Abdelmaksood atefy\t152694
+201556596102\tAbdelrahman Mohamed Hussien\t157911
+201066437995\tIbrahim Ahmed Ibrahim Yossef\t99681
+201148134259\tMohamed Youssry Mohamed Mohamed Ali\t115071
+201012928307\tAhmed Mohamed Ezzat AlMazayen\t120151
+201203955834\tFathy Mohamed Fathy Ibrahim\t89993
+201221614310\tAbdelrahman Atef Abdelrahman Mahmoud\t119455'

TOTAL=$(printf '%s\n' "$REPS" | wc -l | tr -d ' ')
TODAY=$(date +%Y-%m-%d)
TSV="docs/pilot_reps_${TODAY}.tsv"
XLSX="docs/pilot_reps_${TODAY}.xlsx"

cat <<BANNER
=========================================================
  BATCH PASSWORD RESET — 18 EXISTING REPS (HR sheet)
=========================================================
  Target URL:  ${SUPABASE_URL}
  Rep count:   ${TOTAL}
  Output:      ${XLSX}
  (TSV intermediate at ${TSV} — deleted after xlsx built.)
=========================================================
WARNING: This invalidates these reps' CURRENT passwords. Anyone
         already logged in must re-onboard with the fresh temp
         password. Only proceed if you will redistribute now.
BANNER

read -r -p "Type YES to reset all ${TOTAL} passwords in prod: " CONFIRM
[[ "${CONFIRM^^}" == "YES" ]] || { echo "Aborted."; exit 1; }

# TSV header
mkdir -p docs
printf 'Name\tPhone\tEmployee ID\tTemp Password\n' > "$TSV"

# --- Loop -------------------------------------------------------------------

FAILURES=0
IDX=0
declare -a FAIL_LINES

while IFS=$'\t' read -r PHONE NAME EMP_ID; do
  IDX=$((IDX + 1))
  echo ""
  echo "[${IDX}/${TOTAL}] Resetting ${NAME} (${PHONE})..."

  set +e
  OUTPUT=$(bash "${REPO_ROOT}/scripts/reset_password.sh" --phone "$PHONE" 2>&1)
  RC=$?
  set -e

  if [[ $RC -ne 0 ]]; then
    FAIL_MSG=$(printf '%s' "$OUTPUT" | tail -5 | tr '\n' ' ' | sed 's/  */ /g')
    FAIL_LINES+=("$(printf '%s\t%s\t%s\t%s' "$NAME" "$PHONE" "$EMP_ID" "$FAIL_MSG")")
    FAILURES=$((FAILURES + 1))
    echo "    FAILED (rc=${RC}): ${FAIL_MSG}"
    continue
  fi

  TEMP_PW=$(printf '%s' "$OUTPUT" | awk -F'[[:space:]]+' '/Temp password:/ {print $NF}' | tr -d '\r')

  if [[ -z "$TEMP_PW" ]]; then
    FAIL_LINES+=("$(printf '%s\t%s\t%s\tparse_failed_unexpected_output' "$NAME" "$PHONE" "$EMP_ID")")
    FAILURES=$((FAILURES + 1))
    echo "    FAILED: could not parse temp password from script output."
    continue
  fi

  printf '%s\t%s\t%s\t%s\n' "$NAME" "$PHONE" "$EMP_ID" "$TEMP_PW" >> "$TSV"
  echo "    OK"
done <<< "$REPS"

SUCCESSES=$((TOTAL - FAILURES))

# --- Build xlsx -------------------------------------------------------------

echo ""
echo "========================================================="
echo "  Building ${XLSX}..."
echo "========================================================="

PS_SCRIPT="scripts/build_reps_sheet.ps1"

if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
    -InputTsv "$TSV" -OutputXlsx "$XLSX"
  PS_RC=$?
elif command -v pwsh >/dev/null 2>&1; then
  pwsh -File "$PS_SCRIPT" -InputTsv "$TSV" -OutputXlsx "$XLSX"
  PS_RC=$?
else
  echo "WARNING: Neither powershell.exe nor pwsh found in PATH." >&2
  echo "         TSV retained at ${TSV} — import manually into Excel." >&2
  PS_RC=127
fi

# --- Cleanup ----------------------------------------------------------------

if [[ $PS_RC -eq 0 && -f "$XLSX" ]]; then
  rm -f "$TSV"
  TSV_STATE="deleted"
else
  echo "ERROR: xlsx build failed (PS_RC=${PS_RC}). TSV retained at ${TSV}." >&2
  TSV_STATE="retained at ${TSV}"
fi

# --- Summary ----------------------------------------------------------------

echo ""
echo "========================================================="
echo "  SUMMARY"
echo "========================================================="
echo "  Succeeded:        ${SUCCESSES} / ${TOTAL}"
echo "  Failed:           ${FAILURES} / ${TOTAL}"
echo "  Output:           ${XLSX}"
echo "  TSV intermediate: ${TSV_STATE}"
echo "========================================================="

if (( ${#FAIL_LINES[@]} > 0 )); then
  echo ""
  echo "--- FAILURES ---"
  printf 'Name\tPhone\tEmpID\tTail\n'
  printf '%s\n' "${FAIL_LINES[@]}"
fi

echo ""
echo "DO NOT commit ${XLSX}. Distribute each rep their own line, then delete."
