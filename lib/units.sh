#!/bin/bash
# units.sh — helpers de selección y estado para la instalación modular.
# Requiere: log()/warn() ya definidos por bootstrap.sh y LAB_UNITS ya sourceado
# desde registry.sh. Se sourcea DESPUÉS de ambos.
#
# Variables que setea bootstrap.sh según los flags:
#   SELECTED_UNITS  (array de ids activos)  — resuelto en bootstrap.sh
#   UNTIL_STAGE     (ej. "03" o "" = sin límite)
#   RESUME_MODE     (true/false)

STATE_DIR="$HOME/.ai-lab/state"
STATE_FILE="$STATE_DIR/bootstrap.tsv"
mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

# _unit_field <id> <n-campo 1..6> — imprime el campo n de la línea del registro.
_unit_field() {
  local id="$1" n="$2" line
  for line in "${LAB_UNITS[@]}"; do
    [ "${line%%|*}" = "$id" ] && { echo "$line" | cut -d'|' -f"$n"; return 0; }
  done
  return 1
}

is_obligatoria() { [ "$(_unit_field "$1" 4)" = "si" ]; }
unit_stage()     { _unit_field "$1" 2; }
unit_deps()      { _unit_field "$1" 5; }
unit_desc()      { _unit_field "$1" 6; }
unit_default()   { _unit_field "$1" 3; }

is_done()   { grep -qx "$1" "$STATE_FILE" 2>/dev/null; }
mark_done() { is_done "$1" || echo "$1" >> "$STATE_FILE"; }

# is_selected <id> — true si el id está en SELECTED_UNITS o es obligatoria.
is_selected() {
  local id="$1" u
  is_obligatoria "$id" && return 0
  for u in "${SELECTED_UNITS[@]}"; do [ "$u" = "$id" ] && return 0; done
  return 1
}

# should_install <id> — decisión final. Usar SIEMPRE como: if should_install x; then ...; fi
# (nunca suelto: con set -e un return 1 abortaría el script).
should_install() {
  local id="$1"
  is_selected "$id" || return 1
  # límite de etapa (--until): comparación lexicográfica, requiere stages de 2 dígitos.
  if [ -n "${UNTIL_STAGE:-}" ]; then
    [ "$(unit_stage "$id")" \> "$UNTIL_STAGE" ] && return 1
  fi
  # resume: saltar lo ya hecho.
  if [ "${RESUME_MODE:-false}" = "true" ] && is_done "$id"; then
    log "[resume] $id ya hecho — saltando."
    return 1
  fi
  return 0
}

# remove_unit <id> — saca un id de SELECTED_UNITS (retrocompat de flags viejos).
remove_unit() {
  local drop="$1" u _tmp=()
  for u in "${SELECTED_UNITS[@]}"; do
    [ "$u" = "$drop" ] || _tmp+=("$u")
  done
  SELECTED_UNITS=("${_tmp[@]}")
}
