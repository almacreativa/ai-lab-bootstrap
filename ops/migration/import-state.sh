#!/usr/bin/env bash
set -euo pipefail

# import-state.sh — Importar estado desde servidor origen o disco montado
#
# Ejecutar en el servidor DESTINO después de bootstrap + apply-configs.
# Trae todo el estado (configs, auth, secrets, Docker volumes) desde
# el origen vía rsync SSH o desde un disco montado.
#
# Uso:
#   import-state.sh --source user@host       # rsync por SSH/Tailscale
#   import-state.sh --disk /mnt/i7local      # desde disco montado
#   import-state.sh --source user@host --dry  # dry-run (no toca nada)
#
# Prerrequisitos:
#   - bootstrap.sh + setup-instance.sh completados
#   - apply-configs.sh del repo privado ejecutado
#   - SSH access al origen (si se usa --source)
#   - Disco montado (si se usa --disk); ver notas sobre LVM abajo
#
# Notas LVM:
#   Si el disco usa LVM (instalación Ubuntu Server por defecto):
#     sudo vgscan
#     sudo vgchange -ay
#     sudo mount -o ro /dev/mapper/ubuntu--vg-ubuntu--lv /mnt/origen
#   Verificar con: lsblk (buscar "LVM2_member")

LOG_TAG="[import-state]"
MODE=""
SOURCE=""
DISK=""
DRY_RUN=false
LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"

log()  { echo "$LOG_TAG $*"; }
ok()   { echo "$LOG_TAG ✓ $*"; }
warn() { echo "$LOG_TAG ⚠ $*"; }
fail() { echo "$LOG_TAG ✗ $*"; exit 1; }

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] $*"
  else
    eval "$@"
  fi
}

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --source) SOURCE="$2"; MODE="rsync"; shift 2 ;;
    --disk)   DISK="$2";   MODE="disk";  shift 2 ;;
    --dry)    DRY_RUN=true; shift ;;
    *) echo "Uso: $0 --source user@host | --disk /mnt/path [--dry]"; exit 1 ;;
  esac
done

[ -z "$MODE" ] && fail "Especificar --source o --disk"

# Resolver paths según modo
src_path() {
  local rel="$1"
  if [ "$MODE" = "rsync" ]; then
    echo "${SOURCE}:${rel}"
  else
    # En disco, el home está en /mnt/punto/home/usuario/
    local disk_home
    disk_home=$(find "$DISK/home" -maxdepth 1 -type d ! -name home 2>/dev/null | head -1)
    if [ -z "$disk_home" ]; then
      fail "No se encontró un home de usuario en $DISK/home/"
    fi
    echo "${disk_home}${rel#$HOME}"
  fi
}

rsync_cmd() {
  local src="$1"
  local dst="$2"
  shift 2
  local extra_args=("$@")

  if [ "$MODE" = "rsync" ]; then
    run rsync -avz "${extra_args[@]}" "$src" "$dst"
  else
    run rsync -av "${extra_args[@]}" "$src" "$dst"
  fi
}

rsync_sudo() {
  local src="$1"
  local dst="$2"
  shift 2
  local extra_args=("$@")

  if [ "$MODE" = "rsync" ]; then
    run sudo rsync -avz --rsync-path=\"sudo rsync\" "${extra_args[@]}" "$src" "$dst"
  else
    run sudo rsync -a "${extra_args[@]}" "$src" "$dst"
  fi
}

echo "============================================"
echo "  Import State — $([ "$MODE" = "rsync" ] && echo "SSH/Tailscale" || echo "Disco montado")"
echo "============================================"
echo ""
echo "  Modo: $MODE"
[ "$MODE" = "rsync" ] && echo "  Origen: $SOURCE"
[ "$MODE" = "disk" ]  && echo "  Disco: $DISK"
echo "  Destino: $HOME"
[ "$DRY_RUN" = true ] && echo "  *** DRY-RUN — nada se modifica ***"
echo ""

# Verificar conectividad
if [ "$MODE" = "rsync" ]; then
  log "Verificando SSH..."
  ssh -o ConnectTimeout=5 "$SOURCE" "echo OK" &>/dev/null || fail "No se puede conectar a $SOURCE"
  ok "SSH conectado a $SOURCE"

  REMOTE_HOME=$(ssh "$SOURCE" 'echo $HOME')
  log "Home remoto: $REMOTE_HOME"
else
  [ -d "$DISK" ] || fail "Disco no montado en $DISK"
  DISK_HOME=$(find "$DISK/home" -maxdepth 1 -type d ! -name home 2>/dev/null | head -1)
  [ -d "$DISK_HOME" ] || fail "No se encontró home de usuario en $DISK/home/"
  ok "Disco montado: $DISK (home: $DISK_HOME)"
