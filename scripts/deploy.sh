#!/usr/bin/env bash
# Apply desired state: pull latest repo, regenerate configs, (re)create services.
# This is also how you enable/disable services after editing
# COMPOSE_PROFILES in config.env (--remove-orphans cleans up).

set -euo pipefail
cd "$(dirname "$0")/.."

git pull --ff-only

# shellcheck source=scripts/lib/common.sh
. scripts/lib/common.sh

check_dns
gen_configs
compose up -d --remove-orphans
compose ps

if [ "$VERGES_ENABLED" -eq 1 ]; then
	echo "client URI:"
	client_uri
fi
