#!/usr/bin/env bash
# Stop all services. Containers are kept; restart:always brings them back on
# daemon restart/reboot. To remove containers entirely: docker compose down
# (they will NOT come back after reboot until the next deploy).
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

compose stop
