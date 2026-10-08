#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
systemctl stop x-ui
echo "x-ui stopped"
if systemctl is-active hysteria2 >/dev/null 2>&1; then
	systemctl stop hysteria2
	echo "hysteria2 stopped"
fi
