# Ubuntu Server Setup

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=flat&logo=gnu-bash&logoColor=white)
![Docker Compose](https://img.shields.io/badge/Docker%20Compose-2496ED?style=flat&logo=docker&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=flat&logo=ubuntu&logoColor=white)
![License](https://img.shields.io/github/license/nuroso000/ubuntu-server-setup)
![Last commit](https://img.shields.io/github/last-commit/nuroso000/ubuntu-server-setup)
![Issues](https://img.shields.io/github/issues/nuroso000/ubuntu-server-setup)
![Stars](https://img.shields.io/github/stars/nuroso000/ubuntu-server-setup?style=social)

One-command setup for a Ubuntu server: Docker, a reverse proxy, monitoring, a
Docker management UI, and an auto-populated dashboard — plus a long list of
optional self-hosted apps you can pick during installation.

## Install

```bash
curl -fsSL -o /tmp/setup.sh https://raw.githubusercontent.com/nuroso000/ubuntu-server-setup/main/setup.sh && sudo bash /tmp/setup.sh
```

This downloads the script first and then runs it, instead of piping it
directly into `sudo bash`. Piping straight into `sudo bash` looks like a single
command too, but it silently swallows the `sudo` password prompt and can
break the interactive menus on some terminals/SSH clients, which looks like
the script is frozen. Download-then-run avoids both problems while still
being one line to paste.

Run it once on a fresh Ubuntu server. It walks you through a few interactive
menus, then does everything else automatically.

## Always installed

- **Homepage** — dashboard, auto-populated with every service you enable (port 3000)

## Choose one (interactive menu)

| Category | Options |
|---|---|
| Reverse proxy | Nginx Proxy Manager, Traefik, or none |
| Monitoring | Uptime Kuma, Gatus, or none |
| Docker management UI | Portainer or Dockge |
| DNS ad-blocker | Pi-hole, AdGuard Home, or none |

## Optional apps (multi-select)

- **IT-Tools** — developer tool collection
- **Nextcloud** (+ MariaDB) — file sync & storage
- **OpenClaw** — self-hosted AI agent, works with the Anthropic Claude API
- **Vaultwarden** — Bitwarden-compatible password manager
- **Gitea** — self-hosted Git server
- **n8n** — workflow automation
- **Watchtower** — automatically updates all containers
- **Jellyfin** — media server
- **File Browser** — web-based file manager
- **WG-Easy** — WireGuard VPN with a web UI
- **Speedtest Tracker** — periodic internet speed logging
- **Immich** — self-hosted photo/video backup (+ Postgres/Redis)

Every service you enable is automatically added as a tile on the Homepage
dashboard.

## After installation

- Change default passwords immediately: Nginx Proxy Manager (`admin@example.com` / `changeme`), Pi-hole, Vaultwarden, WG-Easy, File Browser.
- If you enabled WG-Easy, edit `WG_HOST` in `/opt/homelab/docker-compose.yml` to your server's public IP or domain, then re-run `docker compose up -d`.
- If you enabled Nginx Proxy Manager or Traefik, add proxy hosts / labels for your own domains.
- Change the Nextcloud/Immich database passwords in `docker-compose.yml` before exposing them beyond your local network.
- All config and data files live under `/opt/homelab`.

## Updating the script

```bash
git add . && git commit -m "..." && git push
```

The `curl | sudo bash` command always pulls the latest version from `main`.
