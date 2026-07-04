#!/usr/bin/env bash
#
# Ubuntu Server Setup
#
#   Choose a reverse proxy   : Nginx Proxy Manager / Traefik / none
#   Choose a monitoring tool : Uptime Kuma / Gatus / none
#   Choose a Docker UI       : Portainer / Dockge
#   Choose a DNS ad-blocker  : Pi-hole / AdGuard Home / none
#   Homepage dashboard is always installed and auto-populated.
#
#   Plus a long list of optional self-hosted apps (multi-select).
#
# One-liner install (once hosted on GitHub):
#   curl -fsSL -o /tmp/setup.sh https://raw.githubusercontent.com/<user>/<repo>/main/setup.sh && sudo bash /tmp/setup.sh
#
# (Downloading first, then running, avoids sudo swallowing the password
#  prompt and the interactive menus breaking under `curl | sudo bash`.)
#
# Local run:
#   sudo bash setup.sh
#
set -euo pipefail

# When run as `curl ... | sudo bash`, stdin is the pipe carrying this script's
# source, not the terminal -- so interactive prompts (whiptail) can't read
# keypresses. Reattach stdin to the controlling terminal so menus work.
if [[ -r /dev/tty ]]; then
  exec < /dev/tty
fi

BASE_DIR="/opt/homelab"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
HOMEPAGE_CFG="${BASE_DIR}/homepage/config"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if [[ ${EUID} -ne 0 ]]; then
  echo "Please run as root: sudo bash setup.sh" >&2
  exit 1
fi

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "Warning: this script targets Ubuntu Server. Continuing anyway..." >&2
fi

echo "==> Updating package lists"
apt-get update -y

echo "==> Installing base packages"
apt-get install -y ca-certificates curl gnupg whiptail ufw openssl

# ---------------------------------------------------------------------------
# Docker installation (official apt repo)
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  echo "==> Installing Docker Engine"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  ARCH="$(dpkg --print-architecture)"
  CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
  echo \
    "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
else
  echo "==> Docker already installed, skipping"
fi

# Add the invoking (non-root) user to the docker group, if applicable
if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "${SUDO_USER}" || true
fi

# ---------------------------------------------------------------------------
# Reverse proxy choice
# ---------------------------------------------------------------------------
REVERSE_PROXY=$(whiptail --title "Reverse Proxy" --radiolist \
  "Which reverse proxy should manage inbound traffic?" \
  12 74 3 \
  "NPM"     "Nginx Proxy Manager (web UI, easiest to use)" ON \
  "TRAEFIK" "Traefik (label-based, dashboard included)" OFF \
  "NONE"    "Skip, don't install a reverse proxy" OFF \
  3>&1 1>&2 2>&3) || REVERSE_PROXY="NPM"

# ---------------------------------------------------------------------------
# Monitoring choice
# ---------------------------------------------------------------------------
MONITORING=$(whiptail --title "Monitoring" --radiolist \
  "Which uptime/monitoring tool should be installed?" \
  12 74 3 \
  "UPTIMEKUMA" "Uptime Kuma (full-featured, most popular)" ON \
  "GATUS"      "Gatus (lightweight, config-file based)" OFF \
  "NONE"       "Skip, don't install a monitoring tool" OFF \
  3>&1 1>&2 2>&3) || MONITORING="UPTIMEKUMA"

# ---------------------------------------------------------------------------
# Docker management UI choice
# ---------------------------------------------------------------------------
DOCKER_UI=$(whiptail --title "Docker Management UI" --radiolist \
  "Which UI should be used to manage Docker/Compose?" \
  12 74 2 \
  "PORTAINER" "Portainer (full-featured Docker GUI)" ON \
  "DOCKGE"    "Dockge (lightweight Compose stack manager)" OFF \
  3>&1 1>&2 2>&3) || DOCKER_UI="PORTAINER"

# ---------------------------------------------------------------------------
# DNS ad-blocker choice
# ---------------------------------------------------------------------------
DNS_BLOCKER=$(whiptail --title "DNS Ad-Blocker" --radiolist \
  "Which network-wide ad/tracker blocker should be installed (uses port 53)?" \
  12 74 3 \
  "NONE"    "Skip, don't install a DNS blocker" ON \
  "PIHOLE"  "Pi-hole" OFF \
  "ADGUARD" "AdGuard Home" OFF \
  3>&1 1>&2 2>&3) || DNS_BLOCKER="NONE"

