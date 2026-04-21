#!/usr/bin/env bash
#
# rls_fuzzer.sh — RLS fuzz harness for the Aman Supabase project.
#
# Provisions three throwaway fixture users (rep_a, rep_b, admin) via the Admin
# API, logs each of them in via GoTrue to get real access_token JWTs, then
# drives PostgREST with those JWTs to prove the RLS policies in migration 004
# (+ 012, + 013) actually reject cross-rep access. Deletes the fixtures on
# exit regardless of outcome.
#
# Expected outcomes (rows in the fuzz matrix below). Any deviation fails the
# run and exits non-zero, making this safe to gate CI on.
#
# Usage:
#   source .env.admin                 # SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
#   export SUPABASE_ANON_KEY="..."    # project anon key (login endpoint needs it)
#   ./scripts/rls_fuzzer.sh
#
# Flags:
#   --keep-fixtures   skip cleanup (useful for post-mortem debugging)
#   --verbose         print full PostgREST responses instead of pass/fail lines
#
# Target project:
#   Whichever SUPABASE_URL is active. DO NOT run against prod — the fixtures
#   land in auth.users and public.users, and the lead rows land in
#   public.merchants. Safety guard below refuses to run if SUPABASE_URL looks
#   like the prod project ref.

set -euo pipefail

# --- Config -----------------------------------------------------------------

PROD_PROJECT_REF="yflwudkmhqwoscipscbb"
FUZZ_PREFIX="RLSFUZZ"
RUN_ID="$(date -u +%Y%m%d%H%M%S)"
KEEP_FIXTURES=0
VERBOSE=0
FAIL_COUNT=0
PASS_COUNT=0

# --- Arg parsing ------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-fixtures) KEEP_FIXTURES=1; shift ;;
    --verbose)       VERBOSE=1; shift ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- Helpers ----------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

log()   { echo "[$(date -u +%H:%M:%S)] $*"; }
pass()  { PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS  $*"; }
fail()  { FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL  $*" >&2; }

# random_phone: +201 + 7 trailing RUN_ID chars + 2-char role suffix = 12 digits total.
# Well under E.164's 15-digit cap. Auth Admin API doesn't enforce carrier prefix;
# only public.merchants.phone does (via normalize_phone trigger).
random_phone() {
  local suffix="$1"  # 2 chars
  local tail="${RUN_ID: -7}"
  printf '+201%s%s' "$tail" "$suffix"
}

generate_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true
}

# PostgREST GET — returns JSON array body; caller checks length via jq.
pg_get() {
  local jwt="$1" path="$2"
  curl -sS -X GET \
    "${SUPABASE_URL}${path}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${jwt}"
}

# PostgREST generic — returns body + HTTP status on one line: "BODY\n<STATUS>"
pg_call() {
  local method="$1" jwt="$2" path="$3" body="${4:-}"
  local args=(-sS -X "$method"
    "${SUPABASE_URL}${path}"
    -H "apikey: ${SUPABASE_ANON_KEY}"
    -H "Authorization: Bearer ${jwt}"
    -H "Content-Type: application/json"
    -H "Prefer: return=representation"
    -w "\n%{http_code}")
  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}"
}

# Extract body + status from pg_call output into globals BODY / STATUS.
split_body_status() {
  local raw="$1"
  STATUS="${raw##*$'\n'}"
  BODY="${raw%$'\n'*}"
}

# --- Validation -------------------------------------------------------------

require_cmd curl
require_cmd jq

