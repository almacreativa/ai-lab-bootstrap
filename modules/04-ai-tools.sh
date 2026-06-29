#!/bin/bash
# Módulo 04 — Herramientas AI: Claude Code, Opencode, Chromium, Xvfb

log "Paso 4/6 — Herramientas AI..."

# Asegurar que nvm/node/npm y binarios locales estén en PATH
# (módulo 02 los instala pero el PATH solo se persiste en .bashrc)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"

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

# Aliases en .bashrc
BASHRC="$HOME/.bashrc"
if ! grep -q "alias claude-d=" "$BASHRC"; then
  echo "" >> "$BASHRC"
  echo "# AI Lab" >> "$BASHRC"
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$BASHRC"
  echo "alias claude-d='claude --dangerously-skip-permissions'" >> "$BASHRC"
  [ "$INSTALL_HERMES" = "true" ] && echo "alias hermes='\$HOME/.hermes-env/bin/hermes'" >> "$BASHRC"
  log "Aliases y PATH agregados a .bashrc."
fi

# Engram — memoria persistente cross-session para agentes AI (binario Go estático)
if ! command -v engram &>/dev/null; then
  ENGRAM_TMP_DIR="/tmp/engram-install"
  mkdir -p "$HOME/.local/bin" "$ENGRAM_TMP_DIR"
  ENGRAM_TAG=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/Gentleman-Programming/engram/releases/latest" 2>/dev/null | grep -oP 'tag/\K.*')
  if [ -z "$ENGRAM_TAG" ]; then
    warn "Engram: no se pudo detectar la versión más reciente"
  else
    ENGRAM_VER="${ENGRAM_TAG#v}"
    ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && ARCH="amd64"; [ "$ARCH" = "aarch64" ] && ARCH="arm64"
    ENGRAM_URL="https://github.com/Gentleman-Programming/engram/releases/download/${ENGRAM_TAG}/engram_${ENGRAM_VER}_linux_${ARCH}.tar.gz"
    if curl -fsSL -o "$ENGRAM_TMP_DIR/engram.tar.gz" "$ENGRAM_URL" 2>/dev/null; then
      tar -xzf "$ENGRAM_TMP_DIR/engram.tar.gz" -C "$ENGRAM_TMP_DIR"
      if [ -f "$ENGRAM_TMP_DIR/engram" ]; then
        mv "$ENGRAM_TMP_DIR/engram" "$HOME/.local/bin/engram"
        chmod +x "$HOME/.local/bin/engram"
        log "Engram ${ENGRAM_TAG} instalado."
      else
        warn "Engram: tar.gz no contenía binario 'engram'"
      fi
    else
      warn "Engram: descarga falló — instalar manualmente desde github.com/Gentleman-Programming/engram"
    fi
  fi
  rm -rf "$ENGRAM_TMP_DIR"
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
