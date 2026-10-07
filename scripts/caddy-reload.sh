#!/usr/bin/env bash
# Validate and gracefully reload the Caddyfile (no downtime).
# /etc/caddy is mounted read-only, so no formatting is done here.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

compose exec caddy caddy validate --config /etc/caddy/Caddyfile
compose exec caddy caddy reload --config /etc/caddy/Caddyfile
