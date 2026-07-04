#!/usr/bin/env bash
#
# Ubuntu Server Setup
#   Immer installiert: Docker, Nginx Proxy Manager, Uptime Kuma, Homepage
#   Wahlweise Docker-Management-UI: Portainer ODER Dockge
#   Optional (Mehrfachauswahl): IT-Tools, Nextcloud, OpenClaw, Vaultwarden,
#                                Gitea, n8n, Pi-hole, Watchtower
#
# Einzeiler-Installation (nach dem Hosting auf GitHub):
#   curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/setup.sh | sudo bash
#
# Lokale Ausfuehrung:
#   sudo bash setup.sh
#
set -euo pipefail

BASE_DIR="/opt/homelab"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
HOMEPAGE_CFG="${BASE_DIR}/homepage/config"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if [[ ${EUID} -ne 0 ]]; then
  echo "Bitte als root ausfuehren: sudo bash setup.sh" >&2
  exit 1
fi

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "Warnung: Dieses Script ist fuer Ubuntu Server gedacht. Fahre trotzdem fort..." >&2
fi

echo "==> Aktualisiere Paketlisten"
apt-get update -y

echo "==> Installiere Basis-Pakete"
apt-get install -y ca-certificates curl gnupg whiptail ufw

# ---------------------------------------------------------------------------
# Docker Installation (offizielles apt-Repo)
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  echo "==> Installiere Docker Engine"
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
  echo "==> Docker ist bereits installiert, ueberspringe"
fi

# Falls das Script per sudo von einem normalen User gestartet wurde, diesen zur docker-Gruppe hinzufuegen
if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "${SUDO_USER}" || true
fi

# ---------------------------------------------------------------------------
# Docker-Management-UI: Portainer oder Dockge
# ---------------------------------------------------------------------------
DOCKER_UI=$(whiptail --title "Docker-Management-UI" --radiolist \
  "Welche Oberflaeche zur Docker-/Compose-Verwaltung soll installiert werden?" \
  12 70 2 \
  "PORTAINER" "Portainer (volle Docker-GUI, mehr Funktionen)" ON \
  "DOCKGE"    "Dockge (schlanker Compose-Stack-Manager)" OFF \
  3>&1 1>&2 2>&3) || DOCKER_UI="PORTAINER"

# ---------------------------------------------------------------------------
# Interaktive Auswahl optionaler Dienste
# ---------------------------------------------------------------------------
SELECTED=$(whiptail --title "Optionale Dienste" --checklist \
  "Welche zusaetzlichen Dienste sollen installiert und in Homepage eingebunden werden?" \
  20 78 8 \
  "ITTOOLS"     "IT-Tools (Sammlung von Dev-Tools)" OFF \
  "NEXTCLOUD"   "Nextcloud (+ MariaDB)" OFF \
  "OPENCLAW"    "OpenClaw (selbstgehosteter KI-Agent, nutzbar mit Anthropic Claude API)" OFF \
  "VAULTWARDEN" "Vaultwarden (selbstgehosteter Passwort-Manager, Bitwarden-kompatibel)" OFF \
  "GITEA"       "Gitea (eigener Git-Server)" OFF \
  "N8N"         "n8n (Workflow-/Automatisierungstool)" OFF \
  "PIHOLE"      "Pi-hole (netzwerkweiter Werbe-/Tracker-Blocker via DNS)" OFF \
  "WATCHTOWER"  "Watchtower (aktualisiert alle Container automatisch)" OFF \
  3>&1 1>&2 2>&3) || SELECTED=""

WITH_ITTOOLS=false
WITH_NEXTCLOUD=false
WITH_OPENCLAW=false
WITH_VAULTWARDEN=false
WITH_GITEA=false
WITH_N8N=false
WITH_PIHOLE=false
WITH_WATCHTOWER=false
[[ "${SELECTED}" == *ITTOOLS*     ]] && WITH_ITTOOLS=true
[[ "${SELECTED}" == *NEXTCLOUD*   ]] && WITH_NEXTCLOUD=true
[[ "${SELECTED}" == *OPENCLAW*    ]] && WITH_OPENCLAW=true
[[ "${SELECTED}" == *VAULTWARDEN* ]] && WITH_VAULTWARDEN=true
[[ "${SELECTED}" == *GITEA*       ]] && WITH_GITEA=true
[[ "${SELECTED}" == *N8N*         ]] && WITH_N8N=true
[[ "${SELECTED}" == *PIHOLE*      ]] && WITH_PIHOLE=true
[[ "${SELECTED}" == *WATCHTOWER*  ]] && WITH_WATCHTOWER=true

