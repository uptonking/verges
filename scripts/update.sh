#!/usr/bin/env bash
# Re-pull the image versions pinned in config.env and recreate services.
# For repo changes use scripts/deploy.sh.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

compose pull
compose up -d --remove-orphans
docker image prune -f
compose ps
