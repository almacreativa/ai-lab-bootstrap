#!/bin/bash
# Módulo 04 (macOS) — Herramientas AI: Claude Code, Opencode, Chromium

log "Paso 4/6 — Herramientas AI..."

# Chromium — necesario para nlm (en Mac usa pantalla real, no requiere CDP/Xvfb)
if ! brew list --cask chromium &>/dev/null 2>&1; then
  brew install --cask chromium
  log "Chromium instalado via Homebrew Cask."
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

# Aliases — detectar shell (zsh es el default en macOS desde Catalina)
SHELL_RC="$HOME/.zshrc"
[ "$(basename "$SHELL")" = "bash" ] && SHELL_RC="$HOME/.bash_profile"

if ! grep -q "alias claude-d=" "$SHELL_RC" 2>/dev/null; then
  echo "" >> "$SHELL_RC"
  echo "# AI Lab" >> "$SHELL_RC"
  echo "export PATH=\"\$HOME/.opencode/bin:\$PATH\"" >> "$SHELL_RC"
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
  echo "alias claude-d='claude --dangerously-skip-permissions'" >> "$SHELL_RC"
  [ "$INSTALL_HERMES" = "true" ] && echo "alias hermes='\$HOME/.hermes-env/bin/hermes'" >> "$SHELL_RC"
  log "Aliases y PATH agregados a $SHELL_RC."
fi

log "Módulo 04 completo."
