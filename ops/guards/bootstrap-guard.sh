#!/usr/bin/env bash
set -euo pipefail

# bootstrap-guard.sh — Audita cobertura del bootstrap
# Compara lo que está instalado en el sistema contra lo que
# ai-lab-bootstrap/modules/*.sh cubre.
# Uso: ~/ai-lab/ops/guards/bootstrap-guard.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard-lib.sh"

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-$LAB_DIR/repos/ai-lab-bootstrap}"

guard_init "bootstrap"

echo "[bootstrap-guard] $(date -Iseconds) Inicio de auditoría"

if [ ! -d "$BOOTSTRAP_DIR/modules" ]; then
  echo "[bootstrap-guard] WARN: $BOOTSTRAP_DIR no encontrado — solo verificando backup coverage."
fi

MODULES_CONTENT=""
if [ -d "$BOOTSTRAP_DIR/modules" ]; then
  MODULES_CONTENT=$(cat "$BOOTSTRAP_DIR/modules"/*.sh 2>/dev/null || echo "")
fi

BACKUP_SCRIPT="$LAB_DIR/ops/backup/lab-backup.sh"
if [ ! -f "$BACKUP_SCRIPT" ]; then
  BACKUP_SCRIPT="$LAB_DIR/scripts/lab-backup.sh"
fi
BACKUP_CONTENT=$(cat "$BACKUP_SCRIPT" 2>/dev/null || echo "")

# 1. Binarios en ~/.local/bin/ — ¿cubiertos por bootstrap o backup?
echo "[bootstrap-guard] Verificando binarios en ~/.local/bin/..."
if [ -d "$HOME/.local/bin" ]; then
  for bin in "$HOME/.local/bin"/*; do
    [ -f "$bin" ] || [ -L "$bin" ] || continue
    name=$(basename "$bin")
    [[ "$name" == *.old* ]] && continue

    in_bootstrap=false
    in_backup=false

    if [ -n "$MODULES_CONTENT" ]; then
      if echo "$MODULES_CONTENT" | grep -qi "$name" 2>/dev/null; then
        in_bootstrap=true
      fi
    fi

    if echo "$BACKUP_CONTENT" | grep -q '\.local/bin' 2>/dev/null; then
      in_backup=true
    fi

    if $in_bootstrap; then
      report_ok "binary" "$name"
    elif $in_backup; then
      report_ok "binary" "$name (backup-only)"
    else
      report_gap "binary" "$name" "no cubierto por bootstrap ni backup"
    fi
  done
fi

# 2. Servicios systemd user — ¿cubiertos?
echo "[bootstrap-guard] Verificando servicios systemd user..."
systemctl --user list-unit-files --state=enabled --type=service --no-pager --no-legend 2>/dev/null | while read -r unit _rest; do
  in_bootstrap=false
  in_backup=false

  if [ -n "$MODULES_CONTENT" ]; then
    svc_base=$(echo "$unit" | sed 's/\.service$//')
    if echo "$MODULES_CONTENT" | grep -qi "$svc_base" 2>/dev/null; then
      in_bootstrap=true
    fi
  fi

  if echo "$BACKUP_CONTENT" | grep -q 'systemd/user' 2>/dev/null; then
    in_backup=true
  fi

  if $in_bootstrap; then
    report_ok "systemd" "$unit"
  elif $in_backup; then
    report_ok "systemd" "$unit (backup-only)"
  else
    report_gap "systemd" "$unit" "no cubierto por bootstrap ni backup"
  fi
done

# 3. Containers Docker — ¿cubiertos por módulo 05 o stacks/?
echo "[bootstrap-guard] Verificando containers Docker..."
docker ps --format '{{.Names}}' 2>/dev/null | while read -r ctr; do
  in_bootstrap=false
  in_stacks=false

  if [ -n "$MODULES_CONTENT" ]; then
    if echo "$MODULES_CONTENT" | grep -qi "$ctr" 2>/dev/null; then
      in_bootstrap=true
    fi
  fi

  # Buscar en stacks/ o repos/ con compose files
  for compose_dir in "$LAB_DIR/stacks"/*/ "$LAB_DIR/repos"/*/; do
    [ -d "$compose_dir" ] || continue
    for cfile in docker-compose.yml compose.yaml docker-compose.yaml; do
      if [ -f "$compose_dir/$cfile" ] && grep -qi "$ctr" "$compose_dir/$cfile" 2>/dev/null; then
        in_stacks=true
        break 2
      fi
    done
  done

  if $in_bootstrap || $in_stacks; then
    report_ok "container" "$ctr"
  else
    report_gap "container" "$ctr" "no cubierto por bootstrap ni stacks/"
  fi
done

# 4. Repos APT de terceros — ¿cubiertos?
echo "[bootstrap-guard] Verificando repos APT de terceros..."
if [ -d /etc/apt/sources.list.d ]; then
  for src in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$src" ] || continue
    name=$(basename "$src")

    in_bootstrap=false
    in_backup=false

    if [ -n "$MODULES_CONTENT" ]; then
      src_base=$(echo "$name" | sed 's/\.\(list\|sources\)$//')
      if echo "$MODULES_CONTENT" | grep -qi "$src_base" 2>/dev/null; then
        in_bootstrap=true
      fi
    fi

    if echo "$BACKUP_CONTENT" | grep -q 'sources.list.d' 2>/dev/null; then
      in_backup=true
    fi

    if $in_bootstrap; then
      report_ok "apt-repo" "$name"
    elif $in_backup; then
      report_ok "apt-repo" "$name (backup-only)"
    else
      report_gap "apt-repo" "$name" "no cubierto por bootstrap ni backup"
    fi
  done
fi

# Emitir resultados
echo ""
echo "[bootstrap-guard] Resultados:"
JSON_FILE=$(emit_json)
emit_telegram
echo "[bootstrap-guard] Reporte JSON: $JSON_FILE"

guard_exit_code
