#!/usr/bin/env bash
# Apply desired state to 3x-ui: upsert the direct + relay VLESS+Reality inbounds.
#
# The *_INBOUND_ENABLE flags in config.env are the source of truth: a manual
# toggle in the 3x-ui webapp persists until the next ./deploy.sh run.

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
	TOKEN_OUT="$(/usr/local/x-ui/x-ui setting -getApiToken -tokenName automation 2>/dev/null || true)"
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

# --- shared substitution context ---
export NODE_NAME NODE_HOST DOMAIN_NAME CLIENT_ENTRY_HOST CLIENT_ENTRY_PORT \
	XUI_VERSION VLESS_EMAIL REALITY_DEST REALITY_SNI \
	REALITY_FINGERPRINT REALITY_SHORT_IDS XUI_PANEL_PORT XUI_WEB_BASE_PATH \
	XUI_LISTEN_IP SWAP_SIZE_MB BACKUP_KEEP_DAYS \
	VLESS_UUID REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY
export REALITY_SHORT_IDS_JSON="$(short_ids_json)"

# --- upsert one inbound ---
upsert_inbound() {
	local port="$1" tag="$2" remark="$3" enable="$4"

	local enable_bool="false"
	if [ "$enable" = "1" ]; then
		enable_bool="true"
	fi

	# 3x-ui requires unique client emails across inbounds.
	local email="${VLESS_EMAIL}"
	if [ "$tag" = "${RELAY_VLESS_TAG}" ]; then
		email="${VLESS_EMAIL}+relay"
	fi

	export INBOUND_PORT="$port" INBOUND_TAG="$tag" INBOUND_REMARK="$remark" INBOUND_ENABLE="$enable_bool" INBOUND_EMAIL="$email"

	local payload
	payload="$(mktemp)"
	envsubst '${INBOUND_PORT} ${INBOUND_TAG} ${INBOUND_REMARK} ${INBOUND_ENABLE} ${INBOUND_EMAIL} ${VLESS_UUID} ${REALITY_DEST} ${REALITY_SNI} ${REALITY_FINGERPRINT} ${REALITY_SHORT_IDS_JSON} ${REALITY_PRIVATE_KEY} ${REALITY_PUBLIC_KEY}' \
		< lib/inbound.json.template \
		> "$payload"

	if ! jq empty "$payload" 2>/dev/null; then
		echo "ERROR: generated payload for ${tag} is not valid JSON" >&2
		rm -f "$payload"
		exit 1
	fi

	echo "checking existing inbounds for tag ${tag} ..."
	local existing_id
	existing_id="$(api_call GET /panel/api/inbounds/list | jq -r ".obj[] | select(.tag==\"${tag}\") | .id" | head -n1 || true)"

	local inbound_id
	if [ -n "$existing_id" ]; then
		echo "updating inbound id=${existing_id} (port=${port}, enable=${enable})"
		api_call POST "/panel/api/inbounds/update/${existing_id}" -d "@$payload" | jq -r '.msg'
		inbound_id="$existing_id"
	else
		echo "creating inbound (port=${port}, enable=${enable})"
		inbound_id="$(api_call POST /panel/api/inbounds/add -d "@$payload" | jq -r '.obj.id')"
		echo "created inbound id=${inbound_id}"
	fi
	rm -f "$payload"

	# The update/add endpoints ignore the enable field — enforce it explicitly.
	local current_enable
	current_enable="$(api_call GET /panel/api/inbounds/list | jq -r ".obj[] | select(.id==${inbound_id}) | .enable")"
	if [ "$current_enable" != "$enable_bool" ]; then
		api_call POST "/panel/api/inbounds/setEnable/${inbound_id}" \
			-d "{\"enable\":${enable_bool}}" | jq -r '.msg'
	fi
}

upsert_inbound "${DIRECT_VLESS_PORT}" "${DIRECT_VLESS_TAG}" "${NODE_NAME}-direct" "${DIRECT_INBOUND_ENABLE}"
upsert_inbound "${RELAY_VLESS_PORT}" "${RELAY_VLESS_TAG}" "${NODE_NAME}-relay" "${RELAY_INBOUND_ENABLE}"

# Try to set lean xray log config via settings API (best-effort).
api_call POST /panel/api/setting/updateXrayTemplate \
	-d '{"log":{"access":"none","loglevel":"warning","dnsLog":false}}' >/dev/null 2>&1 || true

# Ensure xray picks up changes.
systemctl reload x-ui || systemctl restart x-ui

echo
echo "=== deploy done ==="
./status.sh
