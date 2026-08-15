#!/bin/bash
# ============================================================
# ai-lab-bootstrap — bootstrap.sh
# Levanta un AI agent lab completo en Ubuntu Server 24.04.
#
# Uso:
#   git clone https://github.com/almacreativa/ai-lab-bootstrap.git
#   cd ai-lab-bootstrap
#   bash bootstrap.sh
#
# Variables configurables (se pueden exportar antes de correr
# el script o se piden interactivamente al inicio):
#
#   LAB_USER            usuario del sistema (default: $USER)
#   LAB_DIR             directorio base del lab (default: ~/ai-lab)
#   INSTALL_PAPERCLIP   instalar Paperclip (default: true)
#   INSTALL_HERMES      instalar Hermes Agent (default: true)
#   INSTALL_NLM         instalar notebooklm-mcp-cli (default: true)
# ============================================================

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[bootstrap]${NC} $1"; }
warn()    { echo -e "${YELLOW}[warn]${NC} $1"; }
err()     { echo -e "${RED}[error]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}$1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Flags de instalación modular ─────────────────────────────
# Todos opcionales. Sin flags = comportamiento default idéntico al histórico
# (todas las unidades default=on, un solo confirm, sin prompts por-herramienta).
#   --only a,b,c   instalar solo esas unidades (+ deps)
#   --layer a,b    instalar esas capas (builder/operator/explorer/addons) (+ base y deps)
#   --skip a,b     todo default menos esas
#   --interactive  preguntar herramienta por herramienta (agrupado por capa)
#   --until NN     cortar tras la etapa NN (01..05); reanudable luego
#   --resume       saltar unidades ya marcadas en el state file
#   --list         resolver y mostrar SELECTED_UNITS sin instalar nada (sale 0)
INTERACTIVE=false
RESUME_MODE=false
UNTIL_STAGE=""
ONLY_LIST=""
LAYER_LIST=""
SKIP_LIST=""
ONLY_LISTING=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive) INTERACTIVE=true; shift ;;
    --resume)      RESUME_MODE=true; shift ;;
    --until)       UNTIL_STAGE="$2"; shift 2 ;;
    --only)        ONLY_LIST="$2"; shift 2 ;;
    --layer)       LAYER_LIST="$2"; shift 2 ;;
    --skip)        SKIP_LIST="$2"; shift 2 ;;
    --list)        ONLY_LISTING=true; shift ;;
    -h|--help)
      echo "Uso: bash bootstrap.sh [--only a,b] [--layer a,b] [--skip a,b] [--interactive] [--until NN] [--resume] [--list]"
      echo "Capas válidas para --layer: builder, operator, explorer, addons"
      exit 0 ;;
    *) shift ;;  # ignorar desconocidos
  esac
done
export RESUME_MODE UNTIL_STAGE

echo ""
echo "  ██████╗  ██████╗  ██████╗ ████████╗███████╗████████╗██████╗  █████╗ ██████╗"
echo "  ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗"
echo "  ██████╔╝██║   ██║██║   ██║   ██║   ███████╗   ██║   ██████╔╝███████║██████╔╝"
echo "  ██╔══██╗██║   ██║██║   ██║   ██║   ╚════██║   ██║   ██╔══██╗██╔══██║██╔═══╝"
echo "  ██████╔╝╚██████╔╝╚██████╔╝   ██║   ███████║   ██║   ██║  ██║██║  ██║██║"
echo "  ╚═════╝  ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝"
echo "  AI Agent Lab Bootstrap — Ubuntu Server 24.04"
echo ""

# ─── Configuración ────────────────────────────────────────────
section "── Configuración ──"
echo ""

LAB_USER="${LAB_USER:-$USER}"
LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
INSTALL_PAPERCLIP="${INSTALL_PAPERCLIP:-true}"
INSTALL_HERMES="${INSTALL_HERMES:-true}"
INSTALL_NLM="${INSTALL_NLM:-true}"

echo "  Usuario del sistema : $LAB_USER"
echo "  Directorio del lab  : $LAB_DIR"
# Las unidades resueltas se muestran más abajo ("Unidades a instalar"), una vez
# que SELECTED_UNITS está calculado. No imprimir aquí los flags viejos
# (INSTALL_PAPERCLIP/HERMES/NLM): solo se conservan por retrocompat.
echo ""

