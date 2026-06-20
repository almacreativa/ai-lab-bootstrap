#!/bin/bash
# Módulo 01 (macOS) — Homebrew, Docker Desktop, Tailscale, GitHub CLI, SSH, Syncthing

log "Paso 1/6 — Sistema base (macOS)..."

# Homebrew
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -d /opt/homebrew/bin ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  log "Homebrew instalado."
else
  log "Homebrew ya instalado, saltando."
fi

brew update -q

brew install -q git curl wget tmux gnupg || true

# Docker Desktop
if ! command -v docker &>/dev/null; then
  brew install --cask docker
  log "Docker Desktop instalado — abrirlo manualmente al menos una vez: open -a Docker"
  warn "Docker Desktop requiere abrirse y aceptar permisos antes de poder usar 'docker' en terminal."
else
  log "Docker ya instalado, saltando."
fi

# Tailscale
if ! command -v tailscale &>/dev/null; then
  brew install --cask tailscale
  log "Tailscale instalado — activar manualmente al final desde la app o: tailscale up"
else
  log "Tailscale ya instalado, saltando."
fi

# GitHub CLI
if ! command -v gh &>/dev/null; then
  brew install -q gh
  log "GitHub CLI instalado."
else
  log "gh ya instalado, saltando."
fi

# SSH (Remote Login) + hardening — equivalente a sshd en Linux
if [[ $(sudo systemsetup -getremotelogin 2>/dev/null | grep -c "On") -eq 0 ]]; then
  sudo systemsetup -setremotelogin on
  log "Remote Login (SSH) activado."
else
  log "Remote Login ya estaba activo."
fi

sudo sed -i '' 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true
sudo sed -i '' 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null || true
sudo sed -i '' 's/^#*TCPKeepAlive.*/TCPKeepAlive yes/' /etc/ssh/sshd_config 2>/dev/null || true
sudo sed -i '' 's/^#*ClientAliveInterval.*/ClientAliveInterval 30/' /etc/ssh/sshd_config 2>/dev/null || true
sudo sed -i '' 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config 2>/dev/null || true
sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
log "SSH hardening aplicado (keepalive 30s, sin root, sin password)."
warn "Si usas Touch ID/contraseña local para sudo, PasswordAuthentication=no solo afecta SSH remoto, no el login local."

# Syncthing
if ! command -v syncthing &>/dev/null; then
  brew install -q syncthing
  brew services start syncthing
  log "Syncthing instalado y activo via brew services."
else
  log "Syncthing ya instalado, saltando."
fi

log "Módulo 01 (macOS) completo."
