#!/usr/bin/env bash
#
# reset_password.sh — Reset a rep's password to a fresh temp value.
#
# Usage:
#   ./scripts/reset_password.sh --phone "+201012345678"
#
# Behavior:
#   1. Looks up the auth user by phone.
#   2. Generates a 16-char alphanumeric temp password.
#   3. Updates the password via Admin API.
#   4. Sets must_change_password=true in public.users.
#   5. Prints temp password ONCE. Send to rep via email + WhatsApp.
#
# Requirements:
#   - bash 4+, curl, jq
#   - .env.admin sourced. SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY exported.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/provision.log"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
mask_phone() {
  local p="$1"
  if [[ ${#p} -ge 8 ]]; then echo "${p:0:6}****${p: -4}"; else echo "****"; fi
}
generate_password() {
  # || true: suppress SIGPIPE (exit 141) when head closes the pipe under pipefail.
  local pw
  pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
  [[ ${#pw} -ge 16 ]] || { echo "FATAL: password generation failed" >&2; exit 1; }
  printf '%s' "${pw:0:16}"
}

# --- Args --------------------------------------------------------------------

PHONE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phone) PHONE="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# --- Validation --------------------------------------------------------------

require_cmd curl
require_cmd jq

[[ -n "$PHONE" ]] || die "--phone is required"
[[ "$PHONE" =~ ^\+[1-9][0-9]{7,14}$ ]] \
  || die "Invalid phone format. Expected E.164 like +201012345678"

[[ -n "${SUPABASE_URL:-}" ]]                || die "SUPABASE_URL not set. Source .env.admin."
[[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]   || die "SUPABASE_SERVICE_ROLE_KEY not set. Source .env.admin."

if [[ ! "$SUPABASE_SERVICE_ROLE_KEY" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
  die "SUPABASE_SERVICE_ROLE_KEY does not look like a JWT. Refusing to proceed."
fi

# --- Step 1: Look up user by phone -------------------------------------------

echo ">>> Looking up auth user for $(mask_phone "$PHONE")..."

# Admin API list with phone filter (server-side filter not exposed; pull and grep).
LIST_RESPONSE=$(curl -sS \
  "${SUPABASE_URL}/auth/v1/admin/users?per_page=200" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}")

USER_ID=$(echo "$LIST_RESPONSE" | jq -r --arg p "${PHONE#+}" \
  '.users[]? | select(.phone == $p) | .id' | head -n1)

if [[ -z "$USER_ID" ]]; then
  die "No auth user found with phone $(mask_phone "$PHONE"). Provision first."
fi

echo ">>> Found user: ${USER_ID}"

# --- Step 2: Generate + update password --------------------------------------

TEMP_PASSWORD="$(generate_password)"

UPDATE_PAYLOAD=$(jq -nc --arg pw "$TEMP_PASSWORD" '{password: $pw}')

UPDATE_RESPONSE=$(curl -sS -X PUT \
  "${SUPABASE_URL}/auth/v1/admin/users/${USER_ID}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "$UPDATE_PAYLOAD")

if ! echo "$UPDATE_RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
  echo "Update response:" >&2
  echo "$UPDATE_RESPONSE" | jq . >&2 || echo "$UPDATE_RESPONSE" >&2
  die "Failed to update password."
fi

echo ">>> Password updated."

# --- Step 3: Force must_change_password = true in public.users ---------------

FLAG_PAYLOAD='{"must_change_password": true}'

FLAG_RESPONSE=$(curl -sS -X PATCH \
  "${SUPABASE_URL}/rest/v1/users?id=eq.${USER_ID}" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "$FLAG_PAYLOAD")

if ! echo "$FLAG_RESPONSE" | jq -e '.[0].id' >/dev/null 2>&1; then
  echo "Flag update response:" >&2
  echo "$FLAG_RESPONSE" | jq . >&2 || echo "$FLAG_RESPONSE" >&2
  echo "WARN: must_change_password may not be set. Verify in Dashboard." >&2
fi

# --- Logging (no password) ---------------------------------------------------

echo "${TS}	reset	$(mask_phone "$PHONE")	-	-	${USER_ID}" >> "$LOG_FILE"

# --- Output ------------------------------------------------------------------

cat <<EOF

=========================================================
  PASSWORD RESET
=========================================================
  Phone (login):   ${PHONE}
  Auth user ID:    ${USER_ID}
  Temp password:   ${TEMP_PASSWORD}
=========================================================
  ACTION REQUIRED:
    1. Copy temp password to your password manager NOW.
    2. Send to rep via EMAIL + WHATSAPP (manual).
    3. Rep will be forced to change on next login.
    4. This password will NOT be shown again.
=========================================================
EOF