# ─── Resolución de unidades a instalar ────────────────────────
# El registro (lib/registry.sh) es la ÚNICA fuente de verdad de qué existe.
# lib/units.sh aporta los helpers should_install/mark_done/is_done. Se sourcean
# DESPUÉS de que log()/warn() estén definidos. Los módulos se siguen sourceando
# (mismo proceso), por eso SELECTED_UNITS/LAB_UNITS quedan visibles sin export.
source "$SCRIPT_DIR/lib/registry.sh"
source "$SCRIPT_DIR/lib/units.sh"

SELECTED_UNITS=()
if [ -n "$ONLY_LIST" ] || [ -n "$LAYER_LIST" ]; then
  # --only: ids explícitos, tal cual (respetan lo pedido aunque sean default=off).
  if [ -n "$ONLY_LIST" ]; then
    IFS=',' read -ra _only <<< "$ONLY_LIST" || true
    for u in "${_only[@]}"; do
      [ -z "$u" ] && continue
      is_selected "$u" || SELECTED_UNITS+=("$u")
    done
  fi
  # --layer: expandir cada capa a sus unidades default=on (unión con --only).
  # Una capa NO arrastra unidades default=off (ej. odysseus): esas se piden por --only.
  if [ -n "$LAYER_LIST" ]; then
    IFS=',' read -ra _layers <<< "$LAYER_LIST" || true
    for lay in "${_layers[@]}"; do
      [ -z "$lay" ] && continue
      _ids="$(layer_units "$lay")"
      if [ -z "$_ids" ]; then warn "capa desconocida '$lay' — ignorada (válidas: builder, operator, explorer, addons)."; continue; fi
      while IFS= read -r lid; do
        [ -z "$lid" ] && continue
        [ "$(unit_default "$lid")" = "on" ] || continue
        is_selected "$lid" || SELECTED_UNITS+=("$lid")
      done <<< "$_ids"
    done
  fi
else
  # default: todas las unidades con default=on
  for line in "${LAB_UNITS[@]}"; do
    id="${line%%|*}"; def="$(echo "$line" | cut -d'|' -f3)"
    [ "$def" = "on" ] && SELECTED_UNITS+=("$id")
  done
fi

# aplicar --skip
if [ -n "$SKIP_LIST" ]; then
  IFS=',' read -ra _skip <<< "$SKIP_LIST" || true
  for s in "${_skip[@]}"; do remove_unit "$s"; done
fi

# modo interactivo: preguntar por unidad, agrupado por capa (encabezados cosméticos).
# El orden real de instalación lo sigue mandando el source de módulos por etapa.
# Las obligatorias (docker/node/uv) se auto-seleccionan sin preguntar.
if [ "$INTERACTIVE" = true ]; then
  _sel=()
  for lay in builder operator explorer addons; do
    echo ""
    section "── ${lay^^} ──"
    # Juntar los ids de la capa PRIMERO (el read -rp de abajo usa stdin real; si
    # se leyera la lista por herestring, ambos reads competirían por el mismo fd).
    _layer_ids=()
    while IFS= read -r lid; do [ -n "$lid" ] && _layer_ids+=("$lid"); done <<< "$(layer_units "$lay")"
    for lid in "${_layer_ids[@]}"; do
      desc="$(unit_desc "$lid")"
      if is_obligatoria "$lid"; then
        echo "  $lid ($desc) [base, siempre]"
        _sel+=("$lid"); continue
      fi
      read -rp "  ¿Instalar $lid ($desc)? [S/n] " r; r="${r:-S}"
      [[ "$r" =~ ^[Ss]$ ]] && _sel+=("$lid")
    done
  done
  SELECTED_UNITS=("${_sel[@]}")
fi

# Retrocompat de flags viejos (INSTALL_HERMES/PAPERCLIP/NLM): alias a ids.
[ "${INSTALL_HERMES:-true}" = "false" ]    && remove_unit "hermes"
[ "${INSTALL_PAPERCLIP:-true}" = "false" ] && remove_unit "paperclip"
[ "${INSTALL_NLM:-true}" = "false" ]       && remove_unit "nlm"