# ---------------------------------------------------------------------------
# Optional apps (multi-select)
# ---------------------------------------------------------------------------
SELECTED=$(whiptail --title "Optional Apps" --checklist \
  "Which additional apps should be installed and added to Homepage?" \
  24 78 12 \
  "ITTOOLS"    "IT-Tools (developer tool collection)" OFF \
  "NEXTCLOUD"  "Nextcloud (+ MariaDB) - file sync & storage" OFF \
  "OPENCLAW"   "OpenClaw (self-hosted AI agent, works with Anthropic Claude API)" OFF \
  "VAULTWARDEN" "Vaultwarden (Bitwarden-compatible password manager)" OFF \
  "GITEA"      "Gitea (self-hosted Git server)" OFF \
  "N8N"        "n8n (workflow automation)" OFF \
  "WATCHTOWER" "Watchtower (auto-updates all containers)" OFF \
  "JELLYFIN"   "Jellyfin (media server)" OFF \
  "FILEBROWSER" "File Browser (web file manager)" OFF \
  "WGEASY"     "WG-Easy (WireGuard VPN with web UI)" OFF \
  "SPEEDTEST"  "Speedtest Tracker (periodic internet speed logging)" OFF \
  "IMMICH"     "Immich (self-hosted photo/video backup, + Postgres/Redis)" OFF \
  3>&1 1>&2 2>&3) || SELECTED=""

WITH_ITTOOLS=false
WITH_NEXTCLOUD=false
WITH_OPENCLAW=false
WITH_VAULTWARDEN=false
WITH_GITEA=false
WITH_N8N=false
WITH_WATCHTOWER=false
WITH_JELLYFIN=false
WITH_FILEBROWSER=false
WITH_WGEASY=false
WITH_SPEEDTEST=false
WITH_IMMICH=false
[[ "${SELECTED}" == *ITTOOLS*     ]] && WITH_ITTOOLS=true
[[ "${SELECTED}" == *NEXTCLOUD*   ]] && WITH_NEXTCLOUD=true
[[ "${SELECTED}" == *OPENCLAW*    ]] && WITH_OPENCLAW=true
[[ "${SELECTED}" == *VAULTWARDEN* ]] && WITH_VAULTWARDEN=true
[[ "${SELECTED}" == *GITEA*       ]] && WITH_GITEA=true
[[ "${SELECTED}" == *N8N*         ]] && WITH_N8N=true
[[ "${SELECTED}" == *WATCHTOWER*  ]] && WITH_WATCHTOWER=true
[[ "${SELECTED}" == *JELLYFIN*    ]] && WITH_JELLYFIN=true
[[ "${SELECTED}" == *FILEBROWSER* ]] && WITH_FILEBROWSER=true
[[ "${SELECTED}" == *WGEASY*      ]] && WITH_WGEASY=true
[[ "${SELECTED}" == *SPEEDTEST*   ]] && WITH_SPEEDTEST=true
[[ "${SELECTED}" == *IMMICH*      ]] && WITH_IMMICH=true

echo "==> Reverse proxy: ${REVERSE_PROXY} | Monitoring: ${MONITORING} | Docker UI: ${DOCKER_UI} | DNS blocker: ${DNS_BLOCKER}"
echo "==> Optional apps: IT-Tools=${WITH_ITTOOLS} Nextcloud=${WITH_NEXTCLOUD} OpenClaw=${WITH_OPENCLAW} Vaultwarden=${WITH_VAULTWARDEN} Gitea=${WITH_GITEA} n8n=${WITH_N8N} Watchtower=${WITH_WATCHTOWER} Jellyfin=${WITH_JELLYFIN} FileBrowser=${WITH_FILEBROWSER} WG-Easy=${WITH_WGEASY} Speedtest=${WITH_SPEEDTEST} Immich=${WITH_IMMICH}"

