#!/usr/bin/env bash
# Generate client configs for both VLESS+Reality modes (direct + relay).
# Both modes share the same UUID / public key / short id — only server:port differs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

if [ -z "$VLESS_UUID" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
	echo "ERROR: VLESS_UUID or REALITY_PUBLIC_KEY not set. Run ./bootstrap.sh first." >&2
	exit 1
fi

SID="$(first_short_id)"

vless_link_relay="vless://${VLESS_UUID}@${CLIENT_ENTRY_HOST}:${CLIENT_ENTRY_PORT}?security=reality&sni=${REALITY_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&sid=${SID}&type=tcp&flow=xtls-rprx-vision#edge-relay"
vless_link_direct="vless://${VLESS_UUID}@${NODE_HOST}:${DIRECT_VLESS_PORT}?security=reality&sni=${REALITY_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&sid=${SID}&type=tcp&flow=xtls-rprx-vision#edge-direct"

vless_proxy_yaml() {
	local name="$1" server="$2" port="$3"
	cat <<EOF
  - name: ${name}
    type: vless
    server: ${server}
    port: ${port}
    uuid: ${VLESS_UUID}
    flow: xtls-rprx-vision
    network: tcp
    udp: true
    tls: true
    servername: ${REALITY_SNI}
    reality-opts:
      public-key: ${REALITY_PUBLIC_KEY}
      short-id: ${SID}
    client-fingerprint: ${REALITY_FINGERPRINT}
EOF
}

echo "=== VLESS+Reality client configs (two modes, same credentials) ==="
echo
echo "--- vless:// links ---"
echo "relay  (via primary): ${vless_link_relay}"
echo "direct (standalone) : ${vless_link_direct}"
echo
echo "--- Clash Meta snippet ---"
{
	echo "proxies:"
	vless_proxy_yaml edge-relay "${CLIENT_ENTRY_HOST}" "${CLIENT_ENTRY_PORT}"
	vless_proxy_yaml edge-direct "${NODE_HOST}" "${DIRECT_VLESS_PORT}"
	cat <<EOF

proxy-groups:
  - name: AI-sites
    type: select
    proxies:
      - edge-relay
      - edge-direct
      - DIRECT

rules:
  - DOMAIN-SUFFIX,openai.com,AI-sites
  - DOMAIN-SUFFIX,chatgpt.com,AI-sites
  - DOMAIN-SUFFIX,anthropic.com,AI-sites
  - DOMAIN-SUFFIX,claude.ai,AI-sites
  - DOMAIN-SUFFIX,gemini.google.com,AI-sites
  - DOMAIN-SUFFIX,aistudio.google.com,AI-sites
  - DOMAIN-SUFFIX,ai.google.dev,AI-sites
  - DOMAIN-SUFFIX,bard.google.com,AI-sites
  - DOMAIN-SUFFIX,copilot.microsoft.com,AI-sites
  - DOMAIN-SUFFIX,perplexity.ai,AI-sites
EOF
}
echo
echo "--- sing-box outbound snippet ---"
cat <<EOF
{
  "outbounds": [
    {
      "type": "vless",
      "tag": "edge-relay",
      "server": "${CLIENT_ENTRY_HOST}",
      "server_port": ${CLIENT_ENTRY_PORT},
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "utls": { "enabled": true, "fingerprint": "${REALITY_FINGERPRINT}" },
        "reality": { "enabled": true, "public_key": "${REALITY_PUBLIC_KEY}", "short_id": "${SID}" }
      }
    },
    {
      "type": "vless",
      "tag": "edge-direct",
      "server": "${NODE_HOST}",
      "server_port": ${DIRECT_VLESS_PORT},
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "utls": { "enabled": true, "fingerprint": "${REALITY_FINGERPRINT}" },
        "reality": { "enabled": true, "public_key": "${REALITY_PUBLIC_KEY}", "short_id": "${SID}" }
      }
    }
  ],
  "route": {
    "rules": [
      {
        "domain_suffix": [
          "openai.com",
          "chatgpt.com",
          "anthropic.com",
          "claude.ai",
          "gemini.google.com",
          "aistudio.google.com",
          "ai.google.dev",
          "bard.google.com",
          "copilot.microsoft.com",
          "perplexity.ai"
        ],
        "outbound": "edge-relay"
      }
    ]
  }
}
EOF
echo
echo "# Tip: switch mode by changing the route rule outbound to \"edge-direct\","
echo "#      or pick the other proxy in the Clash AI-sites group."
