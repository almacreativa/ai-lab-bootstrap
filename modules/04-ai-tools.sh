#!/bin/bash
# Módulo 04 — Herramientas AI: Claude Code, Opencode, Chromium, Xvfb

log "Paso 4/6 — Herramientas AI..."

# Asegurar que nvm/node/npm estén en PATH (módulo 02 los instala pero
# el PATH solo se persiste en .bashrc, no en esta sesión de bootstrap)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"

if ! command -v npm &>/dev/null; then
  warn "npm no encontrado en PATH — Claude Code y Opencode no se instalarán."
  warn "Verificar que el módulo 02-node.sh completó correctamente."
fi

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

# Claude Code via npm
if ! command -v claude &>/dev/null; then
  if command -v npm &>/dev/null; then
    npm install -g @anthropic-ai/claude-code 2>&1 || warn "npm install -g claude-code falló"
    # npm global bin puede no estar en PATH — buscar y agregar
    NPM_BIN=$(npm config get prefix 2>/dev/null)/bin
    [ -d "$NPM_BIN" ] && export PATH="$NPM_BIN:$PATH"
    if command -v claude &>/dev/null; then
      log "Claude Code instalado ($(claude --version 2>/dev/null | head -1))."
      warn "Completar login después del bootstrap: claude"
    else
      warn "Claude Code: npm install completó pero 'claude' no está en PATH."
      warn "Verificar con: npm list -g @anthropic-ai/claude-code"
    fi
  else
    warn "Claude Code no instalado — npm no disponible."
  fi
else
  log "Claude Code ya instalado ($(claude --version 2>/dev/null | head -1))."
fi

# Opencode
if ! command -v opencode &>/dev/null && [ ! -f "$HOME/.opencode/bin/opencode" ]; then
  if command -v npm &>/dev/null; then
    mkdir -p "$HOME/.opencode"
    cd "$HOME/.opencode"
    if npm install opencode-ai 2>&1; then
      mkdir -p "$HOME/.opencode/bin"
      ln -sf "$HOME/.opencode/node_modules/.bin/opencode" "$HOME/.opencode/bin/opencode" 2>/dev/null || true
      if [ -x "$HOME/.opencode/bin/opencode" ]; then
        log "Opencode instalado en ~/.opencode/bin/opencode"
      else
        warn "Opencode: npm install completó pero el binario no existe en node_modules/.bin/"
      fi
    else
      warn "npm install opencode-ai falló — instalar manualmente desde opencode.ai"
    fi
    cd - > /dev/null
  else
    warn "Opencode no instalado — npm no disponible."
  fi
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

# Engram — memoria persistente cross-session para agentes AI (binario Go estático)
if ! command -v engram &>/dev/null; then
  ENGRAM_VERSION="latest"
  ENGRAM_URL="https://github.com/Gentleman-Programming/engram/releases/${ENGRAM_VERSION}/download/engram-linux-amd64"
  ENGRAM_TMP="/tmp/engram-download"
  mkdir -p "$HOME/.local/bin"
  if curl -fsSL -o "$ENGRAM_TMP" "$ENGRAM_URL" 2>/dev/null; then
    mv "$ENGRAM_TMP" "$HOME/.local/bin/engram"
    chmod +x "$HOME/.local/bin/engram"
    log "Engram instalado ($(engram version 2>/dev/null || echo 'OK'))."
  else
    rm -f "$ENGRAM_TMP"
    warn "Engram: descarga falló — instalar manualmente desde github.com/Gentleman-Programming/engram"
  fi
else
  log "Engram ya instalado ($(engram version 2>/dev/null || echo 'presente')), saltando."
fi

# MoolMesh — observatorio de sesiones de agentes AI
if ! command -v mool &>/dev/null; then
  if command -v uv &>/dev/null; then
    uv tool install moolmesh
    log "MoolMesh instalado ($(mool --version 2>/dev/null || echo 'OK'))."
  else
    warn "MoolMesh requiere uv — instalar uv primero."
  fi
else
  log "MoolMesh ya instalado ($(mool --version 2>/dev/null || echo 'presente')), saltando."
fi

# MoolMesh systemd user service
mkdir -p "$HOME/.config/systemd/user"
if [ ! -f "$HOME/.config/systemd/user/moolmesh.service" ]; then
  if command -v mool &>/dev/null; then
    MOOL_PATH=$(which mool)
    cat > "$HOME/.config/systemd/user/moolmesh.service" << MOOLEOF
[Unit]
Description=MoolMesh AI Agent Observatory
After=network.target

[Service]
Type=simple
ExecStart=${MOOL_PATH} daemon start --host 0.0.0.0 --port 5200
Restart=on-failure
RestartSec=10
Environment=HOME=${HOME}

[Install]
WantedBy=default.target
MOOLEOF
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    systemctl --user daemon-reload
    systemctl --user enable moolmesh.service
    log "moolmesh.service instalado y habilitado (systemd user)."
    warn "Iniciar con: systemctl --user start moolmesh"
  fi
else
  log "moolmesh.service ya existe — no se sobreescribe."
fi

log "Módulo 04 completo."