# resolver deps (auto-incluir prereqs faltantes de lo seleccionado)
for line in "${LAB_UNITS[@]}"; do
  id="${line%%|*}"
  is_selected "$id" || continue
  deps="$(echo "$line"|cut -d'|' -f5)"
  [ -z "$deps" ] && continue
  IFS=',' read -ra _d <<< "$deps" || true
  for dep in "${_d[@]}"; do
    is_selected "$dep" || { SELECTED_UNITS+=("$dep"); warn "auto-incluyo dep '$dep' requerida por '$id'."; }
  done
done

# --list: mostrar qué unidades correría (aplicando el mismo gating que should_install:
# selección + --until + --resume) en orden de etapa, y salir SIN instalar nada.
if [ "$ONLY_LISTING" = true ]; then
  _out=()
  for line in "${LAB_UNITS[@]}"; do
    id="${line%%|*}"
    is_selected "$id" || continue
    if [ -n "${UNTIL_STAGE:-}" ] && [ "$(unit_stage "$id")" \> "$UNTIL_STAGE" ]; then continue; fi
    if [ "${RESUME_MODE:-false}" = "true" ] && is_done "$id"; then continue; fi
    _out+=("$id")
  done
  echo "${_out[*]}"
  exit 0
fi

echo "  Unidades a instalar : ${SELECTED_UNITS[*]}"
echo ""
read -rp "  ¿Continuar con esta configuración? [S/n] " CONFIRM
CONFIRM="${CONFIRM:-S}"
[[ "$CONFIRM" =~ ^[Ss]$ ]] || { echo "Abortado."; exit 0; }

# Exportar para que los módulos las lean
export LAB_USER LAB_DIR INSTALL_PAPERCLIP INSTALL_HERMES INSTALL_NLM

# ─── Barrera de etapa (--until / --resume a nivel de módulo) ──────
# should_run_stage NN — decide si se debe SOURCEAR el módulo de la etapa NN.
# Sin esta barrera, --until solo filtraba unidades DENTRO de should_install pero
# igual sourceaba los 6 módulos (rehaciendo trabajo estructural: mkdir, redes,
# scaffolding). Con la barrera + mark_stage_done, --until corta de verdad y
# --resume saltea las etapas ya completadas (reanudación real).
# Usar SIEMPRE como: if should_run_stage NN; then ...; fi  (nunca suelto: con
# set -e un return 1 abortaría el script).
should_run_stage() {
  local st="$1"
  if [ -n "${UNTIL_STAGE:-}" ] && [ "$st" \> "$UNTIL_STAGE" ]; then
    log "[until] etapa $st fuera de rango ($UNTIL_STAGE) — omitida"; return 1
  fi
  if [ "${RESUME_MODE:-false}" = "true" ] && is_stage_done "$st"; then
    log "[resume] etapa $st ya completada — omitida"; return 1
  fi
  return 0
}

# ─── Módulos ──────────────────────────────────────────────────
# El source queda a nivel TOP-LEVEL a propósito (NO envolver en una función que
# haga el source adentro): en bash, source dentro de una función mete las
# asignaciones de variables NO exportadas en el scope local de esa función, y los
# módulos posteriores dejarían de ver el estado que esperan. Las definiciones de
# funciones sí serían globales, pero las variables no. Mantener el patrón literal
# if should_run_stage NN; then source ...; mark_stage_done NN; fi.
# La etapa se marca SOLO si el source completó (con set -e, un corte a mitad de
# módulo aborta antes del mark_stage_done → al reanudar re-corre esa etapa, y
# adentro should_install/is_done + guards de idempotencia saltan lo ya hecho).
if should_run_stage 01; then source "$SCRIPT_DIR/modules/01-system.sh";      mark_stage_done 01; fi
if should_run_stage 02; then source "$SCRIPT_DIR/modules/02-node.sh";        mark_stage_done 02; fi
if should_run_stage 03; then source "$SCRIPT_DIR/modules/03-python.sh";      mark_stage_done 03; fi
if should_run_stage 04; then source "$SCRIPT_DIR/modules/04-ai-tools.sh";    mark_stage_done 04; fi
if should_run_stage 05; then source "$SCRIPT_DIR/modules/05-docker-stack.sh"; mark_stage_done 05; fi
if should_run_stage 06; then source "$SCRIPT_DIR/modules/06-post-install.sh"; mark_stage_done 06; fi
