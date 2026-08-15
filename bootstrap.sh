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
#   --skip a,b     todo default menos esas
#   --interactive  preguntar herramienta por herramienta
#   --until NN     cortar tras la etapa NN (01..05); reanudable luego
#   --resume       saltar unidades ya marcadas en el state file
#   --list         resolver y mostrar SELECTED_UNITS sin instalar nada (sale 0)
INTERACTIVE=false
RESUME_MODE=false
UNTIL_STAGE=""
ONLY_LIST=""
SKIP_LIST=""
ONLY_LISTING=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive) INTERACTIVE=true; shift ;;
    --resume)      RESUME_MODE=true; shift ;;
    --until)       UNTIL_STAGE="$2"; shift 2 ;;
    --only)        ONLY_LIST="$2"; shift 2 ;;
    --skip)        SKIP_LIST="$2"; shift 2 ;;
    --list)        ONLY_LISTING=true; shift ;;
    -h|--help)
      echo "Uso: bash bootstrap.sh [--only a,b] [--skip a,b] [--interactive] [--until NN] [--resume] [--list]"
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
echo "  Instalar Paperclip  : $INSTALL_PAPERCLIP"
echo "  Instalar Hermes     : $INSTALL_HERMES"
echo "  Instalar nlm        : $INSTALL_NLM"
echo ""

# ─── Resolución de unidades a instalar ────────────────────────
# El registro (lib/registry.sh) es la ÚNICA fuente de verdad de qué existe.
# lib/units.sh aporta los helpers should_install/mark_done/is_done. Se sourcean
# DESPUÉS de que log()/warn() estén definidos. Los módulos se siguen sourceando
# (mismo proceso), por eso SELECTED_UNITS/LAB_UNITS quedan visibles sin export.
source "$SCRIPT_DIR/lib/registry.sh"
source "$SCRIPT_DIR/lib/units.sh"

SELECTED_UNITS=()
if [ -n "$ONLY_LIST" ]; then
  IFS=',' read -ra SELECTED_UNITS <<< "$ONLY_LIST" || true
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

# modo interactivo: preguntar por unidad (las obligatorias van sí o sí)
if [ "$INTERACTIVE" = true ]; then
  _sel=()
  for line in "${LAB_UNITS[@]}"; do
    id="${line%%|*}"; desc="$(echo "$line"|cut -d'|' -f6)"
    if [ "$(echo "$line"|cut -d'|' -f4)" = "si" ]; then _sel+=("$id"); continue; fi
    read -rp "  ¿Instalar $id ($desc)? [S/n] " r; r="${r:-S}"
    [[ "$r" =~ ^[Ss]$ ]] && _sel+=("$id")
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

# ─── Módulos ──────────────────────────────────────────────────
source "$SCRIPT_DIR/modules/01-system.sh"
source "$SCRIPT_DIR/modules/02-node.sh"
source "$SCRIPT_DIR/modules/03-python.sh"
source "$SCRIPT_DIR/modules/04-ai-tools.sh"
source "$SCRIPT_DIR/modules/05-docker-stack.sh"
source "$SCRIPT_DIR/modules/06-post-install.sh"