echo "==> Docker-UI: ${DOCKER_UI}"
echo "==> Ausgewaehlt: IT-Tools=${WITH_ITTOOLS} Nextcloud=${WITH_NEXTCLOUD} OpenClaw=${WITH_OPENCLAW} Vaultwarden=${WITH_VAULTWARDEN} Gitea=${WITH_GITEA} n8n=${WITH_N8N} Pi-hole=${WITH_PIHOLE} Watchtower=${WITH_WATCHTOWER}"

# Pi-hole braucht Port 53 -> systemd-resolved Stub-Listener deaktivieren
if ${WITH_PIHOLE}; then
  if [[ -f /etc/systemd/resolved.conf ]]; then
    echo "==> Deaktiviere systemd-resolved Stub-Listener (Port 53) fuer Pi-hole"
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
# Verzeichnisstruktur
# ---------------------------------------------------------------------------
mkdir -p \
  "${BASE_DIR}" \
  "${HOMEPAGE_CFG}" \
  "${BASE_DIR}/npm/data" "${BASE_DIR}/npm/letsencrypt" \
  "${BASE_DIR}/uptime-kuma"

if [[ "${DOCKER_UI}" == "PORTAINER" ]]; then
  mkdir -p "${BASE_DIR}/portainer"
else
  mkdir -p "${BASE_DIR}/dockge/data"
fi

${WITH_NEXTCLOUD}   && mkdir -p "${BASE_DIR}/nextcloud/html" "${BASE_DIR}/nextcloud/db"
${WITH_OPENCLAW}    && mkdir -p "${BASE_DIR}/openclaw/config" "${BASE_DIR}/openclaw/workspace" "${BASE_DIR}/openclaw/secrets"
${WITH_VAULTWARDEN} && mkdir -p "${BASE_DIR}/vaultwarden"
${WITH_GITEA}       && mkdir -p "${BASE_DIR}/gitea/data" "${BASE_DIR}/gitea/config"
${WITH_N8N}         && mkdir -p "${BASE_DIR}/n8n"
${WITH_PIHOLE}      && mkdir -p "${BASE_DIR}/pihole/etc-pihole" "${BASE_DIR}/pihole/etc-dnsmasq.d"

# ---------------------------------------------------------------------------
# docker-compose.yml (Basisdienste)
# ---------------------------------------------------------------------------
cat > "${COMPOSE_FILE}" <<'EOF'
networks:
  homelab:
    name: homelab

services:
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

if ${WITH_PIHOLE}; then
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

