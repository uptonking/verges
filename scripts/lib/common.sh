#!/usr/bin/env bash
# Shared helpers for verges stack scripts. Source this file, don't execute it.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR"

CONFIG_ENV="config.env"
SECRETS_ENV=".env"

if [ ! -f "$CONFIG_ENV" ]; then
	echo "ERROR: $CONFIG_ENV not found — run inside the repo clone." >&2
	exit 1
fi
if [ ! -f "$SECRETS_ENV" ]; then
	echo "ERROR: $SECRETS_ENV not found. Create it:" >&2
	echo "  cp .env.example .env   # then edit, or run scripts/bootstrap.sh" >&2
	exit 1
fi

set -a
# shellcheck source=/dev/null
. "$CONFIG_ENV"
# shellcheck source=/dev/null
. "$SECRETS_ENV"
set +a

: "${DOMAIN_NAME:?DOMAIN_NAME must be set in $CONFIG_ENV}"
: "${SSL_EMAIL:?SSL_EMAIL must be set in $SECRETS_ENV}"
: "${VERGES_PORT:=443}"
: "${VERGES_HOP_RANGE:=20000-30000}"
: "${CADDY_IMAGE:=caddy:2.10.2}"
: "${VERGES_IMAGE:=tobyxdd/hysteria:v2.13.0}"
: "${FORWARD_HOST:=edge.aichorage.de}"
: "${FORWARD_PORT:=8443}"
: "${FORWARD_TARGET:=edge-direct.aichorage.de:8443}"
: "${FORWARD_TARGET_UDP:=edge-direct.aichorage.de:443}"
: "${GOST_IMAGE:=gogost/gost:3.3.0}"

VERGES_HOST="verges.${DOMAIN_NAME}"
FORWARD_ENTRY="${FORWARD_HOST}:${FORWARD_PORT}"
FORWARD_ENABLED=0
case ",${COMPOSE_PROFILES:-}," in
*,forward,*) FORWARD_ENABLED=1 ;;
esac
VERGES_ENABLED=0
case ",${COMPOSE_PROFILES:-}," in
*,verges,*) VERGES_ENABLED=1 ;;
esac
if [ "$VERGES_ENABLED" -eq 1 ]; then
	: "${VERGES_PASSWORD:?VERGES_PASSWORD must be set in $SECRETS_ENV (profile 'verges' is enabled)}"
fi

# All docker compose invocations must include both env files:
# config.env (desired state) is NOT auto-loaded by compose.
compose() {
	docker compose --env-file "$CONFIG_ENV" --env-file "$SECRETS_ENV" "$@"
}

warn() { echo "WARN: $*" >&2; }

# Resolve the certificate path (glob covers the CA directory).
# NOTE: glob must stay unquoted so it expands.
cert_path() {
	# shellcheck disable=SC2145
	ls data/caddy/caddy/certificates/*/"$VERGES_HOST"/"$VERGES_HOST".crt 2>/dev/null | head -n1 || true
}

check_dns() {
	local resolved
	resolved="$(getent hosts "$VERGES_HOST" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
	if [ -z "$resolved" ]; then
		warn "$VERGES_HOST has no DNS A record. Certificate issuance will fail until the DNS record points to this VPS."
	else
		echo "DNS OK: $VERGES_HOST -> $resolved"
	fi
	if [ "$FORWARD_ENABLED" -eq 1 ]; then
		resolved="$(getent hosts "$FORWARD_HOST" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
		if [ -z "$resolved" ]; then
			warn "$FORWARD_HOST has no DNS A record. gost clients will not be able to connect."
		else
			echo "DNS OK: $FORWARD_HOST -> $resolved"
		fi
	fi
}

tune_system() {
	local sysctl_file="/etc/sysctl.d/99-verges-tuning.conf"
	if [ -w /etc/sysctl.d ]; then
		cat > "$sysctl_file" <<'EOF'
# BBR and queue discipline
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# TCP Fast Open (3 = client + server)
net.ipv4.tcp_fastopen = 3

# Disable broken/unreachable IPv6 to eliminate lookup & fallback latency
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Buffer sizes for high BDP paths (up to 64MB UDP/TCP buffers)
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# Latency, socket recycling, and network backlog
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
EOF
		sysctl --system >/dev/null 2>&1 || true
		echo "applied sysctl tuning ($sysctl_file)"
	fi

	local iface
	iface="$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1 || true)"
	if [ -n "$iface" ]; then
		ip link set dev "$iface" mtu 1500 2>/dev/null || true
		ip link set dev "$iface" txqueuelen 10000 2>/dev/null || true
		tc qdisc replace dev "$iface" root fq 2>/dev/null || true
		if command -v ethtool >/dev/null 2>&1; then
			ethtool -K "$iface" tx-udp-segmentation off 2>/dev/null || true
		fi
		echo "tuned interface $iface (mtu 1500, txqueuelen 10000, qdisc fq, tx-udp-segmentation off)"
	fi
}

gen_configs() {
	command -v envsubst >/dev/null 2>&1 || {
		echo "ERROR: envsubst not found — install with: apt-get install -y gettext-base" >&2
		exit 1
	}
	if [ "$VERGES_ENABLED" -eq 1 ]; then
		envsubst '${DOMAIN_NAME} ${VERGES_PASSWORD} ${VERGES_HOP_RANGE}' \
			<services/verges/config.yaml.template \
			>services/verges/config.yaml
		chmod 600 services/verges/config.yaml
		echo "generated services/verges/config.yaml"
	fi
}

client_uri() {
	echo "hysteria2://${VERGES_PASSWORD}@${VERGES_HOST}:${VERGES_PORT}?sni=${VERGES_HOST}&insecure=0"
}

forward_uri() {
	echo "vless+reality entry: ${FORWARD_ENTRY} -> ${FORWARD_TARGET}"
}

wait_for_cert() {
	local i=0
	until [ -n "$(cert_path)" ]; do
		i=$((i + 1))
		if [ "$i" -ge 150 ]; then
			warn "certificate not found after 300s"
			echo "check: scripts/logs.sh caddy   (DNS? ports 80/443 reachable? Let's Encrypt rate limits?)" >&2
			return 1
		fi
		sleep 2
	done
	echo "certificate ready: $(cert_path)"
}