# DNS blockers need port 53 -> disable the systemd-resolved stub listener
if [[ "${DNS_BLOCKER}" != "NONE" ]]; then
  if [[ -f /etc/systemd/resolved.conf ]]; then
    echo "==> Disabling systemd-resolved stub listener (port 53) for ${DNS_BLOCKER}"
    mkdir -p /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/no-stub-listener.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
    systemctl restart systemd-resolved
  fi
fi

# ---------------------------------------------------------------------------
# Directory structure
# ---------------------------------------------------------------------------
mkdir -p "${BASE_DIR}" "${HOMEPAGE_CFG}"

[[ "${REVERSE_PROXY}" == "NPM"        ]] && mkdir -p "${BASE_DIR}/npm/data" "${BASE_DIR}/npm/letsencrypt"
[[ "${REVERSE_PROXY}" == "TRAEFIK"    ]] && mkdir -p "${BASE_DIR}/traefik"
[[ "${MONITORING}"    == "UPTIMEKUMA" ]] && mkdir -p "${BASE_DIR}/uptime-kuma"
[[ "${MONITORING}"    == "GATUS"      ]] && mkdir -p "${BASE_DIR}/gatus"
[[ "${DOCKER_UI}"     == "PORTAINER"  ]] && mkdir -p "${BASE_DIR}/portainer"
[[ "${DOCKER_UI}"     == "DOCKGE"     ]] && mkdir -p "${BASE_DIR}/dockge/data"
[[ "${DNS_BLOCKER}"   == "PIHOLE"     ]] && mkdir -p "${BASE_DIR}/pihole/etc-pihole" "${BASE_DIR}/pihole/etc-dnsmasq.d"
[[ "${DNS_BLOCKER}"   == "ADGUARD"    ]] && mkdir -p "${BASE_DIR}/adguard/work" "${BASE_DIR}/adguard/conf"

${WITH_NEXTCLOUD}   && mkdir -p "${BASE_DIR}/nextcloud/html" "${BASE_DIR}/nextcloud/db"
${WITH_OPENCLAW}    && mkdir -p "${BASE_DIR}/openclaw/config" "${BASE_DIR}/openclaw/workspace" "${BASE_DIR}/openclaw/secrets"
${WITH_VAULTWARDEN} && mkdir -p "${BASE_DIR}/vaultwarden"
${WITH_GITEA}       && mkdir -p "${BASE_DIR}/gitea/data" "${BASE_DIR}/gitea/config"
${WITH_N8N}         && mkdir -p "${BASE_DIR}/n8n"
${WITH_JELLYFIN}    && mkdir -p "${BASE_DIR}/jellyfin/config" "${BASE_DIR}/jellyfin/cache" "${BASE_DIR}/jellyfin/media"
${WITH_FILEBROWSER} && mkdir -p "${BASE_DIR}/filebrowser/data" "${BASE_DIR}/filebrowser/srv"
${WITH_WGEASY}      && mkdir -p "${BASE_DIR}/wg-easy"
${WITH_SPEEDTEST}   && mkdir -p "${BASE_DIR}/speedtest-tracker"
${WITH_IMMICH}       && mkdir -p "${BASE_DIR}/immich/library" "${BASE_DIR}/immich/postgres"

# ---------------------------------------------------------------------------
# docker-compose.yml (base)
# ---------------------------------------------------------------------------
cat > "${COMPOSE_FILE}" <<'EOF'
networks:
  homelab:
    name: homelab

services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./homepage/config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - homelab
EOF

# --- Reverse proxy -----------------------------------------------------
if [[ "${REVERSE_PROXY}" == "NPM" ]]; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - ./npm/data:/data
      - ./npm/letsencrypt:/etc/letsencrypt
    networks:
      - homelab
EOF
elif [[ "${REVERSE_PROXY}" == "TRAEFIK" ]]; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  traefik:
    image: traefik:v3
    container_name: traefik
    restart: unless-stopped
    command:
      - --api.insecure=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
    ports:
      - "80:80"
      - "443:443"
      - "8088:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik:/etc/traefik
    networks:
      - homelab
EOF
fi

# --- Monitoring ----------------------------------------------------------
if [[ "${MONITORING}" == "UPTIMEKUMA" ]]; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - ./uptime-kuma:/app/data
    networks:
      - homelab
