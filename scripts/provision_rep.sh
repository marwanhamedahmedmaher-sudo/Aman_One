#!/usr/bin/env bash
#
# provision_rep.sh — Provision a sales rep or admin in Supabase.
#
# Usage:
#   ./scripts/provision_rep.sh \
#       --phone "+201012345678" \
#       --name "Marwan Hamed" \
#       --employee-id "ADMIN001" \
#       --role admin
#
#   --role: admin | sales_rep
#   Optional: --business-unit "Sales Unit", --region "Cairo"
#
# Behavior:
#   1. Creates the auth.users row via Supabase Admin API with phone_confirm=true
#      (NO SMS sent — phone is pre-confirmed).
#   2. Generates a 16-char alphanumeric temp password.
#   3. Inserts companion row into public.users with must_change_password=true.
#   4. Sets the role custom claim via set_claim().
#   5. Prints temp password ONCE to stdout. Capture it, send to rep via email + WhatsApp,
#      then forget. Do NOT pipe this script to tee/log files.
#
# Requirements:
#   - bash 4+, curl, jq
#   - .env.admin sourced (see .env.admin.example) with SUPABASE_URL +
#     SUPABASE_SERVICE_ROLE_KEY exported in the current shell.
#
# Exits non-zero on any error. Logs metadata (NOT the password, NOT the key) to
# scripts/provision.log (gitignored).

set -euo pipefail

# --- Constants ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/provision.log"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# --- Helpers -----------------------------------------------------------------

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

