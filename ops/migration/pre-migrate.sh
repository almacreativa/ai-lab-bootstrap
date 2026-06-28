#!/usr/bin/env bash
set -euo pipefail

# pre-migrate.sh — Preparar servidor origen para migración
#
# Ejecutar en el servidor ORIGEN antes de transferir estado.
# Verifica que los servicios están parados, hace pg_dump de seguridad,
# y reporta qué está listo para transferir.
#
# Uso:
#   bash pre-migrate.sh              # dry-run (solo verifica)
#   bash pre-migrate.sh --dump       # verifica + genera pg_dumps de seguridad

LOG_TAG="[pre-migrate]"
DO_DUMP=false
[ "${1:-}" = "--dump" ] && DO_DUMP=true

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
DUMP_DIR="$LAB_DIR/migration-dumps"

log()  { echo "$LOG_TAG $*"; }
warn() { echo "$LOG_TAG ⚠ $*"; }
ok()   { echo "$LOG_TAG ✓ $*"; }
fail() { echo "$LOG_TAG ✗ $*"; }

echo "============================================"
echo "  Pre-migrate — verificación del origen"
echo "============================================"
echo ""

# 1. Verificar que servicios están parados
log "1/5 — Servicios"
RUNNING=0

for svc in dagu moolmesh centro-de-comando hermes-xai-proxy nlm-gateway; do
  if systemctl --user is-active "$svc" &>/dev/null 2>&1; then
    fail "$svc todavía corriendo"
    RUNNING=$((RUNNING + 1))
  fi
done

if sudo systemctl is-active hermes &>/dev/null 2>&1; then
  fail "hermes (system) todavía corriendo"
  RUNNING=$((RUNNING + 1))
fi

CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
if [ "$CONTAINERS" -gt 0 ]; then
  fail "$CONTAINERS containers Docker todavía corriendo:"
  docker ps --format "  {{.Names}}" 2>/dev/null
  RUNNING=$((RUNNING + CONTAINERS))
fi

[ "$RUNNING" -eq 0 ] && ok "Todos los servicios parados" || warn "$RUNNING servicios aún activos — parar antes de continuar"

# 2. pg_dump de seguridad (opcional)
echo ""
log "2/5 — PostgreSQL dumps"

if [ "$DO_DUMP" = true ]; then
  mkdir -p "$DUMP_DIR"

  PG_STACKS=("paperclip:paperclip-db-1:paperclip" "outline:outline-postgres:outline")

  for entry in "${PG_STACKS[@]}"; do
    IFS=: read -r STACK CTR DB_USER <<< "$entry"
    COMPOSE="$LAB_DIR/stacks/$STACK/docker-compose.yml"

    if [ ! -f "$COMPOSE" ]; then
      warn "Stack $STACK no encontrado — saltando"
      continue
    fi

    log "  Levantando DB de $STACK temporalmente..."
    cd "$LAB_DIR/stacks/$STACK"

    # Levantar solo el servicio de DB
    docker compose up -d db 2>/dev/null || docker compose up -d "${CTR%%-*}" 2>/dev/null || \
      docker compose up -d "$(docker compose config --services | grep -i 'db\|postgres' | head -1)" 2>/dev/null

    # Esperar a que esté healthy
    for i in $(seq 1 30); do
      if docker exec "$CTR" pg_isready -U "$DB_USER" &>/dev/null; then
        break
      fi
      sleep 1
    done

    if docker exec "$CTR" pg_isready -U "$DB_USER" &>/dev/null; then
      DUMP_FILE="$DUMP_DIR/${CTR}.sql"
      docker exec -i "$CTR" pg_dump -U "$DB_USER" > "$DUMP_FILE" 2>/dev/null
      LINES=$(wc -l < "$DUMP_FILE")
      ok "$CTR: $LINES líneas → $DUMP_FILE"
    else
      fail "$CTR: no respondió en 30s"
    fi

    docker compose down 2>/dev/null
  done
