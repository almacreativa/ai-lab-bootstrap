#!/bin/bash
# Módulo 04 — Herramientas AI: Claude Code, Opencode, Chromium, Xvfb

log "Paso 4/6 — Herramientas AI..."

# Chromium — necesario para logins headless via CDP (nlm, OAuth flows)
# snap no es confiable dentro de WSL2 (squashfs/AppArmor) — usar apt ahí
if [ -n "$WSL_DISTRO_NAME" ]; then
  if ! command -v chromium-browser &>/dev/null && ! command -v chromium &>/dev/null; then
    sudo apt install -y chromium-browser || sudo apt install -y chromium
    log "Chromium instalado via apt (WSL2)."
  else
    log "Chromium ya instalado, saltando."
  fi
elif ! snap list chromium &>/dev/null 2>&1; then
  sudo snap install chromium
  log "Chromium instalado via snap."
else
  log "Chromium ya instalado, saltando."
fi

# Claude Code via npm (instalación automática — login es manual al final)
if ! command -v claude &>/dev/null; then
  npm install -g @anthropic-ai/claude-code
  log "Claude Code instalado ($(claude --version 2>/dev/null | head -1))."
  warn "Completar login después del bootstrap: claude"
else
  log "Claude Code ya instalado ($(claude --version 2>/dev/null | head -1))."
fi

# Opencode
if [ ! -f "$HOME/.opencode/bin/opencode" ]; then
  mkdir -p "$HOME/.opencode"
  cd "$HOME/.opencode"
  npm install opencode-ai 2>/dev/null \
    || warn "npm install opencode-ai falló — instalar manualmente desde opencode.ai"
  mkdir -p "$HOME/.opencode/bin"
  ln -sf "$HOME/.opencode/node_modules/.bin/opencode" "$HOME/.opencode/bin/opencode" 2>/dev/null || true
  cd -
  log "Opencode instalado."
else
  log "Opencode ya instalado, saltando."
fi

# Aliases en .bashrc
BASHRC="$HOME/.bashrc"
if ! grep -q "alias claude-d=" "$BASHRC"; then
  echo "" >> "$BASHRC"
  echo "# AI Lab" >> "$BASHRC"
  echo "export PATH=\"\$HOME/.opencode/bin:\$PATH\"" >> "$BASHRC"
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$BASHRC"
  echo "alias claude-d='claude --dangerously-skip-permissions'" >> "$BASHRC"
  [ "$INSTALL_HERMES" = "true" ] && echo "alias hermes='\$HOME/.hermes-env/bin/hermes'" >> "$BASHRC"
  log "Aliases y PATH agregados a .bashrc."
fi

log "Módulo 04 completo."
