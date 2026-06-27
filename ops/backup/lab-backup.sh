#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
DUMP_DIR="/tmp/lab-backup-dumps"
LOG_TAG="[lab-backup]"
ENV_FILE="${LAB_DIR}/scripts/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "$LOG_TAG ERROR: No se encontró $ENV_FILE — correr setup-backup.sh primero"
  exit 1
fi

source "$ENV_FILE"

RESTIC_REPO="${RESTIC_REPOSITORY:-}"
if [ -z "$RESTIC_REPO" ]; then
  echo "$LOG_TAG ERROR: RESTIC_REPOSITORY no definido en $ENV_FILE"
  exit 1
fi

export RESTIC_REPOSITORY="$RESTIC_REPO"
export B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-}"
export B2_ACCOUNT_KEY="${B2_BACKUP_KEY:-}"
export RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"

if [ -z "$RESTIC_PASSWORD" ]; then
  echo "$LOG_TAG ERROR: RESTIC_PASSWORD no definido en $ENV_FILE"
  exit 1
fi

NOTIFY_SCRIPT="${LAB_DIR}/scripts/telegram-notify.sh"
notify() {
  local msg="$1" level="${2:-INFO}"
  echo "$LOG_TAG $msg"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "$msg" "$level" 2>/dev/null || true
  fi
}

UPTIME_KUMA_PUSH_URL="${UPTIME_KUMA_PUSH_URL:-}"

echo "$LOG_TAG $(date -Iseconds) Inicio de backup en $(hostname)"

rm -rf "$DUMP_DIR"
mkdir -p "$DUMP_DIR"

# 1. Manifiesto de software
echo "$LOG_TAG Generando manifiesto de software..."
cat > "$DUMP_DIR/server-manifest.txt" <<MANIFEST
# $(hostname) — Software Manifest
# Generado: $(date -Iseconds)

## Runtimes
python:    $(python3 --version 2>&1 || echo "no instalado")
node:      $(node --version 2>&1 || echo "no instalado")
uv:        $(uv --version 2>&1 || echo "no instalado")
docker:    $(docker --version 2>&1 || echo "no instalado")
tailscale: $(tailscale version 2>&1 | head -1 || echo "no instalado")
dagu:      $(dagu version 2>&1 || echo "no instalado")
sqlite3:   $(sqlite3 --version 2>&1 || echo "no instalado")
git:       $(git --version 2>&1 || echo "no instalado")
restic:    $(restic version 2>&1 || echo "no instalado")
claude:    $(claude --version 2>&1 || echo "no instalado")

## ~/.local/bin
$(ls -la ~/.local/bin/ 2>/dev/null || echo "(vacío)")

## Docker — Images
$(docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null || echo "(no disponible)")

## Docker — Containers
$(docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || echo "(no disponible)")

## Docker — Networks
$(docker network ls --format '{{.Name}}\t{{.Driver}}' 2>/dev/null || echo "(no disponible)")

## Systemd user services (habilitados)
$(systemctl --user list-unit-files --state=enabled --no-pager 2>/dev/null || echo "(no disponible)")

