#!/usr/bin/env bash
# Usage: scripts/logs.sh [service...]   e.g. scripts/logs.sh verges
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

compose logs -f --tail=100 "$@"
