#!/usr/bin/env bash
set -euo pipefail

# lab-cleanup.sh — Limpia un servidor de lab, dejando solo Ubuntu + Tailscale + SSH
#
# Uso:
#   lab-cleanup.sh              # muestra qué haría (dry-run por defecto)
#   lab-cleanup.sh --confirm    # ejecuta la limpieza

LOG_TAG="[lab-cleanup]"
CONFIRM=false
[ "${1:-}" = "--confirm" ] && CONFIRM=true

log()  { echo "$LOG_TAG $*"; }
warn() { echo "$LOG_TAG ⚠ $*"; }
run()  {
  if [ "$CONFIRM" = true ]; then
    eval "$@"
  else
    echo "  [dry-run] $*"
  fi
}

echo "============================================"
echo "  Lab Cleanup"
echo "============================================"
echo ""

if [ "$CONFIRM" != true ]; then
  echo "  MODO DRY-RUN — nada se modifica."
  echo "  Usar --confirm para ejecutar."
  echo ""
fi

# 1. Parar servicios systemd user
log "1/7 — Servicios systemd user"
for svc in dagu moolmesh centro-de-comando hermes; do
  if systemctl --user is-active "$svc" &>/dev/null 2>&1; then
    log "  Parando $svc..."
    run "systemctl --user stop $svc 2>/dev/null || true"
    run "systemctl --user disable $svc 2>/dev/null || true"
  fi
done

# 2. Parar servicios systemd system
log "2/7 — Servicios systemd system"
for svc in hermes nlm-gateway; do
  if sudo systemctl is-active "$svc" &>/dev/null 2>&1; then
    log "  Parando $svc..."
    run "sudo systemctl stop $svc 2>/dev/null || true"
    run "sudo systemctl disable $svc 2>/dev/null || true"
  fi
done

# 3. Docker — parar y limpiar
log "3/7 — Docker containers, volumes, images, networks"
if command -v docker &>/dev/null; then
  CONTAINERS=$(docker ps -aq 2>/dev/null | wc -l)
  VOLUMES=$(docker volume ls -q 2>/dev/null | wc -l)
  IMAGES=$(docker images -q 2>/dev/null | wc -l)
  log "  Containers: $CONTAINERS, Volumes: $VOLUMES, Images: $IMAGES"

  run "docker stop \$(docker ps -aq) 2>/dev/null || true"
  run "docker rm -f \$(docker ps -aq) 2>/dev/null || true"
  run "docker system prune -af --volumes 2>/dev/null || true"
fi

# 4. Borrar directorio del lab
log "4/7 — Directorio ~/ai-lab/"
if [ -d "$HOME/ai-lab" ]; then
  DU=$(du -sh "$HOME/ai-lab" 2>/dev/null | cut -f1)
  log "  ~/ai-lab/ ocupa $DU"
  run "rm -rf $HOME/ai-lab"
fi

# 5. Limpiar configs de usuario
log "5/7 — Configs de usuario"
CONFIGS=(
  "$HOME/.config/systemd/user/dagu.service"
  "$HOME/.config/systemd/user/moolmesh.service"
  "$HOME/.config/systemd/user/centro-de-comando.service"
  "$HOME/.config/systemd/user/hermes.service"
  "$HOME/.config/dagu"
  "$HOME/.hermes"
  "$HOME/.opencode"
)
for cfg in "${CONFIGS[@]}"; do
  if [ -e "$cfg" ]; then
    log "  Borrando $cfg"
    run "rm -rf '$cfg'"
  fi
done

if [ "$CONFIRM" = true ]; then
  systemctl --user daemon-reload 2>/dev/null || true
fi

# 6. Limpiar crontab del lab
log "6/7 — Crontab"
if crontab -l 2>/dev/null | grep -q "ai-lab\|lab-session\|lab-backup"; then
  log "  Encontradas entradas del lab en crontab"
  run "crontab -l 2>/dev/null | grep -v 'ai-lab\|lab-session\|lab-backup' | crontab - 2>/dev/null || true"
fi

# 7. Limpiar .bashrc de entradas del lab
log "7/7 — Aliases en .bashrc"
if grep -q "# AI Lab" "$HOME/.bashrc" 2>/dev/null; then
  log "  Encontrado bloque '# AI Lab' en .bashrc"
  run "sed -i '/# AI Lab/,+5d' $HOME/.bashrc"
fi

echo ""
echo "============================================"
if [ "$CONFIRM" = true ]; then
  echo "  Limpieza completada."
  echo ""
  echo "  Queda instalado:"
  echo "    ✓ Ubuntu $(lsb_release -rs 2>/dev/null || echo '?')"
  echo "    ✓ Tailscale $(tailscale version 2>/dev/null | head -1 || echo '?')"
  echo "    ✓ SSH ($(systemctl is-active sshd 2>/dev/null || echo '?'))"
  echo "    ✓ Docker (vacío, sin containers)"
  echo "    ✓ Usuario: $(whoami)"
  echo ""
  echo "  Para reinstalar el lab:"
  echo "    git clone https://github.com/almacreativa/ai-lab-bootstrap.git"
  echo "    cd ai-lab-bootstrap && bash bootstrap.sh"
else
  echo "  Dry-run completado. Para ejecutar:"
  echo "    bash $0 --confirm"
fi
echo "============================================"
