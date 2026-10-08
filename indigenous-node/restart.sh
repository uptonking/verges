#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
systemctl restart x-ui
echo "x-ui restarted"
if systemctl is-enabled hysteria2 >/dev/null 2>&1; then
	systemctl restart hysteria2
	echo "hysteria2 restarted"
fi
./status.sh
