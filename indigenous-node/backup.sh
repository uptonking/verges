#!/usr/bin/env bash
# Daily backup of 3x-ui state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

mkdir -p /root/backups
TS="$(date +%Y%m%d-%H%M%S)"
OUT="/root/backups/xui-${TS}.tar.gz"

tar czf "$OUT" \
	/etc/x-ui \
	/usr/local/x-ui/bin/config.json \
	/etc/default/x-ui \
	"$SCRIPT_DIR/.env" \
	"$SCRIPT_DIR/config.env" \
	"$SCRIPT_DIR/certs" \
	2>/dev/null

chmod 600 "$OUT"
find /root/backups -name 'xui-*.tar.gz' -mtime +"${BACKUP_KEEP_DAYS}" -delete

echo "backup: $OUT"