fi

# ─────────────────────────────────────────────
# FASE 1: Estado de usuario (configs, auth, tools)
# ─────────────────────────────────────────────
echo ""
log "═══ FASE 1/4: Estado de usuario ═══"

# Hermes — TODO excepto node/, .cache/, __pycache__, .hermes-env
log "Hermes (~/.hermes/)..."
mkdir -p "$HOME/.hermes"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz \
    --exclude='node/' --exclude='.cache/' --exclude='__pycache__/' \
    --exclude='*.pyc' --exclude='.local/' \
    "${SOURCE}:~/.hermes/" "$HOME/.hermes/"
else
  run rsync -av \
    --exclude='node/' --exclude='.cache/' --exclude='__pycache__/' \
    --exclude='*.pyc' --exclude='.local/' \
    "$DISK_HOME/.hermes/" "$HOME/.hermes/"
fi

# Claude Code — memoria, settings, MCP, credentials, sessions
log "Claude Code (~/.claude/)..."
mkdir -p "$HOME/.claude"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.claude/" "$HOME/.claude/"
else
  run rsync -av "$DISK_HOME/.claude/" "$HOME/.claude/"
fi

# Claude Code — OAuth credentials y MCP config (~/.claude.json, archivo suelto en HOME)
log "Claude Code OAuth (~/.claude.json)..."
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.claude.json" "$HOME/.claude.json" 2>/dev/null || true
else
  [ -f "$DISK_HOME/.claude.json" ] && \
    run rsync -av "$DISK_HOME/.claude.json" "$HOME/.claude.json"
fi

# Antigravity/Gemini — OAuth, config (excluir antigravity-cli/ y tmp/)
log "Antigravity (~/.gemini/)..."
mkdir -p "$HOME/.gemini"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz --exclude='antigravity-cli/' --exclude='tmp/' \
    "${SOURCE}:~/.gemini/" "$HOME/.gemini/"
else
  run rsync -av --exclude='antigravity-cli/' --exclude='tmp/' \
    "$DISK_HOME/.gemini/" "$HOME/.gemini/"
fi

# OpenCode — config (sin node_modules, se reconstruyen)
log "OpenCode config (~/.config/opencode/)..."
mkdir -p "$HOME/.config/opencode"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz --exclude='node_modules/' \
    "${SOURCE}:~/.config/opencode/" "$HOME/.config/opencode/"
else
  run rsync -av --exclude='node_modules/' \
    "$DISK_HOME/.config/opencode/" "$HOME/.config/opencode/"
fi

# OpenCode — historial de sesiones
log "OpenCode sesiones (~/.local/share/opencode/)..."
mkdir -p "$HOME/.local/share/opencode"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.local/share/opencode/" "$HOME/.local/share/opencode/"
else
  run rsync -av "$DISK_HOME/.local/share/opencode/" "$HOME/.local/share/opencode/"
fi

# Dagu — historial de ejecuciones
log "Dagu historial (~/.local/share/dagu/)..."
mkdir -p "$HOME/.local/share/dagu"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.local/share/dagu/" "$HOME/.local/share/dagu/"
else
  run rsync -av "$DISK_HOME/.local/share/dagu/" "$HOME/.local/share/dagu/"
fi

# GitHub CLI
log "GitHub CLI (~/.config/gh/)..."
mkdir -p "$HOME/.config/gh"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.config/gh/" "$HOME/.config/gh/"
else
  run rsync -av "$DISK_HOME/.config/gh/" "$HOME/.config/gh/"
fi

# Engram
log "Engram (~/.engram/)..."
mkdir -p "$HOME/.engram"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.engram/" "$HOME/.engram/"
else
  run rsync -av "$DISK_HOME/.engram/" "$HOME/.engram/"
fi

# NLM cookies
log "NLM cookies (~/.nlm/)..."
mkdir -p "$HOME/.nlm"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.nlm/" "$HOME/.nlm/"
else
  run rsync -av "$DISK_HOME/.nlm/" "$HOME/.nlm/"
fi

# SSH keys
log "SSH keys (~/.ssh/)..."
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.ssh/" "$HOME/.ssh/"
else
  run rsync -av "$DISK_HOME/.ssh/" "$HOME/.ssh/"
fi
run chmod 700 "$HOME/.ssh"
run "chmod 600 $HOME/.ssh/id_* 2>/dev/null || true"

