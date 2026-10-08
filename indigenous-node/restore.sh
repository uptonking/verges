#!/usr/bin/env bash
# Restore 3x-ui state from a backup tarball.
set -euo pipefail

if [ $# -ne 1 ]; then
	echo "Usage: $0 <backup.tar.gz>" >&2
	exit 1
fi
BACKUP="$1"
if [ ! -f "$BACKUP" ]; then
	echo "ERROR: backup file not found: $BACKUP" >&2
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "extracting backup ..."
tar xzf "$BACKUP" -C "$TMP"

systemctl stop x-ui || true

cp -a "$TMP/etc/x-ui" /etc/
cp -a "$TMP/usr/local/x-ui/bin/config.json" /usr/local/x-ui/bin/config.json
cp -a "$TMP/etc/default/x-ui" /etc/default/x-ui

if [ -f "$TMP$SCRIPT_DIR/.env" ]; then
	cp -a "$TMP$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env"
	chmod 600 "$SCRIPT_DIR/.env"
fi

systemctl start x-ui
sleep 3
./deploy.sh
./status.sh
