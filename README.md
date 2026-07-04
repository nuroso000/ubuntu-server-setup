# Ubuntu Server Setup

Ein-Kommando-Setup fuer einen Ubuntu-Server mit Docker, Reverse Proxy, Monitoring
und Dashboard.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/nuroso000/ubuntu-server-setup/main/setup.sh | sudo bash
```

## Immer installiert

- Nginx Proxy Manager (Reverse Proxy, Port 81/80/443)
- Uptime Kuma (Monitoring, Port 3001)
- Homepage (Dashboard, Port 3000)
- Portainer *oder* Dockge (waehlbar waehrend der Installation)

## Optional (Mehrfachauswahl waehrend der Installation)

- IT-Tools
- Nextcloud (+ MariaDB)
- OpenClaw (selbstgehosteter KI-Agent, nutzbar mit der Anthropic Claude API)
- Vaultwarden (Passwort-Manager)
- Gitea (Git-Server)
- n8n (Automatisierung)
- Pi-hole (Werbe-/Tracker-Blocker)
- Watchtower (automatische Container-Updates)

Alle ausgewaehlten Dienste werden automatisch als Kacheln im Homepage-Dashboard
angezeigt.

## Nach der Installation

- Standard-Login von Nginx Proxy Manager sofort aendern (admin@example.com / changeme).
- Bei Nextcloud die DB-Passwoerter in `/opt/homelab/docker-compose.yml` anpassen.
- Bei Pi-hole und Vaultwarden Standardpasswoerter aendern.
- Alle Konfigurations- und Datendateien liegen unter `/opt/homelab`.
