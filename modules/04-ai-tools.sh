#!/bin/bash
# Módulo 04 — Herramientas AI: Claude Code, OpenCode, Chromium, Playwright MCP, Engram, MoolMesh, Horizonte 1 (tmux-bridge, clawhip, tmux-gateway)

log "Paso 4/6 — Herramientas AI..."

# Asegurar que nvm/node/npm y binarios locales estén en PATH
# (módulo 02 los instala pero el PATH solo se persiste en .bashrc)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

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
# Nota: el repo publica releases "pi-v*" (sin binarios) y "v*" (con binarios).
# /releases/latest puede apuntar a un pi-v* sin assets. Usamos la API para
# encontrar el primer release con tag "v*" que tenga assets descargables.
if ! command -v engram &>/dev/null; then
  ENGRAM_TMP_DIR="/tmp/engram-install"
  mkdir -p "$HOME/.local/bin" "$ENGRAM_TMP_DIR"
  ENGRAM_TAG=$(curl -fsSL "https://api.github.com/repos/Gentleman-Programming/engram/releases" 2>/dev/null \
    | grep -oP '"tag_name":\s*"\Kv[0-9][^"]*' | head -1)
  if [ -z "$ENGRAM_TAG" ]; then
    warn "Engram: no se pudo detectar la version mas reciente"
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
        warn "Engram: tar.gz no contenia binario 'engram'"
      fi
    else
      warn "Engram: descarga fallo — instalar manualmente desde github.com/Gentleman-Programming/engram"
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

# Playwright MCP — visual testing headless para agentes AI
# Permite a Claude Code, OpenCode, Hermes navegar webs, tomar screenshots
# y leer el accessibility tree sin display físico
if ! command -v playwright-mcp &>/dev/null; then
  npm install -g @playwright/mcp
  log "Playwright MCP instalado ($(playwright-mcp --version 2>/dev/null || echo 'OK'))."
else
  log "Playwright MCP ya instalado ($(playwright-mcp --version 2>/dev/null)), saltando."
fi

# Instalar Chromium de Playwright + dependencias de sistema para renderizado headless
if [ ! -d "$HOME/.cache/ms-playwright/chromium-"* ] 2>/dev/null; then
  npx playwright install --with-deps chromium
  log "Playwright Chromium + deps de sistema instalados."
else
  log "Playwright Chromium ya instalado, saltando."
fi

# Wrapper script para MCP servers
mkdir -p "$HOME/ai-lab/scripts"
PLAYWRIGHT_MCP_SCRIPT="$HOME/ai-lab/scripts/playwright-mcp.sh"
if [ ! -f "$PLAYWRIGHT_MCP_SCRIPT" ]; then
  cat > "$PLAYWRIGHT_MCP_SCRIPT" << 'PWEOF'
#!/bin/bash
# playwright-mcp.sh — Playwright MCP server para agentes IA (headless)
# Navegación web, screenshots, accessibility tree en servidor sin display
exec playwright-mcp \
  --headless \
  --browser chromium \
  --viewport-size 1280x720 \
  --caps vision \
  "$@"
PWEOF
  chmod +x "$PLAYWRIGHT_MCP_SCRIPT"
  log "playwright-mcp.sh creado en ai-lab/scripts/."
else
  log "playwright-mcp.sh ya existe, saltando."
fi

# ─────────────────────────────────────────────
# Horizonte 1 — Orquestación tmux
# ─────────────────────────────────────────────

# tmux-bridge-mcp — MCP server (stdio, Node.js) para comunicación inter-agente
if [ ! -d "$HOME/ai-lab/repos/tmux-bridge-mcp" ]; then
  if command -v git &>/dev/null && command -v node &>/dev/null; then
    git clone https://github.com/howardpen9/tmux-bridge-mcp.git "$HOME/ai-lab/repos/tmux-bridge-mcp" \
      && cd "$HOME/ai-lab/repos/tmux-bridge-mcp" && npm install
    log "tmux-bridge-mcp instalado."
  else
    warn "tmux-bridge-mcp: requiere git + node — saltando."
  fi
else
  log "tmux-bridge-mcp ya existe, saltando."
fi

# Wrapper script para tmux-bridge-mcp
TMUX_BRIDGE_SCRIPT="$HOME/ai-lab/scripts/tmux-bridge-mcp.sh"
if [ ! -f "$TMUX_BRIDGE_SCRIPT" ]; then
  mkdir -p "$HOME/ai-lab/scripts"
  cat > "$TMUX_BRIDGE_SCRIPT" << 'TBEOF'
