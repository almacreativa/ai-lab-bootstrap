#!/bin/bash
# ============================================================
# ai-lab-bootstrap — bootstrap-macos.sh
# Levanta un AI agent lab completo en macOS (Sonoma/Sequoia).
#
# Uso:
#   git clone https://github.com/almacreativa/ai-lab-bootstrap.git
#   cd ai-lab-bootstrap
#   bash bootstrap-macos.sh
#
# Variables configurables (se pueden exportar antes de correr
# el script o se piden interactivamente al inicio):
#
#   LAB_USER            usuario del sistema (default: $USER)
#   LAB_DIR             directorio base del lab (default: ~/ai-lab)
#   INSTALL_PAPERCLIP   instalar Paperclip (default: true)
#   INSTALL_HERMES      instalar Hermes Agent (default: true)
#   INSTALL_NLM         instalar notebooklm-mcp-cli (default: true)
#
# Diferencias clave vs. bootstrap.sh (Linux):
#   - Homebrew en vez de apt
#   - Docker Desktop en vez de Docker CE
#   - launchd (LaunchAgent) en vez de systemd para Hermes
#   - nlm login usa navegador real, no requiere Xvfb/CDP tunnel
#   - SSH hardening usa systemsetup + sshd_config (Remote Login)
# ============================================================

set -e

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Este script es solo para macOS. Usa bootstrap.sh en Linux." >&2
  exit 1
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[bootstrap]${NC} $1"; }
warn()    { echo -e "${YELLOW}[warn]${NC} $1"; }
err()     { echo -e "${RED}[error]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}$1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  ██████╗  ██████╗  ██████╗ ████████╗███████╗████████╗██████╗  █████╗ ██████╗"
echo "  ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗"
echo "  ██████╔╝██║   ██║██║   ██║   ██║   ███████╗   ██║   ██████╔╝███████║██████╔╝"
echo "  ██╔══██╗██║   ██║██║   ██║   ██║   ╚════██║   ██║   ██╔══██╗██╔══██║██╔═══╝"
echo "  ██████╔╝╚██████╔╝╚██████╔╝   ██║   ███████║   ██║   ██║  ██║██║  ██║██║"
echo "  ╚═════╝  ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝"
echo "  AI Agent Lab Bootstrap — macOS"
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
read -rp "  ¿Continuar con esta configuración? [S/n] " CONFIRM
CONFIRM="${CONFIRM:-S}"
[[ "$CONFIRM" =~ ^[Ss]$ ]] || { echo "Abortado."; exit 0; }

# Exportar para que los módulos las lean
export LAB_USER LAB_DIR INSTALL_PAPERCLIP INSTALL_HERMES INSTALL_NLM

# ─── Módulos ──────────────────────────────────────────────────
source "$SCRIPT_DIR/modules/macos/01-system.sh"
source "$SCRIPT_DIR/modules/macos/02-node.sh"
source "$SCRIPT_DIR/modules/macos/03-python.sh"
source "$SCRIPT_DIR/modules/macos/04-ai-tools.sh"
source "$SCRIPT_DIR/modules/macos/05-docker-stack.sh"
source "$SCRIPT_DIR/modules/macos/06-post-install.sh"
