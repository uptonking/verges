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

# Compose profiles are a start gate, not a stop gate: an active profile
# that becomes inactive may leave its container running. Stop + remove it
# idempotently (these commands are no-ops if the container is already gone).
if [ "$VERGES_ENABLED" -eq 0 ]; then
	echo "verges profile disabled — ensuring container is removed"
	compose stop verges >/dev/null 2>&1 || true
	compose rm -f verges >/dev/null 2>&1 || true
fi

compose ps

if [ "$VERGES_ENABLED" -eq 1 ]; then
	echo "client URI:"
	client_uri
fi
