# indigenous-node

Self-contained automation for a small Debian/Ubuntu VPS running **3x-ui + xray-core** with **VLESS + REALITY** inbounds.

This node is the "good IP" egress point. Each mode comes in two transports:

| Mode | Client entry | Transport | Latency (from CN) |
|------|--------------|-----------|-------------------|
| `edge-direct-hy2` | `edge-direct.<domain>:443` udp | Hysteria2/QUIC (standalone, not 3x-ui) | ~1 RTT — fastest |
| `edge-relay-hy2` | `edge.<domain>:8443` udp | Hysteria2 via primary gost UDP relay | ~2 RTT (double hop) |
| `edge-direct` | `edge-direct.<domain>:443` | VLESS+Reality | ~3 RTT (TCP+TLS) |
| `edge-relay` | `edge.<domain>:8443` | VLESS+Reality via primary gost TCP relay | ~3 RTT + hop |

**Use `edge-direct-hy2` by default.** The VLESS modes are the fallback for networks that block/throttle UDP. All four share the same egress IP and (per transport) credentials.

**Switching modes:**

1. **Client-side** (no server change): pick the other proxy — all four are printed by `./client.sh`.
2. **3x-ui webapp**: toggle the inbound's enable switch (immediate effect). Note: the next `./deploy.sh` re-applies the `*_INBOUND_ENABLE` flags from `config.env`.
3. **Config flags**: edit `DIRECT_INBOUND_ENABLE` / `RELAY_INBOUND_ENABLE` in `config.env`, then `./deploy.sh`.

## Quick start

```bash
# On the indigenous VPS, as root
git clone https://github.com/uptonking/verges.git /opt/verges
cd /opt/verges/indigenous-node
./bootstrap.sh
```

`bootstrap.sh` is idempotent: re-running it keeps existing `.env` secrets.

## Files

| File | Purpose |
|------|---------|
| `config.env` | Committed desired state: versions, ports, Reality target, etc. |
| `.env` | Generated secrets: panel creds, API token, UUID, Reality keys. |
| `lib/common.sh` | Shared helpers and env validation. |
| `lib/inbound.json.template` | 3x-ui VLESS+Reality inbound payload template. |
| `bootstrap.sh` | Fresh-VPS setup. |
| `deploy.sh` | Apply `config.env`/`.env` to 3x-ui via its API. |
| `restart.sh`, `stop.sh`, `status.sh`, `logs.sh` | Lifecycle helpers. |
| `update.sh` | Bump `XUI_VERSION` in `config.env` and reinstall. |
| `backup.sh`, `restore.sh` | Daily backup + restore. |
| `client.sh` | Print vless:// link and Clash/sing-box snippets. |

## Re-deploying after config changes

Edit `config.env` (or update DNS), then:

```bash
./deploy.sh
```

## Migrating to another VPS

1. Copy `/opt/verges/indigenous-node` to the new VPS.
2. Copy `.env` and `/etc/x-ui/x-ui.db` to the new VPS.
3. Update `NODE_HOST` and DNS `edge-direct` A record in Cloudflare.
4. Run `./bootstrap.sh` or `./deploy.sh`.

Data loss on IP change is acceptable per project rules; manual migration of `/etc/x-ui/x-ui.db` and `.env` is required.

## Panel access

The 3x-ui panel is bound to `127.0.0.1`. Access it via an SSH tunnel:

```bash
ssh -L 2053:127.0.0.1:2053 root@76.9.111.231
# Then open http://127.0.0.1:2053/xui
```

## Client routing

Use the output of `./client.sh` (both `edge-relay` and `edge-direct` are emitted). Only route traffic that needs the good IP through this node; keep other traffic on `verges` (Hysteria2) or direct.
