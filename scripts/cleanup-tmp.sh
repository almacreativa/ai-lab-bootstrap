#!/usr/bin/env bash
# cleanup-tmp.sh — Limpieza segura de /tmp
# Elimina archivos .so y directorios temporales de Node/Python
# MÁS VIEJOS de 60 minutos. Verifica que NO estén en uso con lsof.
#
# Uso: ./cleanup-tmp.sh [--dry-run]
# --dry-run: solo muestra qué se eliminaría, no ejecuta

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

AGE_MINUTES=60
TMP_DIR="/tmp"
LOG_PREFIX="[cleanup-tmp]"

log() {
  echo "$LOG_PREFIX $1"
}

# ── 1. Limpiar archivos .so en /tmp más viejos de AGE_MINUTES ──
log "Buscando archivos .so en $TMP_DIR con >${AGE_MINUTES}min de antigüedad..."

SO_FILES=()
while IFS= read -r -d '' file; do
  SO_FILES+=("$file")
done < <(find "$TMP_DIR" -maxdepth 2 -name '*.so' -type f -mmin +"$AGE_MINUTES" -print0 2>/dev/null)

if [[ ${#SO_FILES[@]} -eq 0 ]]; then
  log "No hay archivos .so viejos para limpiar."
else
  log "Encontrados ${#SO_FILES[@]} archivo(s) .so viejo(s)."
  for f in "${SO_FILES[@]}"; do
    # Verificar que no esté en uso
    if lsof "$f" >/dev/null 2>&1; then
      log "  SKIP (en uso): $f"
      continue
    fi
    if [[ "$DRY_RUN" == true ]]; then
      log "  DRY-RUN: eliminaría $f"
    else
      rm -f "$f" 2>/dev/null && log "  OK: eliminado $f" || log "  FAIL: no se pudo eliminar $f"
    fi
  done
fi

# ── 2. Limpiar directorios temporales de Node (node_modules/.cache, .tmp) ──
log "Buscando directorios .tmp/.cache de Node/Python en /tmp..."

while IFS= read -r -d '' dir; do
  # Verificar que no esté montado ni en uso
  if mountpoint -q "$dir" 2>/dev/null; then
    log "  SKIP (punto de montaje): $dir"
    continue
  fi
  if lsof +D "$dir" >/dev/null 2>&1; then
    log "  SKIP (en uso): $dir"
    continue
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log "  DRY-RUN: eliminaría directorio $dir"
  else
    rm -rf "$dir" 2>/dev/null && log "  OK: eliminado $dir" || log "  FAIL: no se pudo eliminar $dir"
  fi
done < <(find "$TMP_DIR" -maxdepth 3 -type d \( -name '.tmp' -o -name '.cache' -o -name 'node_modules' \) -mtime +0 -print0 2>/dev/null)

# ── 3. Limpiar archivos temporales de Node/Python en /tmp ──
log "Buscando archivos temporales de Node/Python en /tmp..."

while IFS= read -r -d '' file; do
  if lsof "$file" >/dev/null 2>&1; then
    log "  SKIP (en uso): $file"
    continue
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log "  DRY-RUN: eliminaría $file"
  else
    rm -f "$file" 2>/dev/null && log "  OK: eliminado $file" || log "  FAIL: no se pudo eliminar $file"
  fi
done < <(find "$TMP_DIR" -maxdepth 2 -type f \( -name '*.tmp' -o -name 'node_*.tmp' -o -name 'python_*.tmp' -o -name 'pip-*' -o -name 'npm-*' \) -mmin +"$AGE_MINUTES" -print0 2>/dev/null)

# ── 4. Limpiar archivos .so que queden en subdirectorios de /tmp (ej: /tmp/opencode-xxx/) ──
log "Buscando subdirectorios de /tmp con archivos .so viejos..."

# Excluir directorios gestionados por el sistema (systemd-private, snap, tmux, etc.)
EXCLUDE_PATTERNS='systemd-private|snap-private-tmp|tmux-|pulse-|gdm-|lightdm-'

while IFS= read -r -d '' subdir; do
  # Excluir directorios del sistema
  if echo "$subdir" | grep -Eq "$EXCLUDE_PATTERNS"; then
    log "  SKIP (sistema): $subdir"
    continue
  fi
  # Solo procesar directorios creados hace más de 60 min
  if [[ "$(find "$subdir" -maxdepth 1 -mmin +"$AGE_MINUTES" -print -quit 2>/dev/null)" == "$subdir" ]]; then
    # Verificar que el directorio no tenga archivos en uso
    if lsof +D "$subdir" >/dev/null 2>&1; then
      log "  SKIP (en uso): $subdir"
      continue
    fi
    if [[ "$DRY_RUN" == true ]]; then
      log "  DRY-RUN: eliminaría directorio $subdir (contiene .so viejos)"
    else
      # Solo eliminar si contiene .so
      if find "$subdir" -name '*.so' -type f 2>/dev/null | grep -q .; then
        rm -rf "$subdir" 2>/dev/null && log "  OK: eliminado directorio $subdir" || log "  FAIL: no se pudo eliminar $subdir"
      else
        log "  SKIP (sin .so): $subdir"
      fi
    fi
  fi
done < <(find "$TMP_DIR" -maxdepth 1 -type d -not -path "$TMP_DIR" -print0 2>/dev/null)

log "Limpieza completada."
