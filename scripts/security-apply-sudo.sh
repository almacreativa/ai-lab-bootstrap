#!/usr/bin/env bash
# Remediación de seguridad — bloque S2 (todo lo que requiere sudo, en una pasada).
# Fuente: ~/shared/demos/security-remediation-plan.md
#
# USO:  sudo bash ~/ai-lab/scripts/security-apply-sudo.sh
#
# Idempotente: correrlo dos veces no rompe nada.
# IMPORTANTE: correr desde consola física o SSH vía Tailscale. La regla de SSH
# se agrega ANTES de activar UFW para no perder acceso.

set -u

PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
warn() { echo "  ⚠️  $1"; }
err()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script requiere sudo: sudo bash $0"
  exit 1
fi

REAL_USER="${SUDO_USER:-<usuario>}"
TAILSCALE_NET="100.64.0.0/10"

echo "=== S2.1 — CUPS: detener y deshabilitar (no se imprime desde este servidor) ==="
if snap list cups >/dev/null 2>&1; then
  if snap services cups 2>/dev/null | grep -q active; then
    snap stop --disable cups && ok "CUPS (snap) detenido y deshabilitado" || err "No se pudo detener CUPS"
  else
    ok "CUPS ya estaba detenido"
  fi
else
  ok "CUPS (snap) no instalado — nada que hacer"
fi
# Por si también existe la versión apt
systemctl list-unit-files cups.service >/dev/null 2>&1 && systemctl disable --now cups cups-browsed 2>/dev/null
true

echo ""
echo "=== S2.2 — UFW: baseline para servicios bare metal ==="
echo "  (Docker bypassea UFW — los binds de los contenedores ya fueron corregidos aparte)"

# Reglas ANTES de habilitar, SSH primero.
# SSH restringido a Tailscale + LAN (ajuste 2026-06-11, validado en vivo).
# OJO si se reusa en un servidor nuevo: asegurarse de que Tailscale esté activo
# o tener consola física — si no, esto te deja afuera.
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow from "$TAILSCALE_NET" to any port 22 proto tcp comment 'SSH via Tailscale' >/dev/null
ufw allow from 192.168.0.0/24 to any port 22 proto tcp comment 'SSH LAN' >/dev/null
# Limpiar la regla amplia si quedó de una corrida anterior
ufw status | grep -q "^22/tcp.*ALLOW.*Anywhere" && ufw delete allow 22/tcp >/dev/null 2>&1
ufw allow from "$TAILSCALE_NET" to any port 9119 proto tcp comment 'Hermes dashboard via Tailscale' >/dev/null
ufw allow from 172.16.0.0/12 to any port 9119 proto tcp comment 'Kuma monitor -> Hermes' >/dev/null
ufw allow from "$TAILSCALE_NET" to any port 22000 proto tcp comment 'Syncthing P2P via Tailscale' >/dev/null
ufw allow from 192.168.0.0/24 to any port 22000 proto tcp comment 'Syncthing P2P LAN' >/dev/null

if ufw status | grep -q "Status: active"; then
  ufw reload >/dev/null && ok "UFW ya activo — reglas recargadas"
else
  ufw --force enable >/dev/null && ok "UFW habilitado con baseline" || err "No se pudo habilitar UFW"
fi
echo "  Reglas actuales:"
ufw status numbered | sed 's/^/    /'

echo ""
echo "=== S2.3 — Verificación final ==="

# CUPS no debe escuchar
if ss -tln | grep -q ":631 "; then
  err "Puerto 631 (CUPS) sigue escuchando — revisar manualmente"
else
  ok "Puerto 631 cerrado"
fi

# SSH accesible (reglas restringidas presentes)
ufw status | grep "22" | grep -q "100.64.0.0/10" && ok "SSH restringido a Tailscale + LAN" || err "FALTA regla SSH — revisar YA antes de cerrar la sesión"
ufw status | grep -q "^22/tcp.*ALLOW.*Anywhere" && warn "Regla SSH amplia (Anywhere) todavía presente — borrar con: ufw delete allow 22/tcp"

# Hermes restringido
ufw status | grep -q "9119" && ok "Hermes 9119 restringido a Tailscale" || err "Falta regla de Hermes"

echo ""
echo "=== Resumen: $PASS OK, $FAIL errores ==="
echo ""
echo "VALIDAR DESDE EL MAC (antes de cerrar esta terminal):"
echo "  1. ssh sigue funcionando (abrir una segunda sesión SSH AHORA para probar)"
echo "  2. http://<TAILSCALE_IP>:9119 (dashboard Hermes) accesible"
echo "  3. Syncthing sigue sincronizando (~/shared/demos en el Mac)"
echo ""
echo "Si algo se rompió: sudo ufw disable  # vuelve todo atrás al instante"
exit $FAIL
