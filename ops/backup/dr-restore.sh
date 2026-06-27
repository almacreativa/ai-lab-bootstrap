#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
LOG_TAG="[dr-restore]"
RESTORE_TARGET="${1:-$HOME/restore-test}"

echo "============================================"
echo "  DR Restore — restic + B2"
echo "============================================"
echo ""
echo "  Target: $RESTORE_TARGET"
echo ""

# Credenciales
ENV_FILE="${LAB_DIR}/scripts/.env"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "$LOG_TAG No se encontró $ENV_FILE"
  echo "  Proporcionar variables manualmente:"
  read -r -p "  RESTIC_REPOSITORY (ej: b2:mi-bucket): " RESTIC_REPOSITORY
  read -r -p "  B2_ACCOUNT_ID: " B2_ACCOUNT_ID
  read -r -p "  B2_BACKUP_KEY: " B2_BACKUP_KEY
  read -r -s -p "  RESTIC_PASSWORD: " RESTIC_PASSWORD
  echo ""
fi

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
export B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-}"
export B2_ACCOUNT_KEY="${B2_BACKUP_KEY:-}"
export RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"

if [ -z "$RESTIC_REPOSITORY" ] || [ -z "$RESTIC_PASSWORD" ]; then
  echo "$LOG_TAG ERROR: RESTIC_REPOSITORY y RESTIC_PASSWORD son requeridos."
  exit 1
fi

# Listar snapshots
echo "$LOG_TAG Snapshots disponibles:"
restic snapshots --compact
echo ""

# Seleccionar snapshot
read -r -p "Snapshot ID a restaurar (vacío = latest): " SNAP_ID
SNAP_ID="${SNAP_ID:-latest}"

echo ""
echo "$LOG_TAG Restaurando snapshot $SNAP_ID a $RESTORE_TARGET ..."
echo "  IMPORTANTE: esto NO sobreescribe archivos existentes en su ubicación original."
echo "  Se restaura a un directorio temporal para inspección."
echo ""
read -r -p "¿Continuar? (s/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
  echo "$LOG_TAG Cancelado."
  exit 0
fi

mkdir -p "$RESTORE_TARGET"

restic restore "$SNAP_ID" --target "$RESTORE_TARGET"

echo ""
echo "$LOG_TAG Restore completado en $RESTORE_TARGET"
echo ""

# Checklist post-restore
echo "============================================"
echo "  Checklist post-restore"
echo "============================================"
echo ""

DUMP_DIR=$(find "$RESTORE_TARGET" -name "server-manifest.txt" -exec dirname {} \; 2>/dev/null | head -1)

echo "  1. Verificar dumps SQL:"
if [ -n "$DUMP_DIR" ]; then
  for sql in "$DUMP_DIR"/*.sql; do
    [ -f "$sql" ] || continue
    LINES=$(wc -l < "$sql")
    HAS_CR=$(grep -cP '\r' "$sql" 2>/dev/null || echo "0")
    echo "     $(basename "$sql"): ${LINES} líneas, CR chars: ${HAS_CR}"
    if [ "$HAS_CR" -gt 0 ]; then
      echo "     ⚠ ATENCIÓN: dump contaminado con \\r — fue generado con docker exec -t"
    fi
  done
else
  echo "     (no se encontraron dumps)"
fi

echo ""
echo "  2. Verificar configs:"
[ -d "$RESTORE_TARGET$HOME/.config/systemd/user" ] && echo "     ✓ systemd user services" || echo "     ✗ systemd user services"
[ -d "$RESTORE_TARGET$HOME/.config/dagu/dags" ] && echo "     ✓ dagu DAGs" || echo "     ✗ dagu DAGs"
[ -f "$RESTORE_TARGET$HOME/.gitconfig" ] && echo "     ✓ gitconfig" || echo "     ✗ gitconfig"

echo ""
echo "  3. Verificar APT sources:"
if [ -d "$DUMP_DIR/apt-sources.list.d" ]; then
  echo "     $(ls "$DUMP_DIR/apt-sources.list.d/" 2>/dev/null | wc -l) repos de terceros"
else
  echo "     (no encontrados — dpkg --set-selections fallará para paquetes de repos externos)"
fi

echo ""
echo "  4. Docker networks a recrear:"
if [ -f "$DUMP_DIR/docker-networks.txt" ]; then
  while read -r net; do
    echo "     docker network create $net"
  done < "$DUMP_DIR/docker-networks.txt"
else
  echo "     (archivo no encontrado)"
fi

echo ""
echo "  5. ¿Restaurando en la MISMA máquina o en una NUEVA?"
echo ""
echo "     a) MISMA máquina (misma IP, mismo hostname):"
echo "        - Copiar archivos restaurados a sus ubicaciones originales"
echo "        - Recrear Docker networks y levantar stacks"
echo "        - Restaurar dumps PostgreSQL con psql"
echo "        - Correr core-guard.sh para verificar"
echo ""
echo "     b) NUEVA máquina (IP/hostname diferentes):"
echo "        - Primero: correr bootstrap.sh + setup-instance.sh"
echo "        - Copiar configs/stacks/knowledge del restore a ~/ai-lab/"
echo "        - Correr rehome.sh para adaptar IP/hostname automáticamente:"
echo "            bash ~/ai-lab/ops/backup/rehome.sh"
echo "        - Recrear Docker networks y levantar stacks"
echo "        - Restaurar dumps PostgreSQL con psql"
echo "        - Correr core-guard.sh para verificar"
echo ""
echo "  Ver runbook completo: ops/runbooks/dr-test.md"
echo ""
