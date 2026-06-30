#!/usr/bin/env bash
#
# provision_reps_aman_2026-06-29.sh — batch-provision the Aman One new-users roster
# parsed + reconciled from docs/aman_new_users_template.xlsx (Downloads, 2026-06-29).
#
# 88 sheet rows -> 68 provisioned here. Excluded:
#   - 17 already live in prod (2026-04-21 cohort) — phone-unique would reject.
#   - R66 Mohamed Yousry (emp 115071 already in prod on a different phone) — kept existing.
#   - R8 Hassan Naser + R28 Mohamed Osama — share phone +201012940013 (data error) — both skipped.
# Adjustments applied:
#   - Area Managers (Ahmed Said, Maher Mohsen) -> role sales_rep (DB only allows sales_rep/admin).
#   - emp_id "NA" (Khaled Hussein, Esraa Ali) -> placeholder PENDING-<last4>; fix in Dashboard later.
#   - All phones normalized to E.164; R80 "0100 904 5200" -> +201009045200.
#
# Prereqs (run in THIS shell before invoking):
#   export BW_CLI="/c/Users/marwan.haahmed/AppData/Local/Microsoft/WinGet/Packages/Bitwarden.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe/bw.exe"
#   export BW_SESSION=$("$BW_CLI" unlock --raw)
#   source .env.admin         # prod target per Current Decisions
#
# Continues on per-rep failure; prints a padded table of name/phone/emp/user_id/TEMP PASSWORD at the end.
# Nothing written to disk — passwords live only in this terminal buffer. DO NOT paste passwords into chat.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

