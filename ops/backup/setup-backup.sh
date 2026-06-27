#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
ENV_FILE="${LAB_DIR}/scripts/.env"
LOG_TAG="[setup-backup]"

echo "============================================"
echo "  Configuración de backup — restic + B2"
echo "============================================"
echo ""

if [ -f "$ENV_FILE" ] && grep -q "RESTIC_PASSWORD" "$ENV_FILE" 2>/dev/null; then
  echo "$LOG_TAG Ya existe configuración de backup en $ENV_FILE"
  read -r -p "¿Sobreescribir? (s/N): " OVERWRITE
  if [[ ! "$OVERWRITE" =~ ^[sS]$ ]]; then
    echo "$LOG_TAG Manteniendo configuración existente."
    exit 0
  fi
fi

mkdir -p "$(dirname "$ENV_FILE")"

echo ""
echo "Paso 1/4: Credenciales de Backblaze B2"
echo "  Crear un application key en https://secure.backblaze.com/b2_buckets.htm"
echo "  Permisos recomendados: listBuckets, readBuckets, listFiles, readFiles, writeFiles"
echo "  (NO dar deleteFiles — anti-ransomware)"
echo ""

read -r -p "B2_ACCOUNT_ID (keyID): " B2_ACCOUNT_ID
read -r -p "B2_BACKUP_KEY (applicationKey): " B2_BACKUP_KEY
read -r -p "Nombre del bucket B2: " B2_BUCKET

RESTIC_REPOSITORY="b2:${B2_BUCKET}"

echo ""
echo "Paso 2/4: Password de restic"
echo "  Esta contraseña encripta los backups. Guardarla en un password manager."
echo "  Si se pierde, los backups son irrecuperables."
echo ""

read -r -s -p "RESTIC_PASSWORD: " RESTIC_PASSWORD
echo ""
read -r -s -p "Confirmar RESTIC_PASSWORD: " RESTIC_PASSWORD_CONFIRM
echo ""

if [ "$RESTIC_PASSWORD" != "$RESTIC_PASSWORD_CONFIRM" ]; then
  echo "$LOG_TAG ERROR: Las passwords no coinciden."
  exit 1
fi

echo ""
echo "Paso 3/4: Uptime Kuma (opcional)"
echo "  Si tenés Uptime Kuma, configurá un push monitor y pegá la URL aquí."
echo "  Dejá vacío para saltar."
echo ""

read -r -p "UPTIME_KUMA_PUSH_URL (vacío para saltar): " UPTIME_KUMA_PUSH_URL

echo ""
echo "Paso 4/4: Telegram (opcional)"
echo "  Si ya tenés telegram-notify.sh configurado, se usará automáticamente."
echo ""

# Escribir .env (append o crear)
if [ -f "$ENV_FILE" ]; then
  # Limpiar variables de backup existentes
  grep -v -E '^(B2_ACCOUNT_ID|B2_BACKUP_KEY|RESTIC_REPOSITORY|RESTIC_PASSWORD|UPTIME_KUMA_PUSH_URL)=' "$ENV_FILE" > "${ENV_FILE}.tmp" || true
  mv "${ENV_FILE}.tmp" "$ENV_FILE"
fi

cat >> "$ENV_FILE" << EOF

# Backup — restic + B2 (configurado por setup-backup.sh)
B2_ACCOUNT_ID=${B2_ACCOUNT_ID}
B2_BACKUP_KEY=${B2_BACKUP_KEY}
RESTIC_REPOSITORY=${RESTIC_REPOSITORY}
RESTIC_PASSWORD=${RESTIC_PASSWORD}
UPTIME_KUMA_PUSH_URL=${UPTIME_KUMA_PUSH_URL}
EOF

chmod 600 "$ENV_FILE"
echo "$LOG_TAG Credenciales escritas en $ENV_FILE (permisos 600)"

# Inicializar repo restic (si no existe)
echo ""
echo "$LOG_TAG Verificando repo restic..."
export RESTIC_REPOSITORY
export B2_ACCOUNT_ID
export B2_ACCOUNT_KEY="$B2_BACKUP_KEY"
export RESTIC_PASSWORD

if restic snapshots &>/dev/null; then
  echo "$LOG_TAG Repo restic ya existe y es accesible."
  SNAP_COUNT=$(restic snapshots --json 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
  echo "$LOG_TAG Snapshots existentes: $SNAP_COUNT"
else
  echo "$LOG_TAG Inicializando repo restic..."
  if restic init; then
    echo "$LOG_TAG Repo inicializado correctamente."
  else
    echo "$LOG_TAG ERROR: No se pudo inicializar el repo. Verificar credenciales."
    exit 1
  fi
fi

echo ""
echo "============================================"
echo "  Backup configurado exitosamente"
echo "============================================"
echo ""
echo "  Repo:     $RESTIC_REPOSITORY"
echo "  Env:      $ENV_FILE"
echo "  Script:   $LAB_DIR/ops/backup/lab-backup.sh"
echo ""
echo "  Próximos pasos:"
echo "    1. Probar: $LAB_DIR/ops/backup/lab-backup.sh"
echo "    2. Instalar DAG en Dagu para backup diario"
echo "    3. Guardar RESTIC_PASSWORD en password manager"
echo ""
