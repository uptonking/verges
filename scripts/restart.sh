#!/usr/bin/env bash
# Restart all running services.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

compose restart
compose ps
