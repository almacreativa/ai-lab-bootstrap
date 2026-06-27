#!/bin/bash
# Módulo 02 (macOS) — NVM + Node.js 24 + Antigravity CLI

log "Paso 2/6 — Node.js..."

export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

nvm install 24 --lts 2>/dev/null || nvm install 24
nvm use 24
nvm alias default 24
log "Node $(node --version) activo."

if ! command -v pnpm &>/dev/null; then
  npm install -g pnpm@9
  log "pnpm $(pnpm --version) instalado."
else
  log "pnpm ya instalado ($(pnpm --version))."
fi

if ! command -v antigravity &>/dev/null; then
  curl -fsSL https://antigravity.google/cli/install.sh | bash
  log "Antigravity CLI instalado."
else
  log "Antigravity CLI ya instalado."
fi

log "Módulo 02 completo."