# Git config
log "Git config (~/.gitconfig)..."
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.gitconfig" "$HOME/.gitconfig"
else
  run rsync -av "$DISK_HOME/.gitconfig" "$HOME/.gitconfig"
fi

# Tmux — config + plugins
log "Tmux (~/.tmux.conf + ~/.tmux/)..."
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/.tmux.conf" "$HOME/.tmux.conf"
  run rsync -avz --exclude='resurrect/' "${SOURCE}:~/.tmux/" "$HOME/.tmux/"
else
  run rsync -av "$DISK_HOME/.tmux.conf" "$HOME/.tmux.conf"
  run rsync -av --exclude='resurrect/' "$DISK_HOME/.tmux/" "$HOME/.tmux/"
fi

# Syncthing — identidad (cert/key = mismo Device ID) + config
log "Syncthing (~/.local/state/syncthing/)..."
mkdir -p "$HOME/.local/state/syncthing"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz \
    --exclude='index-v*/' --exclude='csrftokens.txt' \
    "${SOURCE}:~/.local/state/syncthing/" "$HOME/.local/state/syncthing/"
else
  run rsync -av \
    --exclude='index-v*/' --exclude='csrftokens.txt' \
    "$DISK_HOME/.local/state/syncthing/" "$HOME/.local/state/syncthing/"
fi

# shared/ — carpetas sincronizadas con Syncthing
log "Shared (~/shared/)..."
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/shared/" "$HOME/shared/"
elif [ -d "$DISK_HOME/shared" ]; then
  run rsync -av "$DISK_HOME/shared/" "$HOME/shared/"
fi

# ─────────────────────────────────────────────
# FASE 2: Estado del lab
# ─────────────────────────────────────────────
echo ""
log "═══ FASE 2/4: Estado del lab ═══"

# Secrets (.env files)
log "Secrets (scripts/.env + stacks/*/.env)..."
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/ai-lab/scripts/.env" "$LAB_DIR/scripts/.env"
  for stack in mem0 nlm-gateway odysseus outline paperclip; do
    run rsync -avz "${SOURCE}:~/ai-lab/stacks/$stack/.env" "$LAB_DIR/stacks/$stack/.env" 2>/dev/null || true
  done
else
  run rsync -av "$DISK_HOME/ai-lab/scripts/.env" "$LAB_DIR/scripts/.env"
  for stack in mem0 nlm-gateway odysseus outline paperclip; do
    [ -f "$DISK_HOME/ai-lab/stacks/$stack/.env" ] && \
      run rsync -av "$DISK_HOME/ai-lab/stacks/$stack/.env" "$LAB_DIR/stacks/$stack/.env"
  done
fi
run "chmod 600 $LAB_DIR/scripts/.env $LAB_DIR/stacks/*/.env 2>/dev/null || true"

# Knowledge base
log "Knowledge base (~/ai-lab/knowledge/)..."
mkdir -p "$LAB_DIR/knowledge"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/ai-lab/knowledge/" "$LAB_DIR/knowledge/"
else
  run rsync -av "$DISK_HOME/ai-lab/knowledge/" "$LAB_DIR/knowledge/"
fi

# data/core (bind mounts: mem0, odysseus)
log "Datos persistentes (~/ai-lab/data/core/)..."
mkdir -p "$LAB_DIR/data/core"
if [ "$MODE" = "rsync" ]; then
  run rsync -avz "${SOURCE}:~/ai-lab/data/core/" "$LAB_DIR/data/core/"
else
  run rsync -av "$DISK_HOME/ai-lab/data/core/" "$LAB_DIR/data/core/"
fi

# pg_dump de seguridad (si existen)
log "Dumps SQL de seguridad..."
if [ "$MODE" = "rsync" ]; then
  run "rsync -avz ${SOURCE}:~/ai-lab/migration-dumps/ $LAB_DIR/migration-dumps/ 2>/dev/null || true"
else
  [ -d "$DISK_HOME/ai-lab/migration-dumps" ] && \
    run rsync -av "$DISK_HOME/ai-lab/migration-dumps/" "$LAB_DIR/migration-dumps/"
fi

# ─────────────────────────────────────────────
# FASE 3/4: Docker volumes
# ─────────────────────────────────────────────
echo ""
log "═══ FASE 3/4: Docker volumes ═══"
warn "Requiere sudo para preservar permisos (UID/GID de PostgreSQL, etc.)"
echo ""

VOLUMES=(
  "paperclip_pgdata_v2"
  "paperclip_paperclip-data"
  "outline_outline-pg"
  "outline_outline-data"
  "uptime-kuma"
  "portainer_data"
  "odysseus_chromadb-odysseus-data"
  "odysseus_searxng-odysseus-data"
)