EOF
elif [[ "${MONITORING}" == "GATUS" ]]; then
cat > "${BASE_DIR}/gatus/config.yaml" <<'EOF'
endpoints:
  - name: homepage
    url: "http://homepage:3000"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
EOF
cat >> "${COMPOSE_FILE}" <<'EOF'

  gatus:
    image: twinproduction/gatus:latest
    container_name: gatus
    restart: unless-stopped
    ports:
      - "3001:8080"
    volumes:
      - ./gatus/config.yaml:/config/config.yaml
    networks:
      - homelab
EOF
fi

# --- Docker management UI -------------------------------------------------
if [[ "${DOCKER_UI}" == "PORTAINER" ]]; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer:/data
    networks:
      - homelab
EOF
else
cat >> "${COMPOSE_FILE}" <<'EOF'

  dockge:
    image: louislam/dockge:latest
    container_name: dockge
    restart: unless-stopped
    ports:
      - "5001:5001"
    environment:
      DOCKGE_STACKS_DIR: /opt/homelab
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./dockge/data:/app/data
      - /opt/homelab:/opt/homelab
    networks:
      - homelab
EOF
fi

# --- DNS ad-blocker --------------------------------------------------------
if [[ "${DNS_BLOCKER}" == "PIHOLE" ]]; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    restart: unless-stopped
    environment:
      TZ: "Europe/Berlin"
      WEBPASSWORD: "changeme"
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8085:80"
    volumes:
      - ./pihole/etc-pihole:/etc/pihole
      - ./pihole/etc-dnsmasq.d:/etc/dnsmasq.d
    cap_add:
      - NET_ADMIN
    networks:
      - homelab
EOF
elif [[ "${DNS_BLOCKER}" == "ADGUARD" ]]; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  adguard:
    image: adguard/adguardhome:latest
    container_name: adguard
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3010:3000"
    volumes:
      - ./adguard/work:/opt/adguardhome/work
      - ./adguard/conf:/opt/adguardhome/conf
    networks:
      - homelab
EOF
fi

# --- Optional apps -----------------------------------------------------
if ${WITH_ITTOOLS}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  it-tools:
    image: corentinth/it-tools:latest
    container_name: it-tools
    restart: unless-stopped
    ports:
      - "8082:80"
    networks:
      - homelab
EOF
fi

if ${WITH_NEXTCLOUD}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  nextcloud-db:
    image: mariadb:11
    container_name: nextcloud-db
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED
    environment:
      MYSQL_ROOT_PASSWORD: nextcloud_root_change_me
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud_change_me
    volumes:
      - ./nextcloud/db:/var/lib/mysql
    networks:
      - homelab

  nextcloud:
    image: nextcloud:apache
    container_name: nextcloud
    restart: unless-stopped
    depends_on:
      - nextcloud-db
    ports:
      - "8083:80"
    environment:
      MYSQL_HOST: nextcloud-db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: nextcloud_change_me
    volumes:
      - ./nextcloud/html:/var/www/html
    networks:
      - homelab
EOF
fi

if ${WITH_OPENCLAW}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "18789:18789"
    volumes:
      - ./openclaw/config:/home/node/.openclaw
      - ./openclaw/workspace:/home/node/.openclaw/workspace
      - ./openclaw/secrets:/home/node/.config/openclaw
    networks:
      - homelab
EOF
fi

if ${WITH_VAULTWARDEN}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    ports:
      - "8084:80"
    volumes:
      - ./vaultwarden:/data
    networks:
      - homelab
EOF
fi

if ${WITH_GITEA}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: unless-stopped
    environment:
      USER_UID: 1000
      USER_GID: 1000
      GITEA__database__DB_TYPE: sqlite3
    ports:
      - "3005:3000"
      - "2222:22"
    volumes:
      - ./gitea/data:/data
      - ./gitea/config:/etc/gitea
    networks:
      - homelab
EOF
fi

if ${WITH_N8N}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      N8N_SECURE_COOKIE: "false"
      GENERIC_TIMEZONE: "Europe/Berlin"
    ports:
      - "5678:5678"
    volumes:
      - ./n8n:/home/node/.n8n
    networks:
      - homelab
