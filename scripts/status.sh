#!/usr/bin/env bash
# Stack overview: containers, DNS, port listeners, certificate, client URI.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

echo "=== compose ps ==="
compose ps

echo
echo "=== DNS ==="
check_dns

echo
echo "=== listeners (host) ==="
ss -tlnp | grep -E ':(80|443)\b' || true
ss -ulnp | grep -E ":${VERGES_PORT}\b" || true
if [ -n "${VERGES_HOP_RANGE:-}" ]; then
	ss -ulnp | grep -E ":(${VERGES_HOP_RANGE%-*}|${VERGES_HOP_RANGE#*-})\b" || true
fi
if [ "$FORWARD_ENABLED" -eq 1 ]; then
	ss -tlnp | grep -E ":${FORWARD_PORT}\b" || true
fi

echo
if [ -n "$(cert_path)" ]; then
	echo "=== certificate ==="
	openssl x509 -in "$(cert_path)" -noout -subject -enddate
else
	echo "=== certificate: NOT FOUND (data/caddy/certificates/...) ==="
fi

if [ "$VERGES_ENABLED" -eq 1 ]; then
	echo
	echo "client URI:"
	client_uri
fi
if [ "$FORWARD_ENABLED" -eq 1 ]; then
	echo
	echo "VLESS+Reality relay entry: ${FORWARD_ENTRY} -> ${FORWARD_TARGET}"
fi
