#!/usr/bin/env bash
# Apply desired state to 3x-ui: upsert the VLESS+Reality inbound.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

echo "=== indigenous-node deploy ==="

# --- ensure x-ui is running ---
if ! systemctl is-active x-ui >/dev/null 2>&1; then
	systemctl start x-ui
fi
systemctl enable x-ui >/dev/null 2>&1 || true

# --- ensure API token is valid ---
BASE_URL="$(panel_url)"
API_TOKEN="${XUI_API_TOKEN:-}"

api_call() {
	local method="$1"
	local path="$2"
	shift 2
	curl -fsSL -X "$method" \
		-H "Authorization: Bearer ${API_TOKEN}" \
		-H "Content-Type: application/json" \
		"${BASE_URL}${path}" "$@"
}

test_token() {
	curl -fsS -H "Authorization: Bearer ${API_TOKEN}" "${BASE_URL}/panel/api/inbounds/list" >/dev/null 2>&1
}

if [ -z "$API_TOKEN" ] || ! test_token; then
	echo "minting/regenerating 3x-ui API token ..."
	TOKEN_OUT="$(/usr/local/xui/x-ui setting -getApiToken -tokenName automation 2>/dev/null || true)"
	API_TOKEN="$(echo "$TOKEN_OUT" | awk '/apiToken:/{print $2}' | head -n1)"
	if [ -z "$API_TOKEN" ]; then
		echo "ERROR: could not obtain 3x-ui API token" >&2
		exit 1
	fi
	# Persist new token in .env
	if grep -q '^XUI_API_TOKEN=' .env; then
		sed -i "s|^XUI_API_TOKEN=.*|XUI_API_TOKEN=${API_TOKEN}|" .env
	else
		echo "XUI_API_TOKEN=${API_TOKEN}" >> .env
	fi
	chmod 600 .env
	# Re-source env
	# shellcheck source=lib/common.sh
	. "$SCRIPT_DIR/lib/common.sh"
fi

# --- build inbound payload ---
export NODE_NAME NODE_HOST DOMAIN_NAME CLIENT_ENTRY_HOST CLIENT_ENTRY_PORT \
	XUI_VERSION VLESS_PORT VLESS_TAG VLESS_EMAIL REALITY_DEST REALITY_SNI \
	REALITY_FINGERPRINT REALITY_SHORT_IDS XUI_PANEL_PORT XUI_WEB_BASE_PATH \
	XUI_LISTEN_IP SWAP_SIZE_MB BACKUP_KEEP_DAYS \
	VLESS_UUID REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY
export REALITY_SHORT_IDS_JSON="$(short_ids_json)"

TMP_PAYLOAD="$(mktemp)"
trap 'rm -f "$TMP_PAYLOAD"' EXIT

envsubst '${NODE_NAME} ${VLESS_PORT} ${VLESS_TAG} ${VLESS_EMAIL} ${REALITY_DEST} ${REALITY_SNI} ${REALITY_FINGERPRINT} ${REALITY_SHORT_IDS_JSON} ${REALITY_PRIVATE_KEY} ${REALITY_PUBLIC_KEY} ${VLESS_UUID}' \
	< lib/inbound.json.template \
	> "$TMP_PAYLOAD"

# Validate JSON.
if ! jq empty "$TMP_PAYLOAD" 2>/dev/null; then
	echo "ERROR: generated inbound payload is not valid JSON" >&2
	exit 1
fi

# --- upsert inbound by tag ---
echo "checking existing inbounds for tag ${VLESS_TAG} ..."
EXISTING_ID="$(api_call GET /panel/api/inbounds/list | jq -r ".obj[] | select(.tag==\"${VLESS_TAG}\") | .id" | head -n1 || true)"

if [ -n "$EXISTING_ID" ]; then
	echo "updating inbound id=${EXISTING_ID}"
	api_call POST "/panel/api/inbounds/update/${EXISTING_ID}" -d "@$TMP_PAYLOAD" | jq .
else
	echo "creating inbound"
	api_call POST /panel/api/inbounds/add -d "@$TMP_PAYLOAD" | jq .
fi

# Try to set lean xray log config via settings API (best-effort).
api_call POST /panel/api/setting/updateXrayTemplate \
	-d '{"log":{"access":"none","loglevel":"warning","dnsLog":false}}' >/dev/null 2>&1 || true

# Ensure xray picks up changes.
systemctl reload x-ui || systemctl restart x-ui

echo
echo "=== deploy done ==="
./status.sh