[[ -n "${SUPABASE_URL:-}" ]]               || die "SUPABASE_URL not set (source .env.admin)"
[[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]  || die "SUPABASE_SERVICE_ROLE_KEY not set"
[[ -n "${SUPABASE_ANON_KEY:-}" ]]          || die "SUPABASE_ANON_KEY not set (export before running)"

# Safety guard: don't run against prod unless explicitly whitelisted.
if [[ "$SUPABASE_URL" == *"${PROD_PROJECT_REF}"* ]]; then
  die "Refusing to run: SUPABASE_URL points at prod project ${PROD_PROJECT_REF}. Point at dev."
fi

# --- Provision fixtures -----------------------------------------------------

REP_A_PHONE="$(random_phone 01)"
REP_B_PHONE="$(random_phone 02)"
ADMIN_PHONE="$(random_phone 03)"
REP_A_PASSWORD="$(generate_password)"
REP_B_PASSWORD="$(generate_password)"
ADMIN_PASSWORD="$(generate_password)"

REP_A_ID=""
REP_B_ID=""
ADMIN_ID=""
FIXTURE_MERCHANT_A=""
FIXTURE_MERCHANT_B=""

# cleanup: wipe merchants + auth users. Runs on EXIT unless --keep-fixtures.
cleanup() {
  local rc=$?
  if [[ "$KEEP_FIXTURES" -eq 1 ]]; then
    log "Keeping fixtures (--keep-fixtures). IDs: rep_a=${REP_A_ID} rep_b=${REP_B_ID} admin=${ADMIN_ID}"
    exit "$rc"
  fi
  log "Cleaning up fixtures..."

  # Delete merchants created by fixture reps (service role bypasses RLS).
  # Also purge the audit_log rows referencing those fixture actors, since
  # audit_log has no FK cascade to auth.users and auth.users has a FK to actor_id.
  for uid in "$REP_A_ID" "$REP_B_ID" "$ADMIN_ID"; do
    [[ -z "$uid" ]] && continue
    curl -sS -X DELETE \
      "${SUPABASE_URL}/rest/v1/merchants?created_by=eq.${uid}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Prefer: return=minimal" >/dev/null 2>&1 || true
    curl -sS -X DELETE \
      "${SUPABASE_URL}/rest/v1/audit_log?actor_id=eq.${uid}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Prefer: return=minimal" >/dev/null 2>&1 || true
  done

  # Delete auth users (public.users cascades via FK ON DELETE CASCADE).
  for uid in "$REP_A_ID" "$REP_B_ID" "$ADMIN_ID"; do
    [[ -z "$uid" ]] && continue
    curl -sS -X DELETE \
      "${SUPABASE_URL}/auth/v1/admin/users/${uid}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" >/dev/null 2>&1 || true
  done
  log "Cleanup done."
  exit "$rc"
}
trap cleanup EXIT

# provision_user $phone $password $role -> prints UUID to stdout
provision_user() {
  local phone="$1" password="$2" role="$3"
  # Declare `name` separately — referencing `$role` on the same `local` line
  # that declares it trips `set -u` on older bash (e.g. the one Git Bash ships).
  local name="${FUZZ_PREFIX}_${role}_${RUN_ID}"
  local uid
  local create_payload create_resp profile_payload profile_resp claim_payload claim_resp

  create_payload=$(jq -nc --arg p "$phone" --arg pw "$password" \
    '{phone: $p, password: $pw, phone_confirm: true}')

  create_resp=$(curl -sS -X POST \
    "${SUPABASE_URL}/auth/v1/admin/users" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -d "$create_payload")

  uid=$(echo "$create_resp" | jq -r '.id // empty')
  if [[ -z "$uid" ]]; then
    echo "$create_resp" | jq . >&2 || echo "$create_resp" >&2
    die "Failed to create fixture user ($role)"
  fi

  profile_payload=$(jq -nc --arg id "$uid" --arg name "$name" \
    --arg phone "$phone" --arg role "$role" \
    '{id: $id, name: $name, phone: $phone,
      employee_id: ("FUZZ-" + $id[0:8]),
      business_unit: "FUZZ", region: "FUZZ",
      role: $role, must_change_password: false}')

  profile_resp=$(curl -sS -X POST \
    "${SUPABASE_URL}/rest/v1/users" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "$profile_payload")

  if ! echo "$profile_resp" | jq -e '.[0].id // .id' >/dev/null 2>&1; then
    echo "$profile_resp" | jq . >&2 || echo "$profile_resp" >&2
    die "Failed to insert profile row ($role)"
  fi

  claim_payload=$(jq -nc --arg uid "$uid" --arg role "$role" \
    '{uid: $uid, claim: "role", value: $role}')
  claim_resp=$(curl -sS -X POST \
    "${SUPABASE_URL}/rest/v1/rpc/set_claim" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -d "$claim_payload")
  if echo "$claim_resp" | jq -e '.message' >/dev/null 2>&1; then
    echo "$claim_resp" >&2
    die "Failed to set claim ($role)"
  fi

  printf '%s' "$uid"
}

# login $phone $password -> prints access_token JWT to stdout
login() {
  local phone="$1" password="$2"
  local resp token
  resp=$(curl -sS -X POST \
    "${SUPABASE_URL}/auth/v1/token?grant_type=password" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg p "$phone" --arg pw "$password" '{phone: $p, password: $pw}')")
  token=$(echo "$resp" | jq -r '.access_token // empty')
  if [[ -z "$token" ]]; then
    echo "$resp" >&2
    die "Login failed for $phone"
  fi
  printf '%s' "$token"
}

log "Provisioning fixtures (run_id=${RUN_ID})..."
REP_A_ID=$(provision_user "$REP_A_PHONE"  "$REP_A_PASSWORD"  "sales_rep")
REP_B_ID=$(provision_user "$REP_B_PHONE"  "$REP_B_PASSWORD"  "sales_rep")
ADMIN_ID=$(provision_user "$ADMIN_PHONE"  "$ADMIN_PASSWORD"  "admin")
log "Fixtures: rep_a=${REP_A_ID:0:8} rep_b=${REP_B_ID:0:8} admin=${ADMIN_ID:0:8}"

log "Logging in fixtures..."
JWT_A=$(login "$REP_A_PHONE"  "$REP_A_PASSWORD")
JWT_B=$(login "$REP_B_PHONE"  "$REP_B_PASSWORD")
JWT_ADMIN=$(login "$ADMIN_PHONE" "$ADMIN_PASSWORD")
log "JWTs issued."

# --- Seed: one merchant per rep ---------------------------------------------

# National IDs: structurally-valid 14-digit Egyptian NIDs. Per-run unique to avoid
# national_id_hash UNIQUE collisions when the cleanup path missed a prior run.
# Format: century(2=1900s|3=2000s) + YYMMDD + governorate(2) + serial(4) + checksum(1).
NID_SUFFIX="${RUN_ID: -5}"  # 5 digits, changes per second of wall-clock
# Governorate 88 = foreign-born (accepted by validate_national_id trigger).
# Differ rep_a/rep_b NIDs in the serial portion to dodge the hash UNIQUE.
NID_A="29001018810${NID_SUFFIX: -3}"
NID_B="29001018820${NID_SUFFIX: -3}"

seed_merchant() {
  local jwt="$1" uid="$2" nid="$3" name_suffix="$4" rep_idx="$5"
  local payload resp id phone
  # Egyptian local mobile: 11 digits, 010/011/012/015 prefix. normalize_phone
  # strips non-digits then requires exactly 11 digits starting with 0 + valid
  # operator prefix — "010" + 7-digit RUN_ID tail + 1-digit rep_idx satisfies.
  phone="010${RUN_ID: -7}${rep_idx}"
  payload=$(jq -nc \
    --arg name   "FUZZ Merchant ${name_suffix}" \
    --arg phone  "$phone" \
    --arg nid    "$nid" \
    --arg uid    "$uid" \
    '{name: $name, phone: $phone, national_id: $nid,
      notes: "rls fuzz", status: "lead",
      products: ["BP POS"], created_by: $uid}')
  resp=$(curl -sS -X POST \
    "${SUPABASE_URL}/rest/v1/merchants" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${jwt}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "$payload")
  id=$(echo "$resp" | jq -r '.[0].id // empty')
  [[ -n "$id" ]] || { echo "$resp" >&2; die "Seed insert failed for ${name_suffix}"; }
  printf '%s' "$id"
}

log "Seeding merchants..."
FIXTURE_MERCHANT_A=$(seed_merchant "$JWT_A" "$REP_A_ID" "$NID_A" "A" "1")
FIXTURE_MERCHANT_B=$(seed_merchant "$JWT_B" "$REP_B_ID" "$NID_B" "B" "2")
log "Seeded: m_a=${FIXTURE_MERCHANT_A:0:8} m_b=${FIXTURE_MERCHANT_B:0:8}"

# --- Fuzz matrix ------------------------------------------------------------

echo ""
echo "=== RLS FUZZ MATRIX ==="

# 1. Rep A sees own merchant, not Rep B's.
BODY=$(pg_get "$JWT_A" "/rest/v1/merchants?select=id,created_by")
count_a=$(echo "$BODY" | jq 'length')
sees_b=$(echo "$BODY" | jq --arg bid "$FIXTURE_MERCHANT_B" '[.[] | select(.id==$bid)] | length')
if [[ "$count_a" -ge 1 && "$sees_b" -eq 0 ]]; then
  pass "rep_a SELECT merchants: ${count_a} row(s), rep_b's merchant invisible"
else
  fail "rep_a SELECT merchants: count=${count_a}, saw_rep_b=${sees_b} (expected >=1 and 0)"
  [[ "$VERBOSE" -eq 1 ]] && echo "$BODY"
fi

# 2. Rep B sees own merchant, not Rep A's.
BODY=$(pg_get "$JWT_B" "/rest/v1/merchants?select=id,created_by")
count_b=$(echo "$BODY" | jq 'length')
sees_a=$(echo "$BODY" | jq --arg aid "$FIXTURE_MERCHANT_A" '[.[] | select(.id==$aid)] | length')
if [[ "$count_b" -ge 1 && "$sees_a" -eq 0 ]]; then
  pass "rep_b SELECT merchants: ${count_b} row(s), rep_a's merchant invisible"
else
  fail "rep_b SELECT merchants: count=${count_b}, saw_rep_a=${sees_a} (expected >=1 and 0)"
fi

# 3. Admin sees both fixture rows.
BODY=$(pg_get "$JWT_ADMIN" "/rest/v1/merchants?select=id&or=(id.eq.${FIXTURE_MERCHANT_A},id.eq.${FIXTURE_MERCHANT_B})")
count_admin=$(echo "$BODY" | jq 'length')
if [[ "$count_admin" -eq 2 ]]; then
  pass "admin SELECT merchants: sees both fixture rows"
else
  fail "admin SELECT merchants: count=${count_admin} (expected 2)"
fi

# 4. Anonymous (no JWT — just anon apikey) gets zero merchants.
anon_body=$(curl -sS "${SUPABASE_URL}/rest/v1/merchants?select=id" \
  -H "apikey: ${SUPABASE_ANON_KEY}")
anon_count=$(echo "$anon_body" | jq 'length' 2>/dev/null || echo "err")
if [[ "$anon_count" == "0" ]]; then
  pass "anon SELECT merchants: 0 rows"
else
  fail "anon SELECT merchants: count=${anon_count} (expected 0)"
  [[ "$VERBOSE" -eq 1 ]] && echo "$anon_body"
fi

# 5. Rep A tries to UPDATE Rep B's merchant. PostgREST returns [] when RLS filters.
raw=$(pg_call PATCH "$JWT_A" "/rest/v1/merchants?id=eq.${FIXTURE_MERCHANT_B}" '{"notes":"hacked by a"}')
split_body_status "$raw"
affected=$(echo "$BODY" | jq 'length' 2>/dev/null || echo "err")
if [[ "$affected" == "0" ]]; then
  pass "rep_a UPDATE rep_b's merchant: 0 rows affected (RLS blocked)"
else
  fail "rep_a UPDATE rep_b's merchant: affected=${affected} status=${STATUS} (expected 0)"
  [[ "$VERBOSE" -eq 1 ]] && echo "$BODY"
fi

# 6. Rep A tries to INSERT a merchant with created_by=rep_b. WITH CHECK must reject.
raw=$(pg_call POST "$JWT_A" "/rest/v1/merchants" "$(jq -nc \
  --arg uid "$REP_B_ID" \
  '{name:"FUZZ spoof", phone:"01099887766", national_id:"29001011234599",
    status:"lead", products:["BP POS"], created_by:$uid}')")
split_body_status "$raw"
if [[ "$STATUS" == "403" || "$STATUS" == "401" ]] || echo "$BODY" | jq -e '.code == "42501"' >/dev/null 2>&1; then
  pass "rep_a INSERT with created_by=rep_b: rejected (status=${STATUS})"
else
  fail "rep_a INSERT spoofing created_by: status=${STATUS} body=${BODY} (expected 403/42501)"
fi

# 7. Rep A SELECT audit_log. No SELECT policy for non-admin -> 0 rows.
BODY=$(pg_get "$JWT_A" "/rest/v1/audit_log?select=id")
c=$(echo "$BODY" | jq 'length' 2>/dev/null || echo "err")
if [[ "$c" == "0" ]]; then
  pass "rep_a SELECT audit_log: 0 rows (admin-only)"
else
  fail "rep_a SELECT audit_log: count=${c} (expected 0)"
fi

# 8. Admin SELECT audit_log. Policy is_admin() -> >=2 rows (fixture inserts).
BODY=$(pg_get "$JWT_ADMIN" "/rest/v1/audit_log?select=id&table_name=eq.merchants&order=created_at.desc&limit=5")
c=$(echo "$BODY" | jq 'length' 2>/dev/null || echo "err")
if [[ "$c" =~ ^[0-9]+$ ]] && [[ "$c" -ge 2 ]]; then
  pass "admin SELECT audit_log: ${c} row(s) visible"
else
  fail "admin SELECT audit_log: count=${c} (expected >=2)"
fi

# 9. Rep A SELECT users: own row visible, rep_b's row not.
BODY=$(pg_get "$JWT_A" "/rest/v1/users?select=id,role")
c=$(echo "$BODY" | jq 'length')
sees_b=$(echo "$BODY" | jq --arg b "$REP_B_ID" '[.[] | select(.id==$b)] | length')
if [[ "$c" -ge 1 && "$sees_b" -eq 0 ]]; then
  pass "rep_a SELECT users: own visible, rep_b invisible"
else
  fail "rep_a SELECT users: count=${c}, saw_rep_b=${sees_b}"
fi

# 10. Rep A tries to escalate: UPDATE own users row to role=admin. WITH CHECK must reject.
raw=$(pg_call PATCH "$JWT_A" "/rest/v1/users?id=eq.${REP_A_ID}" '{"role":"admin"}')
split_body_status "$raw"
# PostgREST returns [] when WITH CHECK fails silently OR 403 with code 42501.
# Either way, role should NOT actually be admin. Check by round-tripping.
BODY=$(pg_get "$JWT_A" "/rest/v1/users?select=role&id=eq.${REP_A_ID}")
actual_role=$(echo "$BODY" | jq -r '.[0].role // "missing"')
if [[ "$actual_role" == "sales_rep" ]]; then
  pass "rep_a role escalation blocked (role still sales_rep)"
else
  fail "rep_a role escalation: role=${actual_role} (expected sales_rep)"
fi

# 11. Rep A tries to UPDATE rep_b's users row directly (id=rep_b). USING must reject.
raw=$(pg_call PATCH "$JWT_A" "/rest/v1/users?id=eq.${REP_B_ID}" '{"name":"pwned"}')
split_body_status "$raw"
affected=$(echo "$BODY" | jq 'length' 2>/dev/null || echo "err")
if [[ "$affected" == "0" ]]; then
  pass "rep_a UPDATE rep_b's users row: 0 rows affected"
else
  fail "rep_a UPDATE rep_b's users row: affected=${affected} (expected 0)"
fi

# 12. Anon INSERT into merchants must be rejected (no WITH CHECK match, auth.uid() null).
raw=$(curl -sS -X POST \
  "${SUPABASE_URL}/rest/v1/merchants" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -w "\n%{http_code}" \
  -d "$(jq -nc --arg uid "$REP_A_ID" '{name:"anon",phone:"01000000000",national_id:"29001011234503",status:"lead",products:["BP POS"],created_by:$uid}')")
split_body_status "$raw"
if [[ "$STATUS" == "401" || "$STATUS" == "403" ]] || echo "$BODY" | jq -e '.code == "42501"' >/dev/null 2>&1; then
  pass "anon INSERT merchants: rejected (status=${STATUS})"
else
  fail "anon INSERT merchants: status=${STATUS} body=${BODY}"
fi

# 13. Rep A INSERT activity_types must be rejected (admin-only per migration 012).
raw=$(pg_call POST "$JWT_A" "/rest/v1/activity_types" \
  '{"name":"RLSFUZZ attempt","sort_order":999}')
split_body_status "$raw"
if [[ "$STATUS" == "401" || "$STATUS" == "403" ]] || echo "$BODY" | jq -e '.code == "42501"' >/dev/null 2>&1; then
  pass "rep_a INSERT activity_types: rejected (status=${STATUS})"
else
  fail "rep_a INSERT activity_types: status=${STATUS} body=${BODY} (expected 403/42501 — admin only)"
fi

# 14. Rep A INSERT cross_sell_pool must be rejected (admin-only per migration 013).
raw=$(pg_call POST "$JWT_A" "/rest/v1/cross_sell_pool" \
  '{"name":"RLSFUZZ attempt","phone":"01099999999","notes":"should fail"}')
split_body_status "$raw"
if [[ "$STATUS" == "401" || "$STATUS" == "403" ]] || echo "$BODY" | jq -e '.code == "42501"' >/dev/null 2>&1; then
  pass "rep_a INSERT cross_sell_pool: rejected (status=${STATUS})"
else
  fail "rep_a INSERT cross_sell_pool: status=${STATUS} body=${BODY} (expected 403/42501 — admin only)"
fi

# 15. Soft-delete invisibility: service_role sets merchant_a.deleted_at, then
#     rep_a (the original creator) must see 0 rows. Threat model is an admin or
#     backend process soft-deleting a record and the creator still being able
#     to read it via stale RLS — the deleted_at filter in the SELECT policy's
#     USING clause is what guards against this.
#
#     Why service_role and not rep_a's JWT: reps can't actually UPDATE their
#     own row's deleted_at via PostgREST at all. PostgREST sends Prefer:
#     return=representation on every UPDATE, which makes Postgres apply the
#     SELECT policy's USING as an implicit WITH CHECK on the new row; the new
#     row has deleted_at != NULL, so SELECT USING fails, Postgres raises
#     42501, the whole UPDATE rolls back. Verified against dev — 42501 "new
#     row violates row-level security policy for table merchants". That's a
#     different, happy-path RLS interaction (blocks client-side soft-delete);
#     it's not the attack path this test needs to cover.
#
#     Run LAST: mutates rep_a's fixture row. Cleanup still works — the
#     service_role DELETE filters by created_by, unchanged by this test.
curl -sS -X PATCH \
  "${SUPABASE_URL}/rest/v1/merchants?id=eq.${FIXTURE_MERCHANT_A}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  -d '{"deleted_at":"2020-01-01T00:00:00Z"}' >/dev/null
# Verify the actual DB row state via service_role (bypasses RLS). The SELECT
# policy's `deleted_at IS NULL` filter hides deleted rows from EVERYONE —
# including admin JWTs — through PostgREST, so we can't use an admin read as
# the diagnostic.
svc_view=$(curl -sS \
  "${SUPABASE_URL}/rest/v1/merchants?select=id,deleted_at&id=eq.${FIXTURE_MERCHANT_A}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}")
svc_deleted_at=$(echo "$svc_view" | jq -r '.[0].deleted_at // "null"')
BODY=$(pg_get "$JWT_A" "/rest/v1/merchants?select=id&id=eq.${FIXTURE_MERCHANT_A}")
post_soft_delete_count=$(echo "$BODY" | jq 'length' 2>/dev/null || echo "err")
if [[ "$svc_deleted_at" == "null" ]]; then
  fail "soft-delete setup failed: service_role PATCH did not persist deleted_at. service_role view still null — check service key / network."
elif [[ "$post_soft_delete_count" == "0" ]]; then
  pass "soft-delete invisibility: service_role-deleted merchant hidden from its creator"
else
  fail "soft-delete invisibility: deleted_at persisted (service_role sees ${svc_deleted_at}) but rep_a still sees the row (count=${post_soft_delete_count}) — SELECT policy deleted_at filter leaking"
  [[ "$VERBOSE" -eq 1 ]] && echo "$BODY"
fi

# --- Summary ----------------------------------------------------------------

echo ""
echo "=== RESULT ==="
echo "PASS: ${PASS_COUNT}"
echo "FAIL: ${FAIL_COUNT}"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