EOF
fi

if ${WITH_WATCHTOWER}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    environment:
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_POLL_INTERVAL: "86400"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - homelab
EOF
fi

if ${WITH_JELLYFIN}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - "8096:8096"
    volumes:
      - ./jellyfin/config:/config
      - ./jellyfin/cache:/cache
      - ./jellyfin/media:/media
    networks:
      - homelab
EOF
fi

if ${WITH_FILEBROWSER}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    ports:
      - "8086:80"
    volumes:
      - ./filebrowser/srv:/srv
      - ./filebrowser/data/filebrowser.db:/database/filebrowser.db
    networks:
      - homelab
EOF
fi

if ${WITH_WGEASY}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    container_name: wg-easy
    restart: unless-stopped
    environment:
      WG_HOST: "CHANGE_ME_TO_YOUR_SERVER_IP_OR_DOMAIN"
      PASSWORD: "changeme"
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    volumes:
      - ./wg-easy:/etc/wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    networks:
      - homelab
EOF
fi

if ${WITH_SPEEDTEST}; then
  SPEEDTEST_APP_KEY="base64:$(openssl rand -base64 32)"
cat >> "${COMPOSE_FILE}" <<EOF

  speedtest-tracker:
    image: lscr.io/linuxserver/speedtest-tracker:latest
    container_name: speedtest-tracker
    restart: unless-stopped
    environment:
      TZ: "Europe/Berlin"
      APP_KEY: "${SPEEDTEST_APP_KEY}"
    ports:
      - "8087:80"
    volumes:
      - ./speedtest-tracker:/config
    networks:
      - homelab
EOF
fi

if ${WITH_IMMICH}; then
cat >> "${COMPOSE_FILE}" <<'EOF'

  immich-postgres:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgdata
    container_name: immich-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: immich_change_me
      POSTGRES_USER: immich
      POSTGRES_DB: immich
    volumes:
      - ./immich/postgres:/var/lib/postgresql/data
    networks:
      - homelab

  immich-redis:
    image: redis:7-alpine
    container_name: immich-redis
    restart: unless-stopped
    networks:
      - homelab

  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-server
    restart: unless-stopped
    depends_on:
      - immich-postgres
      - immich-redis
    environment:
      DB_HOSTNAME: immich-postgres
      DB_USERNAME: immich
      DB_PASSWORD: immich_change_me
      DB_DATABASE_NAME: immich
      REDIS_HOSTNAME: immich-redis
    ports:
      - "2283:2283"
    volumes:
      - ./immich/library:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    networks:
      - homelab
EOF
fi

# ---------------------------------------------------------------------------
# Homepage configuration
# ---------------------------------------------------------------------------
cat > "${HOMEPAGE_CFG}/settings.yaml" <<'EOF'
title: Homelab Dashboard
theme: dark
color: slate
headerStyle: clean
EOF

cat > "${HOMEPAGE_CFG}/widgets.yaml" <<'EOF'
- resources:
    cpu: true
    memory: true
    disk: /
EOF

cat > "${HOMEPAGE_CFG}/bookmarks.yaml" <<'EOF'
[]
EOF

cat > "${HOMEPAGE_CFG}/docker.yaml" <<'EOF'
my-docker:
  socket: /var/run/docker.sock
EOF

