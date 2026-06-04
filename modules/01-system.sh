#!/bin/bash
# Módulo 01 — Dependencias del sistema, Docker CE, Tailscale, SSH hardening

log "Paso 1/6 — Sistema base..."

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

# Docker CE (oficial)
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

# Tailscale
if ! command -v tailscale &>/dev/null; then
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

# SSH hardening
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
log "SSH hardening aplicado (PasswordAuthentication no, PermitRootLogin no)."

# Syncthing — sincronización P2P de knowledge/ con otros dispositivos
if ! command -v syncthing &>/dev/null; then
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

log "Módulo 01 completo."
