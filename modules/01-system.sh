#!/bin/bash
# Módulo 01 — Dependencias del sistema, Docker CE, Tailscale, SSH hardening

log "Paso 1/6 — Sistema base..."

# iptables-persistent usa debconf interactivo — pre-seed para que no pause
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections
sudo apt update -qq
sudo apt install -y \
  git curl wget \
  tmux \
  lm-sensors \
  iptables-persistent \
  python3-pip python3-venv \
  openssh-server \
  ca-certificates \
  gnupg \
  lsb-release \
  xvfb

# Docker CE (oficial) — se instala tanto en bare metal como en WSL2.
# En WSL2, docker-ce nativo reemplaza a Docker Desktop (incompatible con
# networkingMode=mirrored). systemd dentro de WSL2 gestiona el daemon.
if ! command -v docker &>/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update -qq
  sudo apt install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$LAB_USER"
  warn "Docker CE instalado. Para usar sin sudo en esta sesión: newgrp docker"
else
  log "Docker ya instalado, saltando."
fi

# Tailscale — en WSL2 se omite: correr desde el host Windows (mejor soporte de red)
if [ -n "$WSL_DISTRO_NAME" ]; then
  log "WSL2 detectado — saltando Tailscale (usar la instalación del host Windows)."
elif ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
  log "Tailscale instalado — activar manualmente al final: sudo tailscale up"
else
  log "Tailscale ya instalado, saltando."
fi

# GitHub CLI
if ! command -v gh &>/dev/null; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update -qq && sudo apt install -y gh
  log "GitHub CLI instalado."
else
  log "gh ya instalado, saltando."
fi

# SSH hardening + keepalive — en WSL2 se omite: el acceso remoto entra por el
# OpenSSH Server del host Windows, no por uno dentro de la distro
if [ -n "$WSL_DISTRO_NAME" ]; then
  log "WSL2 detectado — saltando SSH hardening (gestionado por el host Windows)."
else
  sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sudo sed -i 's/^#*TCPKeepAlive.*/TCPKeepAlive yes/' /etc/ssh/sshd_config
  sudo sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 30/' /etc/ssh/sshd_config
  sudo sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config
  sudo systemctl reload ssh
  log "SSH hardening aplicado (keepalive 30s, sin root, sin password)."
fi

# fail2ban — rate limiting para SSH desde LAN
if ! command -v fail2ban-server &>/dev/null; then
  sudo apt install -y fail2ban
  log "fail2ban instalado."
else
  log "fail2ban ya instalado, saltando."
fi

# firewall-baseline — unidad opcional (default=on): UFW secure-by-default.
# Cierra el gap de "cero firewall tras bootstrap": quien corre solo el bootstrap
# (sin security-apply-sudo.sh + manifiesto) quedaba sin firewall. Este baseline
# deja deny-incoming + SSH solo desde tailnet/LAN. El detalle per-port de cada
# servicio lo sigue afinando security-apply-sudo.sh (post-bootstrap, manifiesto).
# Corre DESPUÉS del SSH hardening + fail2ban (necesita SSH ya configurado).
# OJO: UFW NO protege contenedores Docker (bypass FORWARD) — esos se cierran por
# bind a localhost (F1). Este baseline protege los servicios del host.
if should_install firewall-baseline; then
  if [ -n "$WSL_DISTRO_NAME" ]; then
    log "WSL2 detectado — saltando firewall-baseline (UFW no aplica; red gestionada por el host Windows)."
  else
    command -v ufw >/dev/null || sudo apt install -y ufw
    # ── ANTI-LOCKOUT: permitir SSH ANTES de cualquier deny/enable ──
    TAILNET="100.64.0.0/10"
    sudo ufw allow from "$TAILNET" to any port 22 proto tcp comment 'SSH via Tailscale'
    # LAN detectada (no romper acceso del operador en LAN durante el install).
    # Se toma la subred de la interfaz del default route (el uplink físico real),
    # NO el primer route link-scope: ese suele ser docker0/tailscale0 y detectarlos
    # como "LAN" vaciaría de sentido esta regla anti-lockout.
    LAN_IF=$(ip route show default 2>/dev/null | awk '/^default/{print $5; exit}')
    LAN=""
    [ -n "$LAN_IF" ] && LAN=$(ip -o -f inet route show scope link dev "$LAN_IF" 2>/dev/null | awk '{print $1; exit}')
    [ -n "$LAN" ] && sudo ufw allow from "$LAN" to any port 22 proto tcp comment 'SSH LAN'
    # fuente de ESTA sesión SSH (blindaje extra anti-lockout)
    SRC=$(echo "${SSH_CLIENT:-}" | awk '{print $1}')
    [ -n "$SRC" ] && sudo ufw allow from "$SRC" to any port 22 proto tcp comment 'SSH sesión actual'
    # baseline
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    log "UFW baseline activo: deny-incoming, SSH desde tailnet/LAN. Per-port de servicios: security-apply-sudo.sh."
    warn "UFW no protege contenedores Docker (bypass FORWARD) — esos se cierran por bind (F1)."
  fi
  mark_done firewall-baseline
fi

# Syncthing — unidad opcional (default=on); en WSL2 se omite: correr desde el host Windows
if should_install syncthing; then
  if [ -n "$WSL_DISTRO_NAME" ]; then
    log "WSL2 detectado — saltando Syncthing (usar la instalación del host Windows)."
  elif ! command -v syncthing &>/dev/null; then
    curl -s https://syncthing.net/release-key.txt \
      | sudo gpg --dearmor -o /etc/apt/keyrings/syncthing.gpg
    echo "deb [signed-by=/etc/apt/keyrings/syncthing.gpg] https://apt.syncthing.net/ syncthing stable" \
      | sudo tee /etc/apt/sources.list.d/syncthing.list > /dev/null
    sudo apt update -qq && sudo apt install -y syncthing
    sudo systemctl enable syncthing@"$LAB_USER"
    sudo systemctl start syncthing@"$LAB_USER"
    log "Syncthing instalado y activo como servicio del sistema."
    warn "Configuración de Syncthing requiere pasos manuales — ver instrucciones al final del bootstrap."
  else
    log "Syncthing ya instalado, saltando."
  fi
  mark_done syncthing
fi

# restic — unidad opcional (default=on): backup a B2 del lab
if should_install restic; then
  if ! command -v restic &>/dev/null; then
    sudo apt install -y restic
    log "restic instalado ($(restic version 2>/dev/null | head -1))."
  else
    log "restic ya instalado ($(restic version 2>/dev/null | head -1)), saltando."
  fi
  mark_done restic
fi

if ! command -v age &>/dev/null; then
  sudo apt install -y age
  log "age instalado — cifrado de secrets disponible."
else
  log "age ya instalado, saltando."
fi

if ! command -v sqlite3 &>/dev/null; then
  sudo apt install -y sqlite3
  log "sqlite3 instalado."
else
  log "sqlite3 ya instalado, saltando."
fi

# etckeeper — unidad opcional (default=on): auto-commitea cambios en /etc tras cada apt install
if should_install etckeeper; then
  if ! dpkg -l etckeeper &>/dev/null 2>&1; then
    sudo apt install -y etckeeper
    sudo etckeeper init 2>/dev/null || true
    sudo etckeeper commit "etckeeper: init tras bootstrap" 2>/dev/null || true
    log "etckeeper instalado — /etc bajo control de versiones automático."
  else
    log "etckeeper ya instalado, saltando."
  fi
  mark_done etckeeper
fi

log "Módulo 01 completo."
