#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
SVC="${1:-all}"
case "$SVC" in
xui|x-ui) shift 2>/dev/null || true; exec journalctl -u x-ui -f --tail=100 "$@" ;;
hy2|hysteria|hysteria2) shift 2>/dev/null || true; exec journalctl -u hysteria2 -f --tail=100 "$@" ;;
*) exec journalctl -u x-ui -u hysteria2 -f --tail=100 "$@" ;;
esac
