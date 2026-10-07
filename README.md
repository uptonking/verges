# verge docker services

This repository provides a `docker-compose` setup to run a self-hosted [Caddy](https://caddyserver.com/) reverse proxy.

It is configured to connect to a shared Docker network, allowing easy integration with other services like n8n.

## Features

- Uses the official Caddy Docker image.
- Automatic HTTPS via Let's Encrypt.
- Data is persisted in a local volume.
- Pre-configured for a shared network.
- Includes scripts for easy management.

## Getting Started

1. **Clone the repository:**

```bash
git clone https://github.com/AiratTop/caddy-self-hosted.git
cd caddy-self-hosted
```

2. **Create the shared network:**
   If you haven't already, create the shared Docker network:

```bash
docker network create shared_network
```

3. **Set your domain:**
   Edit the `.env` file and set `DOMAIN_NAME` to your primary domain (for example, `DOMAIN_NAME=example.com` ) and `SSL_EMAIL` .

```bash
cp .env.example .env
```

4. **Configure Caddyfile:**
   Open the `config/Caddyfile` file and adjust any reverse-proxy blocks you need.

5. **Start the service:**

```bash
docker compose up -d
```

## Usage

- **Start:** `docker compose up -d`
- **Stop:** `docker compose down`
- **Restart:** `./restart-docker.sh`
- **Update:** `./update-docker.sh` (Pulls the latest Docker image and restarts)

## Connecting with other services

This setup is designed to work with other services on the `shared_network` . To add a new service, add a new block to the `Caddyfile` in the `config` directory.

## Notes

- built on top of or inspired by the following projects:
  - https://github.com/AiratTop/caddy-self-hosted /MIT

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
