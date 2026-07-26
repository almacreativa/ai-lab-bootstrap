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
# Honra el campo `status` del manifest: un servicio declarado "inactive"
# (oneshot de boot, etc.) es correcto si está inactivo; solo drift si está 'failed'.
echo "[core-guard] Verificando servicios systemd..."
while IFS=$'\t' read -r svc_name svc_status; do
  [ -z "$svc_name" ] && continue
  svc_name=$(echo "$svc_name" | tr -d '"' | xargs)
  [ -z "$svc_status" ] && svc_status="active"
  if [ "$svc_status" = "inactive" ]; then
    if systemctl --user is-failed "$svc_name" &>/dev/null; then
      report_drift "systemd" "$svc_name" "inactive" "failed"
    else
      report_ok "systemd" "$svc_name"
    fi
  elif systemctl --user is-active "$svc_name" &>/dev/null; then
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
    print(f\"{s['name']}\t{s.get('status','active')}\")
" 2>/dev/null)

# 2b. Verificar servicios systemd system del lab
while IFS=$'\t' read -r svc_name svc_status; do
  [ -z "$svc_name" ] && continue
  svc_name=$(echo "$svc_name" | tr -d '"' | xargs)
  [ -z "$svc_status" ] && svc_status="active"
  if [ "$svc_status" = "inactive" ]; then
    if systemctl is-failed "$svc_name" &>/dev/null; then
      report_drift "systemd-system" "$svc_name" "inactive" "failed"
    else
      report_ok "systemd-system" "$svc_name"
    fi
  elif systemctl is-active "$svc_name" &>/dev/null; then
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
    print(f\"{s['name']}\t{s.get('status','active')}\")
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

# 7. Verificar copias de scripts en ~/.hermes/scripts/ (Hermes no acepta
# symlinks — los crons ejecutan copias físicas que pueden divergir del canónico)
echo "[core-guard] Verificando copias de scripts de Hermes..."
if [ -d "$HOME/.hermes/scripts" ]; then
  for copia in "$HOME/.hermes/scripts"/*.sh; do
    [ -e "$copia" ] || continue
    nombre=$(basename "$copia")
    canonico="$LAB_DIR/scripts/$nombre"
    if [ ! -f "$canonico" ]; then
      report_gap "hermes-script" "$nombre" "copia en ~/.hermes/scripts/ sin canónico en scripts/"
    elif [ "$(sha256sum "$copia" | cut -d' ' -f1)" = "$(sha256sum "$canonico" | cut -d' ' -f1)" ]; then
      report_ok "hermes-script" "$nombre"
    else
      report_drift "hermes-script" "$nombre" "hash igual al canónico" "divergente — cp $canonico ~/.hermes/scripts/"
    fi
  done
fi

# 8. Verificar crons de Hermes contra jobs.json
echo "[core-guard] Verificando crons de Hermes..."
while IFS=$'\t' read -r cron_name cron_enabled; do
  [ -z "$cron_name" ] && continue
  estado=$(python3 -c "
import json
try:
    jobs = json.load(open('$HOME/.hermes/cron/jobs.json')).get('jobs', [])
except Exception:
    print('no-jobs-file'); raise SystemExit
for j in jobs:
    if j.get('name') == '''$cron_name''':
        print('enabled' if j.get('enabled') else 'disabled')
        break
else:
    print('missing')
" 2>/dev/null || echo "error")
  case "$estado" in
    enabled)  report_ok "hermes-cron" "$cron_name" ;;
    disabled)
      if [ "$cron_enabled" = "True" ]; then
        report_drift "hermes-cron" "$cron_name" "enabled" "deshabilitado"
      else
        report_ok "hermes-cron" "$cron_name"
      fi ;;
    missing)  report_gap "hermes-cron" "$cron_name" "ya no existe en jobs.json" ;;
    *)        report_gap "hermes-cron" "$cron_name" "no se pudo leer jobs.json" ;;
  esac
done < <(python3 -c "
import yaml
m = yaml.safe_load(open('$MANIFEST'))
for c in m.get('hermes_crons') or []:
    print(f\"{c['name']}\t{c.get('enabled')}\")
" 2>/dev/null)

# 9. Verificar MCPs configurados (rutas de scripts/binarios válidas)
echo "[core-guard] Verificando MCPs configurados..."
while IFS=$'\t' read -r mcp_scope mcp_name mcp_cmd; do
  [ -z "$mcp_name" ] && continue
  ok=true
  for token in $mcp_cmd; do
    case "$token" in
      /*)  [ -e "$token" ] || ok=false ;;
      *.sh|*.py)
        [ -e "$token" ] || [ -e "$HOME/ai-lab/scripts/$token" ] || ok=false ;;
    esac
  done
  # El comando base debe existir (binario en PATH o ruta)
  base=$(echo "$mcp_cmd" | awk '{print $1}')
  if [ -n "$base" ] && [[ "$base" != /* ]]; then
    command -v "$base" >/dev/null 2>&1 || ok=false
  fi
  if $ok; then
    report_ok "mcp" "$mcp_scope/$mcp_name"
  else
    report_gap "mcp" "$mcp_scope/$mcp_name" "comando o ruta inválida: $mcp_cmd"
  fi
done < <(python3 -c "
import yaml
m = yaml.safe_load(open('$MANIFEST'))
for scope, entries in (m.get('mcps') or {}).items():
    for e in entries or []:
        print(f\"{scope}\t{e['name']}\t{e.get('command','')}\")
" 2>/dev/null)

# 10. Detectar scripts huérfanos (sin ningún consumidor conocido)
echo "[core-guard] Verificando scripts huérfanos..."
while IFS=$'\t' read -r script_name n_consumers; do
  [ -z "$script_name" ] && continue
  if [ "$n_consumers" = "0" ]; then
    report_drift "script" "$script_name" "con consumidor" "huérfano — ningún DAG/cron/servicio lo ejecuta"
  else
    report_ok "script" "$script_name"
  fi
done < <(python3 -c "
import yaml
m = yaml.safe_load(open('$MANIFEST'))
for s in m.get('scripts') or []:
    print(f\"{s['name']}\t{len(s.get('consumers') or [])}\")
" 2>/dev/null)

# 11. Detectar conflictos de Syncthing en las carpetas sincronizadas
# Los .sync-conflict-* silenciosos son la forma en que el hub se degrada
# sin que nadie lo note (plan integración conocimientos §5.4).
echo "[core-guard] Verificando conflictos de Syncthing..."
for sync_dir in "$HOME/ai-lab/knowledge" "$HOME/ai-lab/ops" "$HOME/shared/demos"; do
  [ -d "$sync_dir" ] || continue
  etiqueta=$(basename "$sync_dir")
  conflictos=$(find "$sync_dir" -name "*.sync-conflict-*" -not -path "*/.stversions/*" 2>/dev/null | head -5)
  if [ -z "$conflictos" ]; then
    report_ok "sync-conflict" "$etiqueta"
  else
    n=$(echo "$conflictos" | wc -l)
    primero=$(echo "$conflictos" | head -1 | sed "s|$HOME/||")
    report_gap "sync-conflict" "$etiqueta" "$n conflicto(s) — ej: $primero — resolver y borrar"
  fi
done

# 12. Notificaciones Telegram centralizadas
# Regla: NADIE llama a la API de Telegram directamente salvo telegram-notify.sh
# (que tiene fallback Markdown→plano y exit code real). Un curl directo con
# parse_mode puede perder avisos en silencio — bug detectado 2026-07-09.
# El patrón exige la URL completa (https://) para no matchear menciones en comentarios.
echo "[core-guard] Verificando centralización de notificaciones Telegram..."
BYPASSERS=$(grep -rl "https://api\.telegram\.org" \
  "$HOME/ai-lab/scripts" "$HOME/ai-lab/ops" "$HOME/.hermes/scripts" \
  "$HOME/.config/dagu/dags" 2>/dev/null | grep -v "telegram-notify.sh" || true)
if [ -z "$BYPASSERS" ]; then
  report_ok "telegram" "centralizado"
else
  for b in $BYPASSERS; do
    report_drift "telegram" "$(basename "$b")" "via telegram-notify.sh" "curl directo a api.telegram.org — riesgo de aviso perdido"
  done
fi

# Emitir resultados
echo ""
echo "[core-guard] Resultados:"
JSON_FILE=$(emit_json)
emit_telegram
echo "[core-guard] Reporte JSON: $JSON_FILE"

guard_exit_code
