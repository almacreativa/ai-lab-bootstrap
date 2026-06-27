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

# Claude Code — instalador oficial (auto-update incluido)
if ! command -v claude &>/dev/null; then
  if curl -fsSL https://claude.ai/install.sh | bash 2>&1; then
    if command -v claude &>/dev/null; then
      log "Claude Code instalado ($(claude --version 2>/dev/null | head -1))."
      warn "Completar login después del bootstrap: claude"
    else
      warn "Claude Code: instalador completó pero 'claude' no está en PATH."
    fi
  else
    warn "Claude Code: instalador falló — ver https://code.claude.com/docs/en/quickstart"
  fi
else
  log "Claude Code ya instalado ($(claude --version 2>/dev/null | head -1))."
fi

# OpenCode — instalador oficial
if ! command -v opencode &>/dev/null; then
  if curl -fsSL https://opencode.ai/install | bash 2>&1; then
    if command -v opencode &>/dev/null; then
      log "OpenCode instalado ($(opencode --version 2>/dev/null | head -1))."
      warn "Completar login después del bootstrap: opencode"
    else
      warn "OpenCode: instalador completó pero 'opencode' no está en PATH."
    fi
  else
    warn "OpenCode: instalador falló — ver https://opencode.ai"
  fi
else
  log "OpenCode ya instalado ($(opencode --version 2>/dev/null | head -1))."
fi

# Aliases — detectar shell (zsh es el default en macOS desde Catalina)
SHELL_RC="$HOME/.zshrc"
[ "$(basename "$SHELL")" = "bash" ] && SHELL_RC="$HOME/.bash_profile"

if ! grep -q "alias claude-d=" "$SHELL_RC" 2>/dev/null; then
  echo "" >> "$SHELL_RC"
  echo "# AI Lab" >> "$SHELL_RC"
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
  echo "alias claude-d='claude --dangerously-skip-permissions'" >> "$SHELL_RC"
  [ "$INSTALL_HERMES" = "true" ] && echo "alias hermes='\$HOME/.hermes-env/bin/hermes'" >> "$SHELL_RC"
  log "Aliases y PATH agregados a $SHELL_RC."
fi

log "Módulo 04 completo."