# ---------------------------------------------------------------------------
# Homepage-Konfiguration
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
  echo "- Infrastruktur:"
  if [[ "${DOCKER_UI}" == "PORTAINER" ]]; then
    echo "    - Portainer:"
    echo "        href: http://localhost:9000"
    echo "        description: Docker-Verwaltung"
  else
    echo "    - Dockge:"
    echo "        href: http://localhost:5001"
    echo "        description: Docker-Compose-Verwaltung"
  fi
  echo "    - Nginx Proxy Manager:"
  echo "        href: http://localhost:81"
  echo "        description: Reverse Proxy Verwaltung"
  echo "    - Uptime Kuma:"
  echo "        href: http://localhost:3001"
  echo "        description: Monitoring"

  if ${WITH_ITTOOLS} || ${WITH_NEXTCLOUD} || ${WITH_OPENCLAW} || ${WITH_VAULTWARDEN} || ${WITH_GITEA} || ${WITH_N8N} || ${WITH_PIHOLE}; then
    echo "- Tools:"
    ${WITH_ITTOOLS} && {
      echo "    - IT-Tools:"
      echo "        href: http://localhost:8082"
      echo "        description: Dev-Tool-Sammlung"
    }
    ${WITH_NEXTCLOUD} && {
      echo "    - Nextcloud:"
      echo "        href: http://localhost:8083"
      echo "        description: Cloud-Speicher"
    }
    ${WITH_OPENCLAW} && {
      echo "    - OpenClaw:"
      echo "        href: http://localhost:18789"
      echo "        description: Selbstgehosteter KI-Agent (Anthropic Claude API)"
    }
    ${WITH_VAULTWARDEN} && {
      echo "    - Vaultwarden:"
      echo "        href: http://localhost:8084"
      echo "        description: Passwort-Manager"
    }
    ${WITH_GITEA} && {
      echo "    - Gitea:"
      echo "        href: http://localhost:3005"
      echo "        description: Git-Server"
    }
    ${WITH_N8N} && {
      echo "    - n8n:"
      echo "        href: http://localhost:5678"
      echo "        description: Automatisierung"
    }
    ${WITH_PIHOLE} && {
      echo "    - Pi-hole:"
      echo "        href: http://localhost:8085/admin"
      echo "        description: Werbe-/Tracker-Blocker"
    }
  fi
  # Watchtower hat keine Web-UI, taucht daher nicht bei Homepage auf.
} > "${HOMEPAGE_CFG}/services.yaml"

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------
echo "==> Konfiguriere UFW"
ufw allow OpenSSH || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw allow 81/tcp || true
ufw allow 3000/tcp || true
ufw allow 3001/tcp || true
if [[ "${DOCKER_UI}" == "PORTAINER" ]]; then
  ufw allow 9000/tcp || true
else
  ufw allow 5001/tcp || true
fi
${WITH_ITTOOLS}     && ufw allow 8082/tcp || true
${WITH_NEXTCLOUD}   && ufw allow 8083/tcp || true
${WITH_OPENCLAW}    && ufw allow 18789/tcp || true
${WITH_VAULTWARDEN} && ufw allow 8084/tcp || true
${WITH_GITEA}       && { ufw allow 3005/tcp || true; ufw allow 2222/tcp || true; }
${WITH_N8N}         && ufw allow 5678/tcp || true
${WITH_PIHOLE}      && { ufw allow 53 || true; ufw allow 8085/tcp || true; }
ufw --force enable || true

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
echo "==> Starte Container"
cd "${BASE_DIR}"
docker compose up -d

cat <<EOF

============================================================
 Setup abgeschlossen!

 Nginx Proxy Manager:  http://<server-ip>:81   (Standard-Login: admin@example.com / changeme)
 Uptime Kuma:          http://<server-ip>:3001
 Homepage:             http://<server-ip>:3000
EOF
if [[ "${DOCKER_UI}" == "PORTAINER" ]]; then
  echo " Portainer:            http://<server-ip>:9000"
else
  echo " Dockge:               http://<server-ip>:5001"
fi
${WITH_ITTOOLS}     && echo " IT-Tools:             http://<server-ip>:8082"
${WITH_NEXTCLOUD}   && echo " Nextcloud:            http://<server-ip>:8083"
${WITH_OPENCLAW}    && echo " OpenClaw:             http://<server-ip>:18789  (API-Key im Onboarding eintragen)"
${WITH_VAULTWARDEN} && echo " Vaultwarden:          http://<server-ip>:8084"
${WITH_GITEA}       && echo " Gitea:                http://<server-ip>:3005  (SSH-Git-Port: 2222)"
${WITH_N8N}         && echo " n8n:                  http://<server-ip>:5678"
${WITH_PIHOLE}      && echo " Pi-hole:              http://<server-ip>:8085/admin  (Passwort: changeme)"
${WITH_WATCHTOWER}  && echo " Watchtower:           laeuft im Hintergrund, keine Web-UI"
cat <<'EOF'

 Naechste Schritte:
 - Bei Nginx Proxy Manager sofort das Standard-Passwort aendern.
 - Bei Bedarf in NPM "Proxy Hosts" fuer eigene Domains anlegen.
 - Bei Nextcloud die DB-Passwoerter in docker-compose.yml vor dem ersten
   Start (oder danach per docker exec) auf sichere Werte umstellen.
 - Bei Pi-hole und Vaultwarden die Standardpasswoerter aendern.
 - Alle Konfigurationsdateien liegen unter /opt/homelab
============================================================
EOF