#!/bin/bash
# tmux-bridge-mcp.sh — MCP server para comunicación inter-agente vía tmux
# 9 tools: tmux_list, tmux_read, tmux_type, tmux_message, tmux_keys,
#          tmux_name, tmux_resolve, tmux_id, tmux_doctor
exec node "$HOME/ai-lab/repos/tmux-bridge-mcp/dist/cli.js" "$@"
TBEOF
  chmod +x "$TMUX_BRIDGE_SCRIPT"
  log "tmux-bridge-mcp.sh creado en ai-lab/scripts/."
else
  log "tmux-bridge-mcp.sh ya existe, saltando."
fi

# ─────────────────────────────────────────────
# Binarios PREBUILT de orquestación (clawhip, tmux-gateway)
# Decisión (hito 2026-07-26): instalar binarios prebuilt de release en vez de
# compilar con cargo. Así NO se exige toolchain Rust en cada nodo (reproducibilidad).
# `cargo build` queda SOLO como fallback si no hay binario prebuilt para la plataforma.
# Origen de los binarios:
#   - tmux-gateway: releases upstream (github.com/tupe12334/tmux-gateway); targets
#     x86_64/aarch64-unknown-linux-gnu (+ macOS). Verificados con sha256 sibling.
#   - clawhip: upstream (github.com/Yeachan-Heo/clawhip) usa cargo-dist pero NO
#     publica los tarballs Linux como assets (solo dist-manifest.json). El lab hospeda
#     su propio binario en el fork almacreativa/clawhip (release v0.6.11-lab, x86_64,
#     MIT — build sin modificaciones del source de Yeachan Heo). CLAWHIP_PREBUILT_URL
#     override; CLAWHIP_LAB_TAG cambia el tag del fork. Sin asset (arm64) cae a cargo.
# Overrides por env: CLAWHIP_VER, CLAWHIP_LAB_TAG, CLAWHIP_PREBUILT_URL,
#                    TMUX_GATEWAY_VER, TMUX_GATEWAY_PREBUILT_URL.
# ─────────────────────────────────────────────

# Triple de plataforma para los artifacts de release
case "$(uname -m)" in
  x86_64)        RUST_TRIPLE="x86_64-unknown-linux-gnu" ;;
  aarch64|arm64) RUST_TRIPLE="aarch64-unknown-linux-gnu" ;;
  *)             RUST_TRIPLE="" ;;
esac

# Instala un binario Rust prebuilt desde un tarball de release.
# Args: nombre  url_tarball  url_sha256(o "")  ext(tar.gz|tar.xz)
# Devuelve 0 si instaló, 1 si no (para que el caller caiga al fallback cargo).
install_prebuilt_bin() {
  local name="$1" url="$2" sha_url="$3" ext="$4"
  local tmp; tmp=$(mktemp -d "/tmp/${name}-prebuilt.XXXXXX")
  local arc="$tmp/${name}.${ext}"
  if ! curl -fsSL -o "$arc" "$url" 2>/dev/null; then
    rm -rf "$tmp"; return 1
  fi
  if [ -n "$sha_url" ]; then
    local want; want=$(curl -fsSL "$sha_url" 2>/dev/null | awk '{print $1}')
    if [ -n "$want" ]; then
      local got; got=$(sha256sum "$arc" | awk '{print $1}')
      if [ "$want" != "$got" ]; then
        warn "$name: sha256 no coincide (esperado $want, obtuvo $got) — descarto prebuilt."
        rm -rf "$tmp"; return 1
      fi
    fi
  fi
  tar -xf "$arc" -C "$tmp" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  local found; found=$(find "$tmp" -type f -name "$name" | head -1)
  if [ -z "$found" ]; then
    warn "$name: el tarball prebuilt no contenía el binario '$name'."
    rm -rf "$tmp"; return 1
  fi
  install -m 0755 "$found" "$HOME/.local/bin/$name"
  rm -rf "$tmp"; return 0
}