{
  echo "- Infrastructure:"
  if [[ "${REVERSE_PROXY}" == "NPM" ]]; then
    echo "    - Nginx Proxy Manager:"
    echo "        href: http://localhost:81"
    echo "        description: Reverse proxy management"
  elif [[ "${REVERSE_PROXY}" == "TRAEFIK" ]]; then
    echo "    - Traefik:"
    echo "        href: http://localhost:8088"
    echo "        description: Reverse proxy dashboard"
  fi
  if [[ "${MONITORING}" == "UPTIMEKUMA" ]]; then
    echo "    - Uptime Kuma:"
    echo "        href: http://localhost:3001"
    echo "        description: Monitoring"
  elif [[ "${MONITORING}" == "GATUS" ]]; then
    echo "    - Gatus:"
    echo "        href: http://localhost:3001"
    echo "        description: Monitoring"
  fi
  if [[ "${DOCKER_UI}" == "PORTAINER" ]]; then
    echo "    - Portainer:"
    echo "        href: http://localhost:9000"
    echo "        description: Docker management"
  else
    echo "    - Dockge:"
    echo "        href: http://localhost:5001"
    echo "        description: Docker Compose management"
  fi
  if [[ "${DNS_BLOCKER}" == "PIHOLE" ]]; then
    echo "    - Pi-hole:"
    echo "        href: http://localhost:8085/admin"
    echo "        description: Ad/tracker blocker"
  elif [[ "${DNS_BLOCKER}" == "ADGUARD" ]]; then
    echo "    - AdGuard Home:"
    echo "        href: http://localhost:3010"
    echo "        description: Ad/tracker blocker"
  fi

  if ${WITH_ITTOOLS} || ${WITH_NEXTCLOUD} || ${WITH_OPENCLAW} || ${WITH_VAULTWARDEN} || ${WITH_GITEA} || ${WITH_N8N} || ${WITH_JELLYFIN} || ${WITH_FILEBROWSER} || ${WITH_WGEASY} || ${WITH_SPEEDTEST} || ${WITH_IMMICH}; then
    echo "- Apps:"
    ${WITH_ITTOOLS} && {
      echo "    - IT-Tools:"
      echo "        href: http://localhost:8082"
      echo "        description: Developer tool collection"
    }
    ${WITH_NEXTCLOUD} && {
      echo "    - Nextcloud:"
      echo "        href: http://localhost:8083"
      echo "        description: File sync & storage"
    }
    ${WITH_OPENCLAW} && {
      echo "    - OpenClaw:"
      echo "        href: http://localhost:18789"
      echo "        description: Self-hosted AI agent (Anthropic Claude API)"
    }
    ${WITH_VAULTWARDEN} && {
      echo "    - Vaultwarden:"
      echo "        href: http://localhost:8084"
      echo "        description: Password manager"
    }
    ${WITH_GITEA} && {
      echo "    - Gitea:"
      echo "        href: http://localhost:3005"
      echo "        description: Git server"
    }
    ${WITH_N8N} && {
      echo "    - n8n:"
      echo "        href: http://localhost:5678"
      echo "        description: Workflow automation"
    }
    ${WITH_JELLYFIN} && {
      echo "    - Jellyfin:"
      echo "        href: http://localhost:8096"
      echo "        description: Media server"
    }
    ${WITH_FILEBROWSER} && {
      echo "    - File Browser:"
      echo "        href: http://localhost:8086"
      echo "        description: Web file manager"
    }
    ${WITH_WGEASY} && {
      echo "    - WG-Easy:"
      echo "        href: http://localhost:51821"
      echo "        description: WireGuard VPN"
    }
    ${WITH_SPEEDTEST} && {
      echo "    - Speedtest Tracker:"
      echo "        href: http://localhost:8087"
      echo "        description: Internet speed monitoring"
    }
    ${WITH_IMMICH} && {
      echo "    - Immich:"
      echo "        href: http://localhost:2283"
      echo "        description: Photo & video backup"
    }
  fi
  # Watchtower has no web UI, so it doesn't appear on Homepage.
} > "${HOMEPAGE_CFG}/services.yaml"

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------
echo "==> Configuring UFW"
ufw allow OpenSSH || true
ufw allow 3000/tcp || true

if [[ "${REVERSE_PROXY}" == "NPM" ]]; then
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 81/tcp || true
elif [[ "${REVERSE_PROXY}" == "TRAEFIK" ]]; then
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 8088/tcp || true
fi

if [[ "${MONITORING}" != "NONE" ]]; then
  ufw allow 3001/tcp || true
fi

if [[ "${DOCKER_UI}" == "PORTAINER" ]]; then
  ufw allow 9000/tcp || true
else
  ufw allow 5001/tcp || true
fi

if [[ "${DNS_BLOCKER}" == "PIHOLE" ]]; then
  ufw allow 53 || true
  ufw allow 8085/tcp || true
elif [[ "${DNS_BLOCKER}" == "ADGUARD" ]]; then
  ufw allow 53 || true
  ufw allow 3010/tcp || true
