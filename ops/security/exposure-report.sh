#!/usr/bin/env bash
# exposure-report.sh — Reporte de exposición al final del bootstrap (F5 audit).
#
# Self-contained: NO requiere core-manifest.yaml ni telegram-notify.sh (a
# diferencia de exposure-watchdog.sh, que sí los necesita y corre vía Dagu).
# Reusa solo los idioms de detección del watchdog.
#
# Read-only e informativo: imprime a stdout un resumen legible de la postura de
# seguridad (UFW, fail2ban, SSH hardening, puertos del host en 0.0.0.0, Docker
# publicando en 0.0.0.0). NUNCA sale con código != 0 — el bootstrap corre con
# set -e y este reporte jamás debe abortarlo.
#
# Re-ejecutable en cualquier momento:
#   bash ~/ai-lab/repos/ai-lab-bootstrap/ops/security/exposure-report.sh
#
# Cierra el círculo de confianza sobre F1 (paneles a localhost) y F2 (firewall
# baseline): al terminar, el bootstrap dice qué quedó protegido vs expuesto.

# Sin `set -e`: es un reporte, cada check tiene sus propias guardas defensivas.
set -uo pipefail

# ── Colores (funcionan tanto sourced desde el bootstrap como ejecutado suelto) ──
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
BOLD="${BOLD:-\033[1m}"
NC="${NC:-\033[0m}"

OK="${GREEN}✅${NC}"
WARN="${YELLOW}⚠️ ${NC}"

echo ""
echo -e "${BOLD}── Resumen de exposición ──${NC}"

# ── 1) UFW: activo + default deny incoming ──
if command -v ufw >/dev/null 2>&1; then
  ufw_out="$(sudo ufw status verbose 2>/dev/null || true)"
  if echo "$ufw_out" | grep -q "^Status: active"; then
    if echo "$ufw_out" | grep -qi "Default:.*deny.*(incoming)"; then
      echo -e "  ${OK} UFW activo con default deny (incoming)."
    else
      echo -e "  ${WARN} UFW activo pero el default NO es deny incoming — revisar reglas."
    fi
  else
    echo -e "  ${WARN} UFW instalado pero INACTIVO — el host no tiene firewall. Aplicar: security-apply-sudo.sh (o correr el bootstrap con firewall-baseline)."
  fi
else
  echo -e "  ${WARN} UFW no instalado — el host no tiene firewall."
fi

# ── 2) fail2ban: activo ──
if command -v fail2ban-server >/dev/null 2>&1 || command -v fail2ban-client >/dev/null 2>&1; then
  f2b_status="$(systemctl is-active fail2ban 2>/dev/null || true)"
  if [ "$f2b_status" = "active" ] || pgrep -f "fail2ban-server" >/dev/null 2>&1; then
    echo -e "  ${OK} fail2ban activo (rate-limiting de SSH)."
  else
    echo -e "  ${WARN} fail2ban instalado pero INACTIVO."
  fi
else
  echo -e "  ${WARN} fail2ban no instalado."
fi

# ── 3) SSH hardening: sin password, sin root ──
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -r "$SSHD_CONFIG" ]; then
  pass_no=0; root_no=0
  grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+no' "$SSHD_CONFIG" && pass_no=1
  grep -Eq '^[[:space:]]*PermitRootLogin[[:space:]]+no' "$SSHD_CONFIG" && root_no=1
  if [ "$pass_no" = 1 ] && [ "$root_no" = 1 ]; then
    echo -e "  ${OK} SSH endurecido (sin password, sin root)."
  else
    detail=""
    [ "$pass_no" = 0 ] && detail="${detail} PasswordAuthentication no está en 'no';"
    [ "$root_no" = 0 ] && detail="${detail} PermitRootLogin no está en 'no';"
    echo -e "  ${WARN} SSH sin endurecer por completo —${detail}"
  fi
else
  echo -e "  ${WARN} No se pudo leer $SSHD_CONFIG para verificar el hardening de SSH."
fi

# ── 4) Puertos del host escuchando en 0.0.0.0 (idiom del watchdog L96) ──
if command -v ss >/dev/null 2>&1; then
  host_ports="$(ss -tln 2>/dev/null | awk '$4 ~ /^(0\.0\.0\.0|\*|\[::\]):/ {sub(/.*:/,"",$4); print $4}' | sort -un | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ -z "$host_ports" ]; then
    echo -e "  ${OK} Ningún puerto del host escuchando en 0.0.0.0."
  else
    echo -e "  ${WARN} Puertos del host en 0.0.0.0 (protegidos por UFW si está activo, expuestos si no): ${host_ports}"
  fi
else
  echo -e "  ${WARN} 'ss' no disponible — no se pudieron listar los puertos del host."
fi

# ── 5) Docker publicando en 0.0.0.0 (idiom del watchdog L99 — bypassea UFW) ──
if command -v docker >/dev/null 2>&1; then
  dock="$(docker ps --format '{{.Names}} -> {{.Ports}}' 2>/dev/null | grep '0\.0\.0\.0' || true)"
  if [ -z "$dock" ]; then
    echo -e "  ${OK} Ningún contenedor Docker publicando en 0.0.0.0."
  else
    echo -e "  ${WARN} Contenedores Docker en 0.0.0.0 — bypassean UFW; cerralos por bind (LAB_BIND_ADDR=127.0.0.1):"
    while IFS= read -r line; do
      [ -n "$line" ] && echo -e "        ${line}"
    done <<< "$dock"
  fi
else
  # Docker puede no estar instalado (bootstrap parcial) — informativo, no alerta.
  echo -e "  ${OK} Docker no presente — sin contenedores que evaluar."
fi

echo ""
echo -e "  ${BOLD}Nota:${NC} acceso remoto pensado por Tailscale/túnel SSH, no por puerto abierto."
echo -e "        Para afinar el firewall per-port por servicio: scripts/security-apply-sudo.sh"
echo ""

exit 0
