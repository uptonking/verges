# verges — single-node VPS docker services stack

Reproducible Docker stack for a single VPS: [Caddy](https://caddyserver.com/) (automatic TLS, the entrypoint for all HTTP traffic) + [Hysteria 2](https://v2.hysteria.network/) proxy (`verges` service, UDP/QUIC 443) sharing one Let's Encrypt certificate. Config-as-code: desired state lives in git, secrets stay on the VPS.

## Architecture

```
                      Internet
                          |
        +-----------------+------------------+
        |                 |                  |
   TCP 80/443   UDP 443 + 20000-30000    (any client)
        |                 |                  |
  +-----v-----+    +------v------+           |
  |   caddy   |    |    verges   |           |
  | TLS entry |    | hysteria2   |           |
  | h1/h2 only|    | QUIC proxy  |           |
  +-----+-----+    +------+------+           |
        |                 |  masquerade      |
        |  +--------------+  (in-network)    |
        +->| shared_network (bridge) |<------+
           +-------------------------+

  cert flow: caddy obtains/renews LE cert for verges.<domain>
             -> stored in ./data/caddy
             -> mounted read-only into verges
             -> hysteria hot-reloads on renewal (no restart)
```

- **caddy** always runs: TCP 80 (ACME HTTP-01 + redirects) and TCP 443 (HTTPS, h1/h2 — HTTP/3 is disabled because UDP 443 belongs to verges).
- **verges** (Hysteria 2): UDP 443 + server-side port hopping range (default `20000-30000/udp`), enabled/disabled via compose profiles. Unauthenticated traffic is masqueraded to caddy in-network (`It works!` page), so the endpoint looks like a normal HTTPS site.

## Quickstart (fresh VPS)

Prerequisite: a DNS A record `verges.<your-domain>` → VPS IP (DNS-only, no proxy).

```bash
ssh root@<vps>
git clone https://github.com/uptonking/verges.git /opt/verges
cd /opt/verges
scripts/bootstrap.sh
```

Bootstrap checks prerequisites, generates `.env` (secrets) interactively, verifies DNS, adds ufw rules, starts the stack, waits for the certificate, and prints the Hysteria2 client URI.

## Operations (always use the scripts)

| Command | Purpose |
|---|---|
| `scripts/bootstrap.sh` | One-time setup on a fresh VPS |
| `scripts/deploy.sh` | Apply latest git state (pull + regen configs + recreate). Also the enable/disable path. |
| `scripts/restart.sh` | Restart all services |
| `scripts/stop.sh` | Stop all services (containers kept; they return after reboot) |
| `scripts/status.sh` | Containers, DNS, listeners, certificate, client URI |
| `scripts/logs.sh [svc]` | Follow logs (e.g. `scripts/logs.sh verges`) |
| `scripts/update.sh` | Re-pull the pinned images and recreate |
| `scripts/caddy-reload.sh` | Validate + gracefully reload Caddyfile |

Plain `docker compose` also works for inspection but misses `config.env` (profiles, domain) — the scripts pass `--env-file config.env --env-file .env` on every invocation.

## Configuration model

| File | Committed? | Contents |
|---|---|---|
| `config.env` | yes | Desired state: `COMPOSE_PROFILES`, `DOMAIN_NAME`, `VERGES_PORT`, `VERGES_HOP_RANGE`, image pins |
| `.env` | no (generated) | Secrets only: `SSL_EMAIL`, `VERGES_PASSWORD` |
| `caddy/` | yes | Caddyfile + per-site files (`import sites/*.caddy`) |
| `services/verges/config.yaml.template` | yes | Hysteria config template (envsubst → generated `config.yaml`, gitignored) |
| `data/` | no | Runtime data (caddy certificate storage) |

### Daily flow

1. Edit locally (e.g. toggle a service, change ports/domain), commit, push to GitHub.
2. On the VPS: `cd /opt/verges && scripts/deploy.sh`.

### Enable / disable services

Services run behind compose profiles; caddy has no profile (always on). To disable verges:

```bash
# in config.env:  COMPOSE_PROFILES=
git commit -am "disable verges" && git push
# on VPS:
scripts/deploy.sh   # --remove-orphans removes the disabled container
```

Re-enable with `COMPOSE_PROFILES=verges`.

### Changing the VPS IP

Update only the DNS A record for `verges.<domain>` to point to the new VPS IP. The repo no longer stores the VPS IP. Data (certificates) can be migrated manually by copying `data/`; otherwise a fresh bootstrap on the new VPS re-issues everything.

## Client setup

`scripts/status.sh` prints the ready-to-use URI:

```
hysteria2://<password>@verges.<domain>:443?sni=verges.<domain>&insecure=0
```

For clients that support port hopping (e.g. Clash.Meta), also configure `ports: 20000-30000` and `hop-interval: 30`.

Works with any Hysteria2 client (official CLI, sing-box, Clash.Meta, Stash, Shadowrocket, ...).

## Notes

- **Reboot recovery**: all services use `restart: always` and docker is enabled via systemd — no extra units needed. Services come back with the same data/config automatically.
- **Certificates**: caddy renews automatically; hysteria checks cert file mtimes on every handshake and hot-reloads — no restarts on renewal (~60-day cycle).
- **ufw**: docker-published ports bypass ufw (iptables ordering); rules are added anyway for intent/defense-in-depth. Never remove the SSH rule.
- **Reproducibility**: image versions are pinned in `config.env`. Bump a tag, push, `scripts/deploy.sh` (or `scripts/update.sh` to re-pull only).
- **Adding services**: add a compose service (with its own profile) on `shared_network`, add a `caddy/sites/<name>.caddy` site file, add a template under `services/<name>/` if config generation is needed, extend `scripts/lib/common.sh::gen_configs`.
- **Opsec**: this repo is public and reveals the domain/IP running Hysteria2; password auth is the only gate. Make the repo private if that matters to you.

## Credits

- Built on top of / inspired by [AiratTop/caddy-self-hosted](https://github.com/AiratTop/caddy-self-hosted) (MIT).
- [HyNetworks/hysteria](https://github.com/HyNetworks/hysteria) (official image `tobyxdd/hysteria`).

## License

MIT — see [LICENSE.md](LICENSE.md).