[[ -n "${SUPABASE_URL:-}" ]]              || { echo "ERROR: SUPABASE_URL unset. Did you 'source .env.admin'?" >&2; exit 1; }
[[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]] || { echo "ERROR: SUPABASE_SERVICE_ROLE_KEY unset. Did you unlock BW + source .env.admin?" >&2; exit 1; }
[[ "$SUPABASE_SERVICE_ROLE_KEY" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] \
  || { echo "ERROR: SUPABASE_SERVICE_ROLE_KEY is not a JWT shape." >&2; exit 1; }

# --- Roster (phone<TAB>name<TAB>employee_id<TAB>role<TAB>business_unit<TAB>region) ---
REPS=$'+201141892445	Al Mohtady Bealah Mohamed	115211	sales_rep	Outdoor Retail	Upper Egypt
+201062075628	Mostafa Adel Mahmoud Ahmed	119303	sales_rep	Outdoor Retail	Upper Egypt
+201068770589	Nourhan Abd EL Rasoul Sayed Hassan	133461	sales_rep	Outdoor Retail	Upper Egypt
+201111037047	EL Hussein Mostafa Ibrahim Abo Zeid	136419	sales_rep	Outdoor Retail	Upper Egypt
+201002291525	Ahmed Mohamed Sayed Ali	154782	sales_rep	Outdoor Retail	Upper Egypt
+201027892953	Mohamed Hassan Abbas Abd El Hamed	159863	sales_rep	Outdoor Retail	Upper Egypt
+201099573624	Yousef Fawzy Mahmoud Ahmed	160397	sales_rep	Outdoor Retail	Upper Egypt
+201009696021	Omar Refaat Omar Hussein Ali	114825	sales_rep	Outdoor Retail	Upper Egypt
+201024524900	Ahmed Mohamed Refat Abd El Mohsen	87981	sales_rep	Outdoor Retail	Upper Egypt
+201281240671	Mohamed Hussein Abd El Hady Abd El Latif	128752	sales_rep	Outdoor Retail	Upper Egypt
+201119386577	Hend Mostafa Mohamed Abdelwahab	152192	sales_rep	Outdoor Retail	Upper Egypt
+201211319292	Abdallah Gamal Abdelazim Mohamed	153941	sales_rep	Outdoor Retail	Upper Egypt
+201030744975	Sarah Yasser Abd El Tawab Mohamed	161466	sales_rep	Outdoor Retail	Upper Egypt
+201124624610	Khaled Hussein Ahmed Abd El Aal	PENDING-4610	sales_rep	Outdoor Retail	Upper Egypt
+201067067654	Hamam Hassan Mohamed Hamam	125517	sales_rep	Outdoor Retail	Upper Egypt
+201279997992	Mohamed Hosny Mohamed AbdelRahim	133623	sales_rep	Outdoor Retail	Upper Egypt
+201156100569	Mamdouh Gouda El Samman Attia	145962	sales_rep	Outdoor Retail	Upper Egypt
+201154235297	Ahmed El Sadat Hamdy Mohamed	148715	sales_rep	Outdoor Retail	Upper Egypt
+201125966359	Esraa Ali Mohamed Marzouk Ibrahim	PENDING-6359	sales_rep	Outdoor Retail	Upper Egypt
+201012155156	Mohamed Khaled Habashi	98052	sales_rep	Outdoor Retail	Greater Cairo
+201121673450	Ahmed Mahmoud abdelhamid	102909	sales_rep	Outdoor Retail	Greater Cairo
+201115118102	Ammar Tarek Mohamed Abo Bakar	110698	sales_rep	Outdoor Retail	Greater Cairo
+201146319579	Yousif Galal Ibrahim	125316	sales_rep	Outdoor Retail	Greater Cairo
+201157000182	Tiba Gamal Fathy	125804	sales_rep	Outdoor Retail	Greater Cairo
+201270134906	Mahmoud Abdelfatah Mohamed	125942	sales_rep	Outdoor Retail	Greater Cairo
+201226312042	Saeed khaed soliman Emam	126734	sales_rep	Outdoor Retail	Greater Cairo
+201126999068	Habiba Mohamed Hussein	126722	sales_rep	Outdoor Retail	Greater Cairo
+201129820411	Yousif Tarik Abdelmounem	127392	sales_rep	Outdoor Retail	Greater Cairo
+201065624980	Mariam Adel Abaas	127393	sales_rep	Outdoor Retail	Greater Cairo
+201102805878	Nada Sayed Ahmed	128231	sales_rep	Outdoor Retail	Greater Cairo
+201149053308	Nagwa Salim Mohamed	128229	sales_rep	Outdoor Retail	Greater Cairo
+201111129627	Mohamed Anter Ali	129365	sales_rep	Outdoor Retail	Greater Cairo
+201028323217	Hossam Meslh Fadlallah	129366	sales_rep	Outdoor Retail	Greater Cairo
+201156910829	Mostafa Abdelfatah Farouk	133052	sales_rep	Outdoor Retail	Greater Cairo
+201125790651	Ahmed Salah Saeed Shalaan	134065	sales_rep	Outdoor Retail	Greater Cairo
+201158206977	Kirolos gaber rasmy	134001	sales_rep	Outdoor Retail	Greater Cairo
+201113392346	Mohamed Hassan Ragab Hassan	139671	sales_rep	Outdoor Retail	Greater Cairo
+201554392969	Moustafa Sayed Mohamed Moustafa	140215	sales_rep	Outdoor Retail	Greater Cairo
+201114680769	Mohamed Gamal Abdel Hady	132155	sales_rep	Outdoor Retail	Greater Cairo
+201067837929	Mohamed Yehia Shaker Mohamed	93584	sales_rep	Outdoor Retail	Greater Cairo
+201228651568	Abanoub Teghyan Zaky Shenouda	145452	sales_rep	Outdoor Retail	Greater Cairo
+201120068482	Nourhan Mohamed Awad Mansour	146934	sales_rep	Outdoor Retail	Greater Cairo
+201091114459	Ahmed Mohamed Abdmonaam Ali	152266	sales_rep	Outdoor Retail	Greater Cairo
+201007993746	Adham Ahmed Abdelmoaz Ibrahim	157910	sales_rep	Outdoor Retail	Greater Cairo
+201129778328	shady gamal mohamed helmy	160132	sales_rep	Outdoor Retail	Greater Cairo
+201093390299	Alaa essam abdelmonaem	162652	sales_rep	Outdoor Retail	Greater Cairo
+201277742775	Mohab Ismail Ahmed Isamil	111842	sales_rep	Outdoor Retail	Delta
+201067070630	Yasmin Hany Mohamed Elaraby	121433	sales_rep	Outdoor Retail	Delta
+201016390543	Gamal Ibrahim Ali Abou El Enein Elwakel	132097	sales_rep	Outdoor Retail	Delta
+201270740018	Ibrahim Ibrahim Elagamy Hassan	134946	sales_rep	Outdoor Retail	Delta
+201012434139	Sherif Hosaam Ali Abdelkerim	138906	sales_rep	Outdoor Retail	Delta
+201033874492	Seif Aldeen ElSayed Ali Karm	127518	sales_rep	Outdoor Retail	Delta
+201282676218	Sameh Fathy Mohamed Hamed	140541	sales_rep	Outdoor Retail	Delta
+201003380825	Mohamed Youssef Abdelhady MoftahÂ	126504	sales_rep	Outdoor Retail	Delta
+201554745122	Ahmed Ali Abd Elwahab Mohamed	141529	sales_rep	Outdoor Retail	Delta
+201205808579	Ahmed Mostafa Said Mawy	142395	sales_rep	Outdoor Retail	Delta
+201285045443	Rania Magdy Bayoumi Mohamed	146423	sales_rep	Outdoor Retail	Delta
+201009045200	Ahmed Fathy Ali Mohamed	147962	sales_rep	Outdoor Retail	Delta
+201223030825	Wael Gamil sadek gergs khalil	61117	sales_rep	Outdoor Retail	Delta
+201030905548	Reem Khaled Mahmoud Elzaky	153476	sales_rep	Outdoor Retail	Delta
+201284633588	Omnia Maged Sayed Mohamed	153212	sales_rep	Outdoor Retail	Delta
+201202455331	Ghareb Ashraf Ghareb Salem	155371	sales_rep	Outdoor Retail	Delta
+201028778701	Mohamed Montesr Arafa Elsayed Soliman	156438	sales_rep	Outdoor Retail	Delta
+201080867760	Khaled Hesham Mohamed Abdelkader	156797	sales_rep	Outdoor Retail	Delta
+201279963893	Rana Ahmed Abo El Magd Mohamed Ibrahim	157236	sales_rep	Outdoor Retail	Delta
+201280245039	Mohamed Salem Mohamed Abd El Maksoud	160125	sales_rep	Outdoor Retail	Delta
+201159837350	Ahmed Said	90594	sales_rep	Outdoor Retail	Delta
+201159209650	Maher Mohsen	90012	sales_rep	Outdoor Retail	Greater Cairo'

TOTAL=$(printf '%s\n' "$REPS" | wc -l | tr -d ' ')

cat <<BANNER
=========================================================
  BATCH PROVISION — AMAN ONE NEW USERS (2026-06-29)
=========================================================
  Target URL:  ${SUPABASE_URL}
  Rep count:   ${TOTAL}
  Role:        all sales_rep
=========================================================
BANNER

read -r -p "Type YES to provision all ${TOTAL} users in prod: " CONFIRM
[[ "${CONFIRM^^}" == "YES" ]] || { echo "Aborted."; exit 1; }

declare -a SUCCESS_LINES
declare -a FAILURE_LINES
IDX=0

while IFS=$'\t' read -r PHONE NAME EMP_ID ROLE BU REGION; do
  IDX=$((IDX + 1))
  echo ""
  echo "[${IDX}/${TOTAL}] >>> ${NAME} (${PHONE})"

  set +e
  OUTPUT=$(bash "${REPO_ROOT}/scripts/provision_rep.sh" \
    --phone "$PHONE" \
    --name "$NAME" \
    --employee-id "$EMP_ID" \
    --role "$ROLE" \
    --business-unit "$BU" \
    --region "$REGION" 2>&1)
  RC=$?
  set -e

  if [[ $RC -ne 0 ]]; then
    FAIL_MSG=$(printf '%s' "$OUTPUT" | tail -5 | tr '\n' ' ' | sed 's/  */ /g')
    FAILURE_LINES+=("$(printf '%s\t%s\t%s\t%s' "$NAME" "$PHONE" "$EMP_ID" "$FAIL_MSG")")
    echo "    FAILED (rc=${RC}): ${FAIL_MSG}"
    continue
  fi

  USER_ID=$(printf '%s' "$OUTPUT" | awk -F'[[:space:]]+' '/Auth user ID:/ {print $NF}' | tr -d '\r')
  TEMP_PW=$(printf '%s' "$OUTPUT" | awk -F'[[:space:]]+' '/Temp password:/ {print $NF}' | tr -d '\r')

  if [[ -z "$USER_ID" || -z "$TEMP_PW" ]]; then
    FAILURE_LINES+=("$(printf '%s\t%s\t%s\tparse_failed_unexpected_output' "$NAME" "$PHONE" "$EMP_ID")")
    echo "    FAILED: could not parse user_id or temp_password from script output."
    continue
  fi

  SUCCESS_LINES+=("$(printf '%s\t%s\t%s\t%s\t%s' "$NAME" "$PHONE" "$EMP_ID" "$USER_ID" "$TEMP_PW")")
  echo "    OK — user_id=${USER_ID}"
done <<< "$REPS"

echo ""
echo "========================================================="
echo "  SUMMARY"
echo "========================================================="
echo "  Succeeded: ${#SUCCESS_LINES[@]} / ${TOTAL}"
echo "  Failed:    ${#FAILURE_LINES[@]} / ${TOTAL}"
echo "========================================================="

if (( ${#FAILURE_LINES[@]} > 0 )); then
  echo ""
  echo "--- FAILURES ---"
  printf 'Name\tPhone\tEmpID\tTail\n'
  printf '%s\n' "${FAILURE_LINES[@]}"
fi

if (( ${#SUCCESS_LINES[@]} > 0 )); then
  echo ""
  echo "--- SUCCESSES (copy this block to your password manager NOW) ---"
  echo "--- Passwords will NOT be shown again. Do NOT paste into chat. ---"
  echo ""
  {
    printf 'Name\tPhone\tEmpID\tUserID\tTempPassword\n'
    printf '%s\n' "${SUCCESS_LINES[@]}"
  } | column -s $'\t' -t

  # Opt-in disk dump for building credential handouts. OFF by default.
  # Enable with:  CRED_OUT=/c/Users/marwan.haahmed/aman-creds-2026-06-29.tsv bash scripts/provision_reps_aman_2026-06-29.sh
  # SENSITIVE: plaintext passwords on disk. Keep on the encrypted volume, distribute, then SHRED.
  if [[ -n "${CRED_OUT:-}" ]]; then
    {
      printf 'Name\tPhone\tEmpID\tUserID\tTempPassword\n'
      printf '%s\n' "${SUCCESS_LINES[@]}"
    } > "$CRED_OUT"
    chmod 600 "$CRED_OUT" 2>/dev/null || true
    echo ""
    echo ">>> Credentials written to: ${CRED_OUT}"
    echo ">>> Build handouts:  pwsh -File scripts/build_cred_handouts.ps1 -Tsv \"${CRED_OUT}\""
    echo ">>> DELETE this file once every rep has their password."
  fi
fi

echo ""
echo "Done."