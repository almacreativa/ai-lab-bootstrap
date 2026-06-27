#!/usr/bin/env bash
set -euo pipefail

# profile-guard.sh — Audita un perfil desplegado contra su profile.yaml
# Verifica que los recursos declarados en el manifiesto del perfil estén activos.
# Uso: ~/ai-lab/ops/guards/profile-guard.sh <nombre-perfil>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard-lib.sh"

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
PROFILES_DIR="${PROFILES_DIR:-$LAB_DIR/repos/lab-profiles}"

PROFILE_NAME="${1:-}"

if [ -z "$PROFILE_NAME" ]; then
  echo "Uso: profile-guard.sh <nombre-perfil>"
  echo "Ejemplo: profile-guard.sh devlab"
  exit 2
fi

guard_init "profile-${PROFILE_NAME}"

PROFILE_YAML="$PROFILES_DIR/${PROFILE_NAME}/profile.yaml"

echo "[profile-guard] $(date -Iseconds) Auditoría del perfil: $PROFILE_NAME"

# Verificar que el perfil existe
if [ ! -f "$PROFILE_YAML" ]; then
  echo "[profile-guard] Perfil $PROFILE_NAME no encontrado en $PROFILES_DIR"
  echo "[profile-guard] Si el perfil no está instalado, esto es esperado."
  # Emitir JSON vacío para registro
  JSON_FILE=$(emit_json)
  echo "[profile-guard] Reporte JSON: $JSON_FILE"
  exit 0
fi

# Verificar que el perfil tiene datos (está instalado)
if [ ! -d "$LAB_DIR/data/profiles/$PROFILE_NAME" ]; then
  echo "[profile-guard] Perfil $PROFILE_NAME tiene profile.yaml pero no tiene data/ — no instalado."
  JSON_FILE=$(emit_json)
  echo "[profile-guard] Reporte JSON: $JSON_FILE"
  exit 0
fi

# 1. Verificar servicios requeridos del core
echo "[profile-guard] Verificando servicios requeridos del core..."
RUNNING_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null || echo "")

python3 -c "
import yaml
with open('$PROFILE_YAML') as f:
    p = yaml.safe_load(f)
for svc in p.get('requires', {}).get('services', []):
    print(svc)
" 2>/dev/null | while read -r svc; do
  [ -z "$svc" ] && continue
  # Buscar como container o como servicio systemd
  if echo "$RUNNING_CONTAINERS" | grep -qi "$svc"; then
    report_ok "core-service" "$svc"
  elif systemctl --user is-active "${svc}.service" &>/dev/null; then
    report_ok "core-service" "$svc"
  elif systemctl is-active "${svc}.service" &>/dev/null 2>&1; then
    report_ok "core-service" "$svc"
  else
    report_gap "core-service" "$svc" "servicio requerido no corriendo"
  fi
done

# 2. Verificar containers del perfil
echo "[profile-guard] Verificando containers del perfil..."
python3 -c "
import yaml
with open('$PROFILE_YAML') as f:
    p = yaml.safe_load(f)
for svc in p.get('containers', {}).get('services', []):
    print(svc)
" 2>/dev/null | while read -r ctr; do
  [ -z "$ctr" ] && continue
  if echo "$RUNNING_CONTAINERS" | grep -qi "$ctr"; then
    report_ok "profile-container" "$ctr"
  else
    report_gap "profile-container" "$ctr" "container del perfil no corriendo"
  fi
done

# 3. Verificar agentes en Paperclip (si hay DB accesible)
echo "[profile-guard] Verificando agentes en Paperclip..."
EXPECTED_COUNT=$(python3 -c "
import yaml
with open('$PROFILE_YAML') as f:
    p = yaml.safe_load(f)
print(p.get('agents', {}).get('count', 0))
" 2>/dev/null || echo "0")

COMPANY_NAME=$(python3 -c "
import yaml
with open('$PROFILE_YAML') as f:
    p = yaml.safe_load(f)
print(p.get('agents', {}).get('company_name', ''))
" 2>/dev/null || echo "")

if [ -n "$COMPANY_NAME" ] && [ "$EXPECTED_COUNT" -gt 0 ] 2>/dev/null; then
  ACTUAL_COUNT=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -t -c \
    "SELECT count(*) FROM agents WHERE company_id IN (SELECT id FROM companies WHERE name ILIKE '%${COMPANY_NAME}%');" \
    2>/dev/null | tr -d ' ' || echo "?")

  if [ "$ACTUAL_COUNT" = "?" ]; then
    report_drift "agents" "$COMPANY_NAME" "$EXPECTED_COUNT" "DB inaccesible"
  elif [ "$ACTUAL_COUNT" -eq "$EXPECTED_COUNT" ] 2>/dev/null; then
    report_ok "agents" "$COMPANY_NAME ($ACTUAL_COUNT/$EXPECTED_COUNT)"
  else
    report_drift "agents" "$COMPANY_NAME" "$EXPECTED_COUNT agentes" "$ACTUAL_COUNT agentes"
  fi
fi

# 4. Verificar DAGs del perfil
echo "[profile-guard] Verificando DAGs del perfil..."
DAG_COUNT=$(python3 -c "
import yaml
with open('$PROFILE_YAML') as f:
    p = yaml.safe_load(f)
print(p.get('dags', {}).get('count', 0))
" 2>/dev/null || echo "0")

DAG_SOURCE=$(python3 -c "
import yaml
with open('$PROFILE_YAML') as f:
    p = yaml.safe_load(f)
print(p.get('dags', {}).get('source', 'dags/'))
" 2>/dev/null || echo "dags/")

if [ "$DAG_COUNT" -gt 0 ] 2>/dev/null; then
  PROFILE_DAGS_DIR="$PROFILES_DIR/${PROFILE_NAME}/${DAG_SOURCE}"
  if [ -d "$PROFILE_DAGS_DIR" ]; then
    for dag in "$PROFILE_DAGS_DIR"/*.yaml; do
      [ -f "$dag" ] || continue
      dagname=$(basename "$dag")
      if [ -f "$HOME/.config/dagu/dags/$dagname" ]; then
        report_ok "dag" "$dagname"
      else
        report_gap "dag" "$dagname" "no instalado en dags/"
      fi
    done
  fi
fi

# Emitir resultados
echo ""
echo "[profile-guard] Resultados para $PROFILE_NAME:"
JSON_FILE=$(emit_json)
emit_telegram
echo "[profile-guard] Reporte JSON: $JSON_FILE"

guard_exit_code