fi

${WITH_ITTOOLS}     && ufw allow 8082/tcp || true
${WITH_NEXTCLOUD}   && ufw allow 8083/tcp || true
${WITH_OPENCLAW}    && ufw allow 18789/tcp || true
${WITH_VAULTWARDEN} && ufw allow 8084/tcp || true
${WITH_GITEA}       && { ufw allow 3005/tcp || true; ufw allow 2222/tcp || true; }
${WITH_N8N}         && ufw allow 5678/tcp || true
${WITH_JELLYFIN}    && ufw allow 8096/tcp || true
${WITH_FILEBROWSER} && ufw allow 8086/tcp || true
${WITH_WGEASY}      && { ufw allow 51820/udp || true; ufw allow 51821/tcp || true; }
${WITH_SPEEDTEST}   && ufw allow 8087/tcp || true
${WITH_IMMICH}      && ufw allow 2283/tcp || true
ufw --force enable || true

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
echo "==> Starting containers"
cd "${BASE_DIR}"
docker compose up -d

echo
echo "============================================================"
echo " Setup complete!"
echo
echo " Homepage:             http://<server-ip>:3000"
[[ "${REVERSE_PROXY}" == "NPM"     ]] && echo " Nginx Proxy Manager:  http://<server-ip>:81   (default login: admin@example.com / changeme)"
[[ "${REVERSE_PROXY}" == "TRAEFIK" ]] && echo " Traefik dashboard:    http://<server-ip>:8088"
[[ "${MONITORING}"    == "UPTIMEKUMA" ]] && echo " Uptime Kuma:          http://<server-ip>:3001"
[[ "${MONITORING}"    == "GATUS"      ]] && echo " Gatus:                http://<server-ip>:3001"
[[ "${DOCKER_UI}"     == "PORTAINER"  ]] && echo " Portainer:            http://<server-ip>:9000"
[[ "${DOCKER_UI}"     == "DOCKGE"     ]] && echo " Dockge:               http://<server-ip>:5001"
[[ "${DNS_BLOCKER}"   == "PIHOLE"     ]] && echo " Pi-hole:              http://<server-ip>:8085/admin  (password: changeme)"
[[ "${DNS_BLOCKER}"   == "ADGUARD"    ]] && echo " AdGuard Home:         http://<server-ip>:3010"
${WITH_ITTOOLS}     && echo " IT-Tools:             http://<server-ip>:8082"
${WITH_NEXTCLOUD}   && echo " Nextcloud:            http://<server-ip>:8083"
${WITH_OPENCLAW}    && echo " OpenClaw:             http://<server-ip>:18789  (enter your API key during onboarding)"
${WITH_VAULTWARDEN} && echo " Vaultwarden:          http://<server-ip>:8084"
${WITH_GITEA}       && echo " Gitea:                http://<server-ip>:3005  (SSH git port: 2222)"
${WITH_N8N}         && echo " n8n:                  http://<server-ip>:5678"
${WITH_JELLYFIN}    && echo " Jellyfin:             http://<server-ip>:8096"
${WITH_FILEBROWSER} && echo " File Browser:         http://<server-ip>:8086  (default login: admin / admin)"
${WITH_WGEASY}      && echo " WG-Easy:              http://<server-ip>:51821  (password: changeme, set WG_HOST first!)"
${WITH_SPEEDTEST}   && echo " Speedtest Tracker:    http://<server-ip>:8087"
${WITH_IMMICH}      && echo " Immich:               http://<server-ip>:2283"
${WITH_WATCHTOWER}  && echo " Watchtower:           running in the background, no web UI"
cat <<'EOF'

 Next steps:
 - Change default passwords immediately (NPM, Pi-hole, Vaultwarden, WG-Easy, File Browser).
 - If using WG-Easy, edit WG_HOST in /opt/homelab/docker-compose.yml to your
   server's public IP or domain, then run `docker compose up -d` again.
 - If using NPM or Traefik, add proxy hosts / labels for your own domains.
 - Change the Nextcloud/Immich database passwords in docker-compose.yml before
   exposing them beyond your local network.
 - All config and data files live under /opt/homelab
============================================================
EOF
