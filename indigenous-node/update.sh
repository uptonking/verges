#!/usr/bin/env bash
# Update 3x-ui to the version pinned in config.env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

echo "=== updating 3x-ui to ${XUI_VERSION} ==="

export XUI_NONINTERACTIVE=1
export XUI_DB_TYPE=sqlite
export XUI_ENABLE_FAIL2BAN=false
export XUI_USERNAME="${XUI_PANEL_USERNAME}"
export XUI_PASSWORD="${XUI_PANEL_PASSWORD}"
export XUI_PANEL_PORT="${XUI_PANEL_PORT}"
export XUI_WEB_BASE_PATH="${XUI_WEB_BASE_PATH}"

if ! bash <(curl -fsSL "https://raw.githubusercontent.com/MHSanaei/3x-ui/main/install.sh") "${XUI_VERSION}"; then
	echo "ERROR: 3x-ui update failed" >&2
	exit 1
fi

# Re-apply tuning envs.
cat > /etc/default/x-ui <<EOF
XUI_GOGC=50
XUI_MEMORY_LIMIT=192
XUI_MEMORY_RELEASE_INTERVAL=5
XUI_DB_CACHE_MB=8
XUI_DB_MMAP_MB=32
XUI_DB_JOURNAL_MODE=DELETE
XUI_LOG_LEVEL=warning
EOF

systemctl restart x-ui
sleep 2
./deploy.sh
