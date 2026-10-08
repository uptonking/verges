#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
journalctl -u x-ui -f --tail=100 "$@"
