#!/usr/bin/env bash
set -euo pipefail

DUMP_DIR="/tmp/lab-backup-dumps"
LOG_TAG="[lab-backup]"
RESTIC_REPO="b2:lab-backpus"

# Cargar credenciales (B2_ACCOUNT_ID, B2_BACKUP_KEY, RESTIC_PASSWORD)
source ~/ai-lab/scripts/.env

export RESTIC_REPOSITORY="$RESTIC_REPO"
export B2_ACCOUNT_ID
export B2_ACCOUNT_KEY="$B2_BACKUP_KEY"
export RESTIC_PASSWORD

echo "$LOG_TAG $(date -Iseconds) Inicio de backup"

# 1. Preparar directorio de dumps
rm -rf "$DUMP_DIR"
mkdir -p "$DUMP_DIR"

# 2. Generar manifiesto de software
echo "$LOG_TAG Generando manifiesto de software..."
cat > "$DUMP_DIR/server-manifest.txt" <<MANIFEST
# $(hostname) — Software Manifest
# Generado: $(date -Iseconds)
# Este archivo se regenera en cada backup.
# Para comparar con otro snapshot: restic dump <id> .../server-manifest.txt

## Runtimes
python:    $(python3 --version 2>&1)
node:      $(node --version 2>&1)
uv:        $(uv --version 2>&1)
docker:    $(docker --version 2>&1)
tailscale: $(tailscale version 2>&1 | head -1)
opencode:  $(opencode --version 2>&1 || echo "no instalado")
dagu:      $(dagu version 2>&1 || echo "no instalado")
sqlite3:   $(sqlite3 --version 2>&1)
git:       $(git --version 2>&1)
restic:    $(restic version 2>&1)

## ~/.local/bin (binarios instalados manualmente)
$(ls -la ~/.local/bin/ 2>/dev/null || echo "(vacío)")

## Docker — Images
$(docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null || echo "(docker no disponible)")

## Docker — Containers corriendo
$(docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}' 2>/dev/null || echo "(docker no disponible)")

## Snap packages
$(snap list 2>/dev/null || echo "(sin snaps)")

## Node global packages
$(npm -g list --depth=0 2>/dev/null || echo "(sin npm global)")

## Systemd user services (habilitados)
$(systemctl --user list-unit-files --state=enabled --no-pager 2>/dev/null || echo "(no disponible)")

## Dagu DAGs
$(ls ~/.config/dagu/dags/*.yaml 2>/dev/null || echo "(sin DAGs)")

## Archivos .env (rutas, NO contenido)
$(find ~ -maxdepth 4 -name ".env" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null || echo "(ninguno)")

## Disk usage (directorios críticos)
$(du -sh ~/ai-lab/ ~/.hermes/ ~/.moolmesh/ ~/.local/share/opencode/ ~/.config/dagu/ ~/backups/ 2>/dev/null)

## Tailscale network
$(tailscale status 2>/dev/null | head -10 || echo "(tailscale no activo)")
MANIFEST
echo "$LOG_TAG Manifiesto generado: $DUMP_DIR/server-manifest.txt"

# 2b. Capturar paquetes apt (permite reinstalación automática)
dpkg --get-selections > "$DUMP_DIR/apt-packages.selections"
echo "$LOG_TAG $(wc -l < "$DUMP_DIR/apt-packages.selections") paquetes apt capturados"

# 3. Dump PostgreSQL
echo "$LOG_TAG Dumping PostgreSQL..."
docker exec -t paperclip-db-1 pg_dumpall -U paperclip > "$DUMP_DIR/paperclip_all.sql"

# 4. Dump SQLite (backup API seguro)
echo "$LOG_TAG Dumping SQLite..."
sqlite3 ~/.moolmesh/events.db ".backup '$DUMP_DIR/moolmesh_events.db'"
sqlite3 ~/.local/share/opencode/opencode.db ".backup '$DUMP_DIR/opencode.db'"

# 5. Copiar configs críticos
echo "$LOG_TAG Copiando configs..."
cp -r ~/.config/systemd/user "$DUMP_DIR/systemd-user-services"
cp -r ~/.config/dagu/dags "$DUMP_DIR/dagu-dags"

# 6. Restic backup incremental encriptado
echo "$LOG_TAG Ejecutando restic backup..."
restic backup \
  ~/ai-lab/ \
  ~/.hermes/ \
  ~/.moolmesh/ \
  "$DUMP_DIR" \
  --exclude="**/node_modules" \
  --exclude="**/__pycache__" \
  --exclude="**/.venv" \
  --exclude="**/.git/objects" \
  --exclude="**/logs/*.log" \
  --exclude="**/logs/*.gz" \
  --tag "daily" \
  --tag "automated"

# 7. Verificar integridad (subset aleatorio)
echo "$LOG_TAG Verificando integridad..."
restic check --read-data-subset=5%

# 8. Limpiar dumps
rm -rf "$DUMP_DIR"

echo "$LOG_TAG $(date -Iseconds) Backup completado exitosamente"