## Dagu DAGs
$(ls ~/.config/dagu/dags/*.yaml 2>/dev/null || echo "(sin DAGs)")

## APT repos de terceros
$(ls /etc/apt/sources.list.d/*.list 2>/dev/null || echo "(sin repos externos)")

## Archivos .env (rutas, NO contenido)
$(find ~ -maxdepth 4 -name ".env" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null || echo "(ninguno)")

## Disk usage
$(du -sh ~/ai-lab/ ~/.hermes/ ~/.moolmesh/ ~/.local/bin/ ~/.config/dagu/ 2>/dev/null || true)
MANIFEST
echo "$LOG_TAG Manifiesto generado"

# 2. Paquetes apt + repos de terceros (lección DR: sin repos, dpkg --set-selections falla)
dpkg --get-selections > "$DUMP_DIR/apt-packages.selections"
cp -r /etc/apt/sources.list.d "$DUMP_DIR/apt-sources.list.d" 2>/dev/null || true
cp -r /etc/apt/keyrings "$DUMP_DIR/apt-keyrings" 2>/dev/null || true
echo "$LOG_TAG $(wc -l < "$DUMP_DIR/apt-packages.selections") paquetes apt + repos capturados"

# 3. Dump PostgreSQL (NUNCA usar -t en docker exec — agrega \r que corrompe dumps)
echo "$LOG_TAG Dumping PostgreSQL..."
CONTAINERS_PG=""
for ctr in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -i '\(postgres\|db\)' || true); do
  if docker exec "$ctr" psql --version &>/dev/null 2>&1; then
    DB_USER=$(docker exec "$ctr" bash -c 'echo $POSTGRES_USER' 2>/dev/null || echo "postgres")
    [ -z "$DB_USER" ] && DB_USER="postgres"
    DUMP_NAME=$(echo "$ctr" | tr '/' '-')
    docker exec "$ctr" pg_dumpall -U "$DB_USER" > "$DUMP_DIR/${DUMP_NAME}.sql" || {
      echo "$LOG_TAG WARN: pg_dumpall falló para $ctr"
    }
    # Validar que el dump no tiene \r (causado por docker exec -t)
    if [ -f "$DUMP_DIR/${DUMP_NAME}.sql" ] && grep -cP '\r' "$DUMP_DIR/${DUMP_NAME}.sql" > /dev/null 2>&1; then
      CR_COUNT=$(grep -cP '\r' "$DUMP_DIR/${DUMP_NAME}.sql" 2>/dev/null || echo "0")
      if [ "$CR_COUNT" -gt 0 ]; then
        echo "$LOG_TAG WARN: dump de $ctr contiene \\r — limpiando..."
        sed -i 's/\r$//' "$DUMP_DIR/${DUMP_NAME}.sql"
      fi
    fi
    CONTAINERS_PG="$CONTAINERS_PG $ctr"
  fi
done
echo "$LOG_TAG PostgreSQL dumps:${CONTAINERS_PG:- (ninguno)}"

# 4. Dump SQLite (backup API — seguro para archivos abiertos)
echo "$LOG_TAG Dumping SQLite..."
SQLITE_PATHS=(
  "$HOME/.moolmesh/events.db"
  "$HOME/.local/share/opencode/opencode.db"
)
for db_path in "${SQLITE_PATHS[@]}"; do
  if [ -f "$db_path" ]; then
    db_name=$(basename "$db_path")
    sqlite3 "$db_path" ".backup '$DUMP_DIR/$db_name'" 2>/dev/null || {
      echo "$LOG_TAG WARN: sqlite3 backup falló para $db_path"
    }
  fi
done

# 5. Copiar configs críticos
echo "$LOG_TAG Copiando configs..."
if [ -d "$HOME/.config/systemd/user" ]; then
  cp -r "$HOME/.config/systemd/user" "$DUMP_DIR/systemd-user-services"
fi
if [ -d "$HOME/.config/dagu/dags" ]; then
  cp -r "$HOME/.config/dagu/dags" "$DUMP_DIR/dagu-dags"
fi
cp "$HOME/.gitconfig" "$DUMP_DIR/gitconfig" 2>/dev/null || true

# 6. Capturar Docker networks custom
docker network ls --format '{{.Name}}' 2>/dev/null | grep -v -E '^(bridge|host|none)$' > "$DUMP_DIR/docker-networks.txt" || true

# 7. Restic backup incremental
echo "$LOG_TAG Ejecutando restic backup..."

BACKUP_PATHS=(
  "$LAB_DIR/"
  "$HOME/.hermes/"
  "$HOME/.moolmesh/"
  "$HOME/.local/bin/"
  "$HOME/.ssh/"
  "$HOME/.config/dagu/"
  "$HOME/.config/systemd/user/"
  "$HOME/.gitconfig"
  "$DUMP_DIR"
)

EXISTING_PATHS=()
for p in "${BACKUP_PATHS[@]}"; do
  if [ -e "$p" ]; then
    EXISTING_PATHS+=("$p")
  else
    echo "$LOG_TAG SKIP: $p no existe"
  fi
done

restic backup \
  "${EXISTING_PATHS[@]}" \
  --exclude="**/node_modules" \
  --exclude="**/__pycache__" \
  --exclude="**/.venv" \
  --exclude="**/.git/objects" \
  --exclude="**/logs/*.log" \
  --exclude="**/logs/*.gz" \
  --tag "daily" \
  --tag "automated"

# 8. Verificar integridad (5% aleatorio)
echo "$LOG_TAG Verificando integridad..."
restic check --read-data-subset=5%

# 9. Push heartbeat a Uptime Kuma (si configurado)
if [ -n "$UPTIME_KUMA_PUSH_URL" ]; then
  curl -fsS -m 10 "$UPTIME_KUMA_PUSH_URL" >/dev/null 2>&1 || {
    echo "$LOG_TAG WARN: Push a Uptime Kuma falló"
  }
fi

# 10. Limpiar dumps
rm -rf "$DUMP_DIR"

notify "Backup $(hostname) completado — $(date -Iseconds)" INFO

echo "$LOG_TAG $(date -Iseconds) Backup completado exitosamente"
