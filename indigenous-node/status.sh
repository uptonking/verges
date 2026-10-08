#!/usr/bin/env bash
# Health/status summary for the indigenous node.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

echo "=== 3x-ui service ==="
systemctl is-active x-ui || true
systemctl is-enabled x-ui || true

echo
echo "=== hysteria2 service ==="
systemctl is-active hysteria2 || true
systemctl is-enabled hysteria2 || true

echo
echo "=== listeners ==="
ss -tlnp | grep -E ":(${DIRECT_VLESS_PORT}|${RELAY_VLESS_PORT}|${XUI_PANEL_PORT})\b" || true
ss -ulnp | grep -E ":${HY2_PORT}\b" || true

echo
echo "=== xray version ==="
XRAY_BIN="$(xray_bin || true)"
if [ -n "$XRAY_BIN" ] && [ -x "$XRAY_BIN" ]; then
	"$XRAY_BIN" -version 2>/dev/null | head -n3 || true
else
	echo "xray binary not found"
fi

echo
echo "=== 3x-ui API health ==="
if [ -n "$XUI_API_TOKEN" ]; then
	if curl -fsS -H "Authorization: Bearer ${XUI_API_TOKEN}" "$(panel_url)/panel/api/inbounds/list" >/dev/null 2>&1; then
		echo "API OK"
	else
		echo "API unreachable or token invalid"
	fi
else
	echo "API token not set"
fi

echo
echo "=== resources ==="
free -m | head -2
df -h /

echo
echo "=== modes ==="
echo "direct (standalone): ${NODE_HOST}:${DIRECT_VLESS_PORT} enable=${DIRECT_INBOUND_ENABLE}"
echo "relay  (via primary): ${CLIENT_ENTRY_HOST}:${CLIENT_ENTRY_PORT} -> ${NODE_HOST}:${RELAY_VLESS_PORT} enable=${RELAY_INBOUND_ENABLE}"
