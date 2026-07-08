#!/usr/bin/env bash
# post-reboot-check.sh — verifica y recupera servicios tras reinicio del servidor
# Uso: bash ~/ai-lab/scripts/post-reboot-check.sh
# Ejecutar ~2 minutos después del boot (cuando Tailscale ya esté activo)

set -euo pipefail

source "${LAB_DIR:-$HOME/ai-lab}/scripts/.env" 2>/dev/null

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${YELLOW}[FIX]${NC}   $1"; }

ERRORS=0

echo ""
echo "=== Post-reboot check — i12local ==="
echo "$(date)"
echo ""

# ─── 1. Tailscale ────────────────────────────────────────────────────────────
# Nota: no usar 'ip addr | grep -q' con pipefail — grep -q causa SIGPIPE en ip addr (exit 141)
TAILSCALE_IP=$(ip addr show tailscale0 2>/dev/null | grep "${LAB_IP}" || true)
if [ -n "$TAILSCALE_IP" ]; then
  ok "Tailscale (${LAB_IP} disponible)"
else
  fail "Tailscale no tiene la IP ${LAB_IP} asignada — esperar y reintentar"
  echo ""
  echo "Los servicios que dependen de Tailscale no se pueden recuperar aún."
  echo "Ejecutar de nuevo cuando 'tailscale status' muestre Connected."
  exit 1
fi

# ─── 2. Dagu ─────────────────────────────────────────────────────────────────
if ss -tlnp | grep -q "${LAB_IP}:8480"; then
  ok "Dagu HTTP (:8480)"
else
  info "Dagu no escucha en :8480 — reiniciando system service..."
  sudo systemctl restart dagu.service
  sleep 6
  if ss -tlnp | grep -q "${LAB_IP}:8480"; then
    ok "Dagu HTTP (:8480) — recuperado"
  else
    fail "Dagu no arrancó en :8480 — revisar: journalctl -u dagu.service -n 30"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ─── 3. Paperclip server ─────────────────────────────────────────────────────
PC_STATUS=$(docker inspect paperclip-server-1 --format '{{.State.Status}}' 2>/dev/null || echo "missing")
if [ "$PC_STATUS" = "running" ]; then
  ok "Paperclip server (running)"
