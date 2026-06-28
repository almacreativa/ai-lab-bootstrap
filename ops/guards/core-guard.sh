#!/usr/bin/env bash
set -euo pipefail

# core-guard.sh — Audita el core del lab contra core-manifest.yaml
# Verifica que todo lo declarado en el manifiesto siga corriendo.
# Uso: ~/ai-lab/ops/guards/core-guard.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard-lib.sh"

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
MANIFEST="$LAB_DIR/ops/core-manifest.yaml"

guard_init "core"

echo "[core-guard] $(date -Iseconds) Inicio de auditoría"

if [ ! -f "$MANIFEST" ]; then
  echo "[core-guard] ERROR: $MANIFEST no existe. Ejecutar generate-core-manifest.sh primero."
  exit 2
fi

# 1. Verificar binarios
echo "[core-guard] Verificando binarios..."
while IFS= read -r bin_name; do
  [ -z "$bin_name" ] && continue
  bin_name=$(echo "$bin_name" | tr -d '"' | xargs)
  bin_path=$(python3 -c "
import yaml, sys
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
for b in m.get('binaries', []):
    if b['name'] == '$bin_name':
        print(b['path'])
        break
" 2>/dev/null || echo "")

  if [ -z "$bin_path" ]; then
    bin_path="$HOME/.local/bin/$bin_name"
  fi

  if [ -f "$bin_path" ] || [ -L "$bin_path" ]; then
    report_ok "binary" "$bin_name"
  else
    report_gap "binary" "$bin_name" "no encontrado en $bin_path"
  fi
done < <(python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
for b in m.get('binaries', []):
    print(b['name'])
" 2>/dev/null)

# 2. Verificar servicios systemd user
echo "[core-guard] Verificando servicios systemd..."
while IFS= read -r svc_name; do
  [ -z "$svc_name" ] && continue
  svc_name=$(echo "$svc_name" | tr -d '"' | xargs)
  if systemctl --user is-active "$svc_name" &>/dev/null; then
    report_ok "systemd" "$svc_name"
  elif systemctl --user is-enabled "$svc_name" &>/dev/null; then
    report_drift "systemd" "$svc_name" "active" "enabled-but-inactive"
  else
    report_gap "systemd" "$svc_name" "no habilitado ni activo"
  fi
done < <(python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
for s in m.get('services', {}).get('systemd_user', []):
    print(s['name'])
" 2>/dev/null)

# 2b. Verificar servicios systemd system del lab
while IFS= read -r svc_name; do
  [ -z "$svc_name" ] && continue
  svc_name=$(echo "$svc_name" | tr -d '"' | xargs)
  if systemctl is-active "$svc_name" &>/dev/null; then
    report_ok "systemd-system" "$svc_name"
  elif systemctl is-enabled "$svc_name" &>/dev/null; then
    report_drift "systemd-system" "$svc_name" "active" "enabled-but-inactive"
  else
    report_gap "systemd-system" "$svc_name" "no habilitado ni activo"
  fi
done < <(python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
for s in m.get('services', {}).get('systemd_system', []):
    print(s['name'])
" 2>/dev/null)

# 3. Verificar containers Docker
echo "[core-guard] Verificando containers Docker..."
RUNNING_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null || echo "")
while IFS= read -r ctr_name; do
  [ -z "$ctr_name" ] && continue
  ctr_name=$(echo "$ctr_name" | tr -d '"' | xargs)
  if echo "$RUNNING_CONTAINERS" | grep -qx "$ctr_name"; then
    report_ok "container" "$ctr_name"
  elif docker ps -a --format '{{.Names}}' | grep -qx "$ctr_name"; then
    report_drift "container" "$ctr_name" "running" "exited"
  else
    report_gap "container" "$ctr_name" "no existe"
  fi
done < <(python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
for c in m.get('services', {}).get('docker', []):
    print(c['name'])
" 2>/dev/null)

# 4. Verificar redes Docker
echo "[core-guard] Verificando redes Docker..."
EXISTING_NETWORKS=$(docker network ls --format '{{.Name}}' 2>/dev/null || echo "")
while IFS= read -r net_name; do
  [ -z "$net_name" ] && continue
  net_name=$(echo "$net_name" | tr -d '"' | xargs)
  if echo "$EXISTING_NETWORKS" | grep -qx "$net_name"; then
    report_ok "network" "$net_name"
  else
    report_gap "network" "$net_name" "no existe"
  fi
done < <(python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
for n in m.get('networks', []):
    print(n['name'])
" 2>/dev/null)

# 5. Verificar DAGs
echo "[core-guard] Verificando DAGs de Dagu..."
while IFS= read -r dag_name; do
  [ -z "$dag_name" ] && continue
  dag_name=$(echo "$dag_name" | tr -d '"' | xargs)
  if [ -f "$HOME/.config/dagu/dags/$dag_name" ]; then
    report_ok "dag" "$dag_name"
  else
    report_gap "dag" "$dag_name" "no encontrado en dags/"
  fi
done < <(python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
for d in m.get('dags', []):
    print(d)
" 2>/dev/null)

# 6. Verificar backup
echo "[core-guard] Verificando backup..."
if python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
exit(0 if m.get('backup', {}).get('configured') else 1)
" 2>/dev/null; then
  report_ok "backup" "configured"
else
  report_gap "backup" "configured" "backup no configurado"
fi

# Emitir resultados
echo ""
echo "[core-guard] Resultados:"
JSON_FILE=$(emit_json)
emit_telegram
echo "[core-guard] Reporte JSON: $JSON_FILE"

guard_exit_code