SKIP_VOLUMES=("mem0_ollama")

for vol in "${VOLUMES[@]}"; do
  log "Volume: $vol"

  # Crear volume si no existe
  if ! docker volume inspect "$vol" &>/dev/null; then
    run docker volume create "$vol"
  fi

  VOL_PATH=$(docker volume inspect "$vol" 2>/dev/null | grep -o '"Mountpoint": "[^"]*"' | cut -d'"' -f4)
  [ -z "$VOL_PATH" ] && VOL_PATH="/var/lib/docker/volumes/$vol/_data"

  if [ "$MODE" = "rsync" ]; then
    run sudo rsync -avz --rsync-path=\"sudo rsync\" \
      "${SOURCE}:/var/lib/docker/volumes/${vol}/_data/" "${VOL_PATH}/"
  else
    SRC_VOL="$DISK/var/lib/docker/volumes/${vol}/_data"
    if [ -d "$SRC_VOL" ]; then
      run sudo rsync -a "$SRC_VOL/" "${VOL_PATH}/"
    else
      warn "  Volume $vol no encontrado en disco ($SRC_VOL)"
    fi
  fi
done

for vol in "${SKIP_VOLUMES[@]}"; do
  log "SKIP: $vol (se re-descarga: docker exec ollama ollama pull nomic-embed-text)"
done

# ─────────────────────────────────────────────
# FASE 4/4: Reconstruir dependencias
# ─────────────────────────────────────────────
echo ""
log "═══ FASE 4/4: Reconstruir dependencias ═══"

# OpenCode node_modules
if [ -f "$HOME/.config/opencode/package.json" ]; then
  log "Reconstruyendo node_modules de OpenCode..."
  run "cd $HOME/.config/opencode && npm install 2>&1 | tail -1"
fi

# TPM plugins (tmux)
if [ -d "$HOME/.tmux/plugins/tpm" ]; then
  log "Tmux plugins (TPM ya copiado, instalar plugins)..."
  run "$HOME/.tmux/plugins/tpm/bin/install_plugins 2>/dev/null || true"
fi

echo ""
echo "============================================"
echo "  Import completado"
echo "============================================"
echo ""
echo "  Próximos pasos:"
echo "    1. rehome.sh — adaptar IPs y hostname:"
echo "       bash ~/ai-lab/ops/backup/rehome.sh --dry-run"
echo "       bash ~/ai-lab/ops/backup/rehome.sh"
echo ""
echo "    2. Docker networks:"
echo "       docker network create ai-lab-net 2>/dev/null"
echo "       docker network create mem0_default 2>/dev/null"
echo "       docker network create outline_default 2>/dev/null"
echo "       docker network create paperclip_default 2>/dev/null"
echo ""
echo "    3. Arranque escalonado:"
echo "       # Primero DBs (verificar que volumes están correctos):"
echo "       cd ~/ai-lab/stacks/paperclip && docker compose up -d db"
echo "       cd ~/ai-lab/stacks/outline && docker compose up -d outline-postgres"
echo "       sleep 10"
echo ""
echo "       # Si los volumes se copiaron directo, las DBs arrancan con datos."
echo "       # Si se usaron pg_dump, restaurar ahora:"
echo "       # docker exec -i paperclip-db-1 psql -U paperclip < ~/ai-lab/migration-dumps/paperclip-db-1.sql"
echo "       # docker exec -i outline-postgres psql -U outline < ~/ai-lab/migration-dumps/outline-postgres.sql"
echo ""
echo "       # Luego el resto:"
echo "       for s in ~/ai-lab/stacks/*/; do"
echo "         [ -f \"\$s/docker-compose.yml\" ] && cd \"\$s\" && docker compose up -d"
echo "       done"
echo ""
echo "    4. Servicios systemd:"
echo "       systemctl --user daemon-reload"
echo "       systemctl --user start dagu moolmesh centro-de-comando"
echo "       sudo systemctl start hermes"
echo ""
echo "    5. Ollama modelo (se re-descarga):"
echo "       docker exec ollama ollama pull nomic-embed-text"
echo ""
echo "    6. Rehome manual — Uptime Kuma:"
echo "       Abrir http://<TAILSCALE_IP>:3001"
echo "       Actualizar la URL del monitor 'Paperclip' a la nueva IP"
echo ""
echo "    7. Verificar:"
echo "       ~/ai-lab/ops/guards/core-guard.sh"
echo "       ~/ai-lab/ops/guards/bootstrap-guard.sh"
echo "============================================"