else
  info "Paperclip server en estado '$PC_STATUS' — levantando desde stack..."
  cd ~/ai-lab/stacks/paperclip
  docker compose up -d server 2>&1 | tail -5
  sleep 8
  PC_STATUS=$(docker inspect paperclip-server-1 --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [ "$PC_STATUS" = "running" ]; then
    ok "Paperclip server — recuperado"
  else
    fail "Paperclip server no arrancó — revisar: docker logs paperclip-server-1 --tail=30"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ─── 4. Odysseus ─────────────────────────────────────────────────────────────
OD_STATUS=$(docker inspect odysseus --format '{{.State.Status}}' 2>/dev/null || echo "missing")
OD_PORTS=$(docker inspect odysseus --format '{{json .NetworkSettings.Ports}}' 2>/dev/null || echo "null")
if [ "$OD_STATUS" = "running" ] && [ "$OD_PORTS" != "{}" ] && [ "$OD_PORTS" != "null" ]; then
  ok "Odysseus (:7000)"
else
  info "Odysseus en estado '$OD_STATUS' o sin ports — recreando..."
  cd ~/ai-lab/stacks/odysseus
  docker compose down odysseus 2>&1 | tail -3
  docker compose up -d odysseus 2>&1 | tail -3
  sleep 8
  OD_STATUS=$(docker inspect odysseus --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [ "$OD_STATUS" = "running" ]; then
    ok "Odysseus — recuperado"
  else
    fail "Odysseus no arrancó — revisar: docker logs odysseus --tail=30"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ─── 5. Portainer ────────────────────────────────────────────────────────────
# Race condition: Docker puede levantar el contenedor antes de que Tailscale asigne IP
# → contenedor "Up" pero sin port bindings (puertos vacíos). Detectar y recrear.
PT_STATUS=$(docker inspect portainer --format '{{.State.Status}}' 2>/dev/null || echo "missing")
PT_PORTS=$(docker inspect portainer --format '{{json .NetworkSettings.Ports}}' 2>/dev/null || echo "{}")
if [ "$PT_STATUS" = "running" ] && [ "$PT_PORTS" != "{}" ] && [ "$PT_PORTS" != "null" ]; then
  ok "Portainer (:9443)"
elif [ "$PT_STATUS" = "running" ] && { [ "$PT_PORTS" = "{}" ] || [ "$PT_PORTS" = "null" ]; }; then
  info "Portainer running pero sin port bindings (race Tailscale) — recreando..."
  cd ~/ai-lab/stacks/portainer
  docker compose down 2>&1 | tail -3
  docker compose up -d 2>&1 | tail -3
  sleep 6
  PT_PORTS=$(docker inspect portainer --format '{{json .NetworkSettings.Ports}}' 2>/dev/null || echo "{}")
  if [ "$PT_PORTS" != "{}" ] && [ "$PT_PORTS" != "null" ]; then
    ok "Portainer — recuperado con puertos"
  else
    fail "Portainer sin puertos tras recrear — revisar: docker logs portainer --tail=20"
    ERRORS=$((ERRORS + 1))
  fi
else
  info "Portainer en estado '$PT_STATUS' — levantando desde stack..."
  cd ~/ai-lab/stacks/portainer
  docker compose up -d 2>&1 | tail -3
  sleep 6
  PT_STATUS=$(docker inspect portainer --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [ "$PT_STATUS" = "running" ]; then
    ok "Portainer — recuperado"
  else
    fail "Portainer no arrancó — revisar: docker logs portainer --tail=20"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ─── 6. Glance ───────────────────────────────────────────────────────────────
GL_STATUS=$(docker inspect glance --format '{{.State.Status}}' 2>/dev/null || echo "missing")
if [ "$GL_STATUS" = "running" ]; then
  ok "Glance"
else
  info "Glance en estado '$GL_STATUS' — levantando desde stack..."
  cd ~/ai-lab/stacks/glance
  docker compose up -d 2>&1 | tail -3
  sleep 5
  GL_STATUS=$(docker inspect glance --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [ "$GL_STATUS" = "running" ]; then
    ok "Glance — recuperado"
  else
    fail "Glance no arrancó — revisar: docker logs glance --tail=20"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ─── 7. Uptime Kuma ──────────────────────────────────────────────────────────
# Race condition: Kuma bindea a IP Tailscale — misma lógica que Portainer
UK_STATUS=$(docker inspect uptime-kuma --format '{{.State.Status}}' 2>/dev/null || echo "missing")
UK_PORTS=$(docker inspect uptime-kuma --format '{{json .NetworkSettings.Ports}}' 2>/dev/null || echo "{}")
if [ "$UK_STATUS" = "running" ] && [ "$UK_PORTS" != "{}" ] && [ "$UK_PORTS" != "null" ]; then
  ok "Uptime Kuma (:3001)"
elif [ "$UK_STATUS" = "running" ] && { [ "$UK_PORTS" = "{}" ] || [ "$UK_PORTS" = "null" ]; }; then
  info "Uptime Kuma running pero sin port bindings (race Tailscale) — recreando..."
  cd ~/ai-lab/stacks/uptime-kuma
  docker compose down 2>&1 | tail -3
  docker compose up -d 2>&1 | tail -3
  sleep 5
  UK_PORTS=$(docker inspect uptime-kuma --format '{{json .NetworkSettings.Ports}}' 2>/dev/null || echo "{}")
  if [ "$UK_PORTS" != "{}" ] && [ "$UK_PORTS" != "null" ]; then
    ok "Uptime Kuma — recuperado con puertos"
  else
    fail "Uptime Kuma sin puertos tras recrear — revisar: docker logs uptime-kuma --tail=20"
    ERRORS=$((ERRORS + 1))
  fi
else
  info "Uptime Kuma en estado '$UK_STATUS' — levantando desde stack..."
  cd ~/ai-lab/stacks/uptime-kuma
  docker compose up -d 2>&1 | tail -3
  sleep 5
  UK_STATUS=$(docker inspect uptime-kuma --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [ "$UK_STATUS" = "running" ]; then
    ok "Uptime Kuma — recuperado"
  else
    fail "Uptime Kuma no arrancó — revisar: docker logs uptime-kuma --tail=20 (¿Tailscale activo?)"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ─── 8. SearXNG ──────────────────────────────────────────────────────────────
SX_STATUS=$(docker inspect searxng --format '{{.State.Status}}' 2>/dev/null || echo "missing")
if [ "$SX_STATUS" = "running" ]; then
  ok "SearXNG (:8080)"
else
  info "SearXNG en estado '$SX_STATUS' — levantando desde stack..."
  cd ~/ai-lab/stacks/searxng
  docker compose up -d 2>&1 | tail -3
  sleep 5
  SX_STATUS=$(docker inspect searxng --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [ "$SX_STATUS" = "running" ]; then
    ok "SearXNG — recuperado"
  else
    fail "SearXNG no arrancó — revisar: docker logs searxng --tail=20"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ─── 9. Mem0 + Ollama ────────────────────────────────────────────────────────
M0_STATUS=$(docker inspect mem0 --format '{{.State.Status}}' 2>/dev/null || echo "missing")
if [ "$M0_STATUS" = "running" ]; then
  ok "Mem0 + Ollama (:8765)"
else
  info "Mem0 en estado '$M0_STATUS' — levantando desde stack..."
  cd ~/ai-lab/stacks/mem0
  docker compose up -d 2>&1 | tail -3
  sleep 8
  M0_STATUS=$(docker inspect mem0 --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [ "$M0_STATUS" = "running" ]; then
    ok "Mem0 + Ollama — recuperados"
  else
    fail "Mem0 no arrancó — revisar: docker logs mem0 --tail=20"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ─── 10. Hermes ──────────────────────────────────────────────────────────────
# Hermes arranca via @reboot crontab (tmux), no tiene hermes.service — verificar por HTTP
HERMES_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${LAB_IP}:9119 --max-time 5 || true)
if [ "$HERMES_CODE" = "200" ] || [ "$HERMES_CODE" = "302" ]; then
  ok "Hermes (:9119 HTTP $HERMES_CODE)"
else
  fail "Hermes no responde en :9119 (HTTP $HERMES_CODE) — revisar: ps aux | grep hermes"
  ERRORS=$((ERRORS + 1))
fi

# ─── 11. MoolMesh ────────────────────────────────────────────────────────────
if XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active moolmesh.service > /dev/null 2>&1; then
  ok "MoolMesh (systemd)"
else
  fail "MoolMesh no está activo — revisar: systemctl --user status moolmesh.service"
  ERRORS=$((ERRORS + 1))
fi

# ─── Resumen ──────────────────────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}Todos los servicios OK.${NC}"
  echo "Verificar visualmente en Centro de Comando: http://${LAB_IP}:9000"
else
  echo -e "${RED}${ERRORS} servicio(s) con error — ver mensajes arriba.${NC}"
  echo "Referencia: ~/ai-lab/repos/i7local-lab/docs/SERVICIOS.md"
fi
echo ""