mask_phone() {
  # Mask middle digits for log: +201012345678 -> +20101****5678
  local p="$1"
  if [[ ${#p} -ge 8 ]]; then
    echo "${p:0:6}****${p: -4}"
  else
    echo "****"
  fi
}

generate_password() {
  # 16 chars, alphanumeric, OS-grade entropy.
  # Avoid + / = symbols that confuse copy-paste in messengers.
  # || true: suppress SIGPIPE (exit 141) when head closes the pipe under pipefail.
  local pw
  pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
  [[ ${#pw} -ge 16 ]] || die "Password generation failed (got ${#pw} chars, need 16)"
  printf '%s' "${pw:0:16}"
}

# --- Argument parsing --------------------------------------------------------

PHONE=""
NAME=""
EMPLOYEE_ID=""
ROLE=""
BUSINESS_UNIT="Sales Unit"
REGION="Cairo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phone)         PHONE="$2"; shift 2 ;;
    --name)          NAME="$2"; shift 2 ;;
    --employee-id)   EMPLOYEE_ID="$2"; shift 2 ;;
    --role)          ROLE="$2"; shift 2 ;;
    --business-unit) BUSINESS_UNIT="$2"; shift 2 ;;
    --region)        REGION="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# --- Validation --------------------------------------------------------------

require_cmd curl
require_cmd jq

[[ -n "$PHONE" ]]       || die "--phone is required"
[[ -n "$NAME" ]]        || die "--name is required"
[[ -n "$EMPLOYEE_ID" ]] || die "--employee-id is required"
[[ -n "$ROLE" ]]        || die "--role is required (admin | sales_rep)"

[[ "$ROLE" == "admin" || "$ROLE" == "sales_rep" ]] \
  || die "--role must be 'admin' or 'sales_rep' (got: $ROLE)"

# E.164: + then 8-15 digits
[[ "$PHONE" =~ ^\+[1-9][0-9]{7,14}$ ]] \
  || die "Invalid phone format. Expected E.164 like +201012345678 (got: $PHONE)"

[[ -n "${SUPABASE_URL:-}" ]] \
  || die "SUPABASE_URL not set. Did you 'source .env.admin'?"
[[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]] \
  || die "SUPABASE_SERVICE_ROLE_KEY not set. Did you 'source .env.admin'?"

# Sanity: service role key should be a JWT (3 dot-separated base64 segments).
if [[ ! "$SUPABASE_SERVICE_ROLE_KEY" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
  die "SUPABASE_SERVICE_ROLE_KEY does not look like a JWT. Refusing to proceed."
fi

# --- Generate temp password --------------------------------------------------

TEMP_PASSWORD="$(generate_password)"

# --- Step 1: Create auth user via Admin API ----------------------------------

echo ">>> Creating auth user for $(mask_phone "$PHONE") ($ROLE)..."

CREATE_PAYLOAD=$(jq -nc \
  --arg phone "$PHONE" \
  --arg password "$TEMP_PASSWORD" \
  '{phone: $phone, password: $password, phone_confirm: true}')

CREATE_RESPONSE=$(curl -sS -X POST \
  "${SUPABASE_URL}/auth/v1/admin/users" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "$CREATE_PAYLOAD")

USER_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id // empty')

if [[ -z "$USER_ID" ]]; then
  echo "Admin API response:" >&2
  echo "$CREATE_RESPONSE" | jq . >&2 || echo "$CREATE_RESPONSE" >&2
  die "Failed to create auth user. See response above."
fi

echo ">>> Auth user created: ${USER_ID}"

# --- Step 2: Insert companion public.users row + set claim -------------------
# We do this via the REST/RPC endpoint using the service role key.
# Using PostgREST's /rest/v1/rpc requires a function; we'll use the SQL endpoint
# via PostgREST table insert + a follow-up RPC for set_claim.

echo ">>> Inserting public.users profile row..."

PROFILE_PAYLOAD=$(jq -nc \
  --arg id "$USER_ID" \
  --arg name "$NAME" \
  --arg phone "$PHONE" \
  --arg employee_id "$EMPLOYEE_ID" \
  --arg business_unit "$BUSINESS_UNIT" \
  --arg region "$REGION" \
  --arg role "$ROLE" \
  '{id: $id, name: $name, phone: $phone, employee_id: $employee_id,
    business_unit: $business_unit, region: $region, role: $role,
    must_change_password: true}')

PROFILE_RESPONSE=$(curl -sS -X POST \
  "${SUPABASE_URL}/rest/v1/users" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "$PROFILE_PAYLOAD")

if ! echo "$PROFILE_RESPONSE" | jq -e '.[0].id // .id' >/dev/null 2>&1; then
  echo "Profile insert response:" >&2
  echo "$PROFILE_RESPONSE" | jq . >&2 || echo "$PROFILE_RESPONSE" >&2
  die "Failed to insert public.users row. Auth user ${USER_ID} was created — clean up manually."
fi

echo ">>> Profile row inserted."

# --- Step 3: Set role claim via RPC -----------------------------------------

echo ">>> Setting role claim..."

CLAIM_PAYLOAD=$(jq -nc \
  --arg uid "$USER_ID" \
  --arg role "$ROLE" \
  '{uid: $uid, claim: "role", value: $role}')

CLAIM_RESPONSE=$(curl -sS -X POST \
  "${SUPABASE_URL}/rest/v1/rpc/set_claim" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "$CLAIM_PAYLOAD")

# set_claim returns void; PostgREST returns empty or null for void functions.
# A non-empty error (JSON with "message" key) means failure.
if echo "$CLAIM_RESPONSE" | jq -e '.message' >/dev/null 2>&1; then
  echo "set_claim response: $CLAIM_RESPONSE" >&2
  die "Failed to set role claim. Clean up auth user ${USER_ID} manually."
fi

echo ">>> Role claim set."

# --- Logging (no password, no key) -------------------------------------------

echo "${TS}	provision	$(mask_phone "$PHONE")	${EMPLOYEE_ID}	${ROLE}	${USER_ID}" >> "$LOG_FILE"

# --- Output (single shot) ----------------------------------------------------

cat <<EOF

=========================================================
  PROVISIONED: ${NAME} (${ROLE})
=========================================================
  Phone (login):   ${PHONE}
  Employee ID:     ${EMPLOYEE_ID}
  Auth user ID:    ${USER_ID}
  Temp password:   ${TEMP_PASSWORD}
=========================================================
  ACTION REQUIRED:
    1. Copy temp password to your password manager NOW.
    2. Send to rep via EMAIL + WHATSAPP (manual).
    3. Inform rep: "You will be asked to change your
       password on first login."
    4. This password will NOT be shown again.
=========================================================
EOF
