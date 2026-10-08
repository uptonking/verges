#!/usr/bin/env bash
# Shared helpers for indigenous-node scripts. Source this file, don't execute it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

CONFIG_ENV="config.env"
SECRETS_ENV=".env"

if [ ! -f "$CONFIG_ENV" ]; then
	echo "ERROR: $CONFIG_ENV not found — run inside the indigenous-node directory." >&2
	exit 1
fi

if [ ! -f "$SECRETS_ENV" ]; then
	echo "ERROR: $SECRETS_ENV not found. Create it:" >&2
	echo "  cp .env.example .env   # or run ./bootstrap.sh" >&2
	exit 1
fi

set -a
# shellcheck source=/dev/null
. "$CONFIG_ENV"
# shellcheck source=/dev/null
. "$SECRETS_ENV"
set +a

: "${NODE_NAME:?NODE_NAME must be set in $CONFIG_ENV}"
: "${NODE_HOST:?NODE_HOST must be set in $CONFIG_ENV}"
: "${DOMAIN_NAME:?DOMAIN_NAME must be set in $CONFIG_ENV}"
: "${CLIENT_ENTRY_HOST:?CLIENT_ENTRY_HOST must be set in $CONFIG_ENV}"
: "${CLIENT_ENTRY_PORT:?CLIENT_ENTRY_PORT must be set in $CONFIG_ENV}"
: "${XUI_VERSION:?XUI_VERSION must be set in $CONFIG_ENV}"
: "${XRAY_VERSION:=v26.6.27}"
: "${DIRECT_VLESS_PORT:=443}"
: "${DIRECT_VLESS_TAG:=in-443-vless-reality}"
: "${DIRECT_INBOUND_ENABLE:=1}"
: "${RELAY_VLESS_PORT:=8443}"
: "${RELAY_VLESS_TAG:=in-8443-vless-reality}"
: "${RELAY_INBOUND_ENABLE:=1}"
: "${VLESS_EMAIL:?VLESS_EMAIL must be set in $CONFIG_ENV}"
: "${REALITY_DEST:?REALITY_DEST must be set in $CONFIG_ENV}"
: "${REALITY_SNI:?REALITY_SNI must be set in $CONFIG_ENV}"
: "${REALITY_FINGERPRINT:?REALITY_FINGERPRINT must be set in $CONFIG_ENV}"
: "${REALITY_MIN_CLIENT_VER:=1.8.2}"
: "${REALITY_SHORT_IDS:?REALITY_SHORT_IDS must be set in $CONFIG_ENV}"
: "${XUI_PANEL_PORT:?XUI_PANEL_PORT must be set in $CONFIG_ENV}"
: "${XUI_WEB_BASE_PATH:?XUI_WEB_BASE_PATH must be set in $CONFIG_ENV}"
: "${XUI_LISTEN_IP:?XUI_LISTEN_IP must be set in $CONFIG_ENV}"
: "${SWAP_SIZE_MB:=256}"
: "${BACKUP_KEEP_DAYS:=7}"
: "${HY2_PORT:=443}"
: "${HY2_VERSION:=app/v2.13.0}"
: "${HY2_CERT:=$SCRIPT_DIR/certs/hy2.crt}"
: "${HY2_KEY:=$SCRIPT_DIR/certs/hy2.key}"
: "${GENERATED_DIR:=$SCRIPT_DIR/generated}"

: "${XUI_PANEL_USERNAME:?XUI_PANEL_USERNAME must be set in $SECRETS_ENV}"
: "${XUI_PANEL_PASSWORD:?XUI_PANEL_PASSWORD must be set in $SECRETS_ENV}"
: "${HY2_PASSWORD:?HY2_PASSWORD must be set in $SECRETS_ENV}"

warn() { echo "WARN: $*" >&2; }

panel_url() {
	echo "http://${XUI_LISTEN_IP}:${XUI_PANEL_PORT}${XUI_WEB_BASE_PATH}"
}

xui_cli() {
	echo "/usr/local/x-ui/x-ui"
}

# Install (or keep) the pinned hysteria2 binary. Idempotent; downloads only
# when the binary is missing or its version differs from HY2_VERSION.
install_hysteria() {
	local want="${HY2_VERSION#app/}"
	if [ -x /usr/local/bin/hysteria ] && /usr/local/bin/hysteria version 2>/dev/null | grep -q "${want}"; then
		return 0
	fi
	echo "installing hysteria ${HY2_VERSION} ..."
	local tmp
	tmp="$(mktemp -d)"
	curl -fsSL -o "${tmp}/hysteria" "https://github.com/apernet/hysteria/releases/download/${HY2_VERSION}/hysteria-linux-amd64"
	install -m 0755 "${tmp}/hysteria" /usr/local/bin/hysteria
	rm -rf "${tmp}"
}

ensure_hy2_certs() {
	if [ ! -f "${HY2_CERT}" ] || [ ! -f "${HY2_KEY}" ]; then
		mkdir -p "$(dirname "${HY2_CERT}")"
		openssl ecparam -genkey -name prime256v1 -out "${HY2_KEY}"
		openssl req -x509 -new -key "${HY2_KEY}" -sha256 -days 3650 \
			-subj "/CN=${NODE_HOST}" \
			-addext "subjectAltName=DNS:${NODE_HOST}" \
			-out "${HY2_CERT}"
		chmod 600 "${HY2_KEY}"
		echo "generated hy2 self-signed cert for ${NODE_HOST}"
	fi
}

xray_bin() {
	local bin="/usr/local/x-ui/bin/xray-linux-amd64"
	if [ -x "$bin" ]; then
		echo "$bin"
		return 0
	fi
	# fallback: try to find any xray binary in the bin dir
	ls /usr/local/x-ui/bin/xray-linux-* 2>/dev/null | head -n1
}

short_ids_json() {
	# REALITY_SHORT_IDS=a3f1,be42 -> ["a3f1","be42"]
	local ids=""
	local first=1
	for id in $(echo "$REALITY_SHORT_IDS" | tr ',' ' '); do
		id="$(echo "$id" | xargs)"
		[ -n "$id" ] || continue
		if [ "$first" -eq 1 ]; then
			first=0
		else
			ids="${ids},"
		fi
		ids="${ids}\"${id}\""
	done
	echo "[$ids]"
}

first_short_id() {
	echo "$REALITY_SHORT_IDS" | cut -d, -f1 | xargs
}
