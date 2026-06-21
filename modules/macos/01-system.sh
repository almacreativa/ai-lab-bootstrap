#!/bin/bash
# Módulo 01 (macOS) — Homebrew, PostgreSQL 17, Tailscale, GitHub CLI, SSH, Syncthing

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

# PostgreSQL 17 nativo (reemplaza Docker)
if ! brew list postgresql@17 &>/dev/null 2>&1; then
  brew install -q postgresql@17
  log "PostgreSQL 17 instalado via Homebrew."
else
  log "PostgreSQL 17 ya instalado, saltando."
fi

if ! brew services list | grep -q "postgresql@17.*started"; then
  brew services start postgresql@17
  sleep 3
  log "PostgreSQL 17 iniciado via brew services."
else
  log "PostgreSQL 17 ya corriendo."
fi

createuser -s paperclip 2>/dev/null || true
createdb -O paperclip paperclip 2>/dev/null || true
psql -d paperclip -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" 2>/dev/null || true
psql -d paperclip -c "CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;" 2>/dev/null || true
log "Base de datos 'paperclip' lista (usuario: paperclip, extensiones: pg_trgm, fuzzystrmatch)."

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