# clawhip — Daemon Rust para monitoreo tmux y enrutamiento de eventos
CLAWHIP_VER="${CLAWHIP_VER:-v0.6.11}"
# Tag del release del fork del lab (almacreativa/clawhip) que hospeda el binario prebuilt.
CLAWHIP_LAB_TAG="${CLAWHIP_LAB_TAG:-v0.6.11-lab}"
if [ ! -f "$HOME/.local/bin/clawhip" ]; then
  mkdir -p "$HOME/.local/bin"
  CLAWHIP_URL="${CLAWHIP_PREBUILT_URL:-}"
  # Default: release del fork del lab (almacreativa/clawhip). Upstream (Yeachan-Heo)
  # no publica los tarballs Linux como assets; el lab hospeda su propio binario x86_64.
  # Para arm64/glibc viejo el asset no existe (404) → cae al fallback cargo. Fuente MIT.
  [ -z "$CLAWHIP_URL" ] && [ -n "$RUST_TRIPLE" ] && \
    CLAWHIP_URL="https://github.com/almacreativa/clawhip/releases/download/${CLAWHIP_LAB_TAG}/clawhip-${RUST_TRIPLE}.tar.xz"
  if [ -n "$CLAWHIP_URL" ] && install_prebuilt_bin "clawhip" "$CLAWHIP_URL" "${CLAWHIP_URL}.sha256" "tar.xz"; then
    log "clawhip prebuilt instalado ($(clawhip --version 2>/dev/null || echo "$CLAWHIP_VER"))."
  elif command -v cargo &>/dev/null && [ -d "$HOME/ai-lab/repos/clawhip" ]; then
    warn "clawhip: sin binario prebuilt para $RUST_TRIPLE — fallback a cargo (requiere Rust)."
    log "clawhip: compilando desde source (puede tardar 1-5 min)..."
    if (cd "$HOME/ai-lab/repos/clawhip" && cargo build --release 2>&1 | tail -3) \
       && [ -f "$HOME/ai-lab/repos/clawhip/target/release/clawhip" ]; then
      install -m 0755 "$HOME/ai-lab/repos/clawhip/target/release/clawhip" "$HOME/.local/bin/clawhip"
      log "clawhip instalado desde source ($(clawhip --version 2>/dev/null || echo 'OK'))."
    else
      warn "clawhip: compilación falló — verificar logs."
    fi
  else
    warn "clawhip: sin prebuilt y sin cargo/repo — exportar CLAWHIP_PREBUILT_URL o instalar Rust."
  fi
else
  log "clawhip ya instalado ($(clawhip --version 2>/dev/null || echo 'presente')), saltando."
fi

# clawhip config directory
if [ ! -d "$HOME/.clawhip" ] && [ -f "$HOME/.local/bin/clawhip" ]; then
  mkdir -p "$HOME/.clawhip"
  log "Directorio ~/.clawhip/ creado."
fi

# tmux-gateway — API REST/gRPC/WebSocket sobre tmux (Rust)
TMUX_GATEWAY_VER="${TMUX_GATEWAY_VER:-v0.1.1}"
if [ ! -f "$HOME/.local/bin/tmux-gateway" ]; then
  mkdir -p "$HOME/.local/bin"
  TG_URL="${TMUX_GATEWAY_PREBUILT_URL:-}"
  [ -z "$TG_URL" ] && [ -n "$RUST_TRIPLE" ] && \
    TG_URL="https://github.com/tupe12334/tmux-gateway/releases/download/${TMUX_GATEWAY_VER}/tmux-gateway-${TMUX_GATEWAY_VER}-${RUST_TRIPLE}.tar.gz"
  if [ -n "$TG_URL" ] && install_prebuilt_bin "tmux-gateway" "$TG_URL" "${TG_URL}.sha256" "tar.gz"; then
    log "tmux-gateway prebuilt instalado ($TMUX_GATEWAY_VER)."
  elif command -v cargo &>/dev/null && command -v protoc &>/dev/null && [ -d "$HOME/ai-lab/repos/tmux-gateway" ]; then
    warn "tmux-gateway: sin binario prebuilt para $RUST_TRIPLE — fallback a cargo (requiere Rust + protoc)."
    log "tmux-gateway: compilando desde source (puede tardar 1-5 min)..."
    if (cd "$HOME/ai-lab/repos/tmux-gateway" && cargo build --release 2>&1 | tail -3) \
       && [ -f "$HOME/ai-lab/repos/tmux-gateway/target/release/tmux-gateway" ]; then
      install -m 0755 "$HOME/ai-lab/repos/tmux-gateway/target/release/tmux-gateway" "$HOME/.local/bin/tmux-gateway"
      log "tmux-gateway instalado desde source."
    else
      warn "tmux-gateway: compilación falló — verificar logs."
    fi
  else
    warn "tmux-gateway: sin prebuilt y sin cargo+protoc — exportar TMUX_GATEWAY_PREBUILT_URL o instalar Rust+protoc."
  fi
else
  log "tmux-gateway ya instalado, saltando."
fi

log "Módulo 04 completo."