else
  log "  Saltando (usar --dump para generar)"
  log "  Los volumes se copian directamente (cold backup limpio)"
fi

# 3. Inventario de estado a transferir
echo ""
log "3/5 — Inventario de estado"

ITEMS=(
  "$HOME/.hermes/:Hermes (state, config, skills, sessions)"
  "$HOME/.claude/:Claude Code (memory, settings, MCP, credentials)"
  "$HOME/.gemini/:Antigravity (OAuth, config)"
  "$HOME/.config/opencode/:OpenCode (config)"
  "$HOME/.local/share/opencode/:OpenCode (historial sesiones)"
  "$HOME/.local/share/dagu/:Dagu (historial ejecuciones)"
  "$HOME/.engram/:Engram (memoria cross-agente)"
  "$HOME/.nlm/:NLM (cookies de sesión)"
  "$HOME/.ssh/:SSH keys"
  "$HOME/.gitconfig:Git config"
  "$HOME/.tmux.conf:Tmux config"
  "$HOME/.tmux/:Tmux (plugins, resurrect)"
  "$LAB_DIR/scripts/.env:Lab secrets"
  "$LAB_DIR/knowledge/:Knowledge base"
  "$LAB_DIR/data/core/:Datos persistentes (bind mounts)"
)

TOTAL_SIZE=0
for item in "${ITEMS[@]}"; do
  IFS=: read -r PATH_ITEM DESC <<< "$item"
  if [ -e "$PATH_ITEM" ]; then
    SIZE=$(du -sh "$PATH_ITEM" 2>/dev/null | cut -f1)
    ok "$DESC: $SIZE"
  else
    warn "$DESC: no existe"
  fi
done

# .env files de stacks
ENV_COUNT=0
for envf in "$LAB_DIR"/stacks/*/.env; do
  [ -f "$envf" ] && ENV_COUNT=$((ENV_COUNT + 1))
done
ok "Stacks .env: $ENV_COUNT archivos"

# 4. Docker volumes
echo ""
log "4/5 — Docker volumes"

MIGRATE_VOLS=(
  "paperclip_pgdata_v2"
  "paperclip_paperclip-data"
  "outline_outline-pg"
  "outline_outline-data"
  "uptime-kuma"
  "portainer_data"
  "odysseus_chromadb-odysseus-data"
  "odysseus_searxng-odysseus-data"
)
SKIP_VOLS=("mem0_ollama")

for vol in "${MIGRATE_VOLS[@]}"; do
  if docker volume inspect "$vol" &>/dev/null; then
    SIZE=$(docker run --rm -v "$vol":/data alpine du -sh /data 2>/dev/null | cut -f1)
    ok "$vol: $SIZE"
  else
    warn "$vol: no existe"
  fi
done

for vol in "${SKIP_VOLS[@]}"; do
  if docker volume inspect "$vol" &>/dev/null; then
    SIZE=$(docker run --rm -v "$vol":/data alpine du -sh /data 2>/dev/null | cut -f1)
    log "  SKIP $vol: $SIZE (se re-descarga con ollama pull)"
  fi
done

# 5. Conectividad
echo ""
log "5/5 — Conectividad"
TS_IP=$(tailscale ip -4 2>/dev/null || echo "N/A")
ok "Tailscale IP: $TS_IP"
ok "Hostname: $(hostname -s)"
ok "Usuario: $(whoami)"
ok "Home: $HOME"

echo ""
echo "============================================"
echo "  Origen listo para migración"
echo ""
if [ "$DO_DUMP" = true ] && [ -d "$DUMP_DIR" ]; then
  echo "  Dumps SQL: $DUMP_DIR/"
fi
echo ""
echo "  Desde el DESTINO, ejecutar:"
echo "    import-state.sh --source $(whoami)@$TS_IP"
echo "  O montar disco USB y ejecutar:"
echo "    import-state.sh --disk /mnt/origen"
echo "============================================"
