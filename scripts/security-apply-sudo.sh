#!/usr/bin/env bash
# security-apply-sudo.sh v2 — Hardening de seguridad derivado del manifiesto.
#
# Lee core-manifest.yaml para generar reglas UFW por puerto (modelo per-port)
# e instalar/configurar fail2ban si corresponde.
#
# USO:  sudo bash ~/ai-lab/scripts/security-apply-sudo.sh
#
# Idempotente: correrlo dos veces no rompe nada.
# IMPORTANTE: correr desde consola física o SSH vía Tailscale. SSH se agrega
# ANTES de borrar la regla amplia para no perder acceso.

set -euo pipefail

PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
warn() { echo "  ⚠️  $1"; }
err()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script requiere sudo: sudo bash $0"
  exit 1
fi

LAB_DIR="${LAB_DIR:-/home/${SUDO_USER:-$USER}/ai-lab}"
MANIFEST="$LAB_DIR/ops/core-manifest.yaml"
ENV_FILE="$LAB_DIR/scripts/.env"
TAILSCALE_NET="100.64.0.0/10"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: Manifiesto no encontrado en $MANIFEST"
  echo "Generar con: $LAB_DIR/ops/manifests/generate-core-manifest.sh"
  exit 1
fi

echo "=== Leyendo manifiesto: $MANIFEST ==="

eval "$(python3 -c "
import yaml, sys
m = yaml.safe_load(open('$MANIFEST'))
net = m.get('network', {})
sec = m.get('security', {})
print(f'LAN_SUBNET=\"{net.get(\"lan_subnet\", \"\")}\"')
print(f'TAILSCALE_IP=\"{net.get(\"tailscale_ip\", \"\")}\"')
print(f'FAIL2BAN_REQUIRED=\"{str(sec.get(\"fail2ban\", False)).lower()}\"')
for p in sec.get('allowed_ports', []):
    port = p.get('port', '')
    proto = p.get('proto', 'tcp')
    sources = ','.join(p.get('from', []))
    svc = p.get('service', 'unknown')
    print(f'PORT_ENTRY=\"{port}|{proto}|{sources}|{svc}\"')
" 2>&1)" || { echo "ERROR: Fallo parseando manifiesto"; exit 1; }

echo "  Tailscale IP: $TAILSCALE_IP"
echo "  LAN subnet:   $LAN_SUBNET"
echo "  fail2ban:     $FAIL2BAN_REQUIRED"
echo ""

echo "=== S2.1 — CUPS: detener y deshabilitar ==="
if snap list cups >/dev/null 2>&1; then
  if snap services cups 2>/dev/null | grep -q active; then
    snap stop --disable cups && ok "CUPS (snap) detenido y deshabilitado" || err "No se pudo detener CUPS"
  else
    ok "CUPS ya estaba detenido"
  fi
else
  ok "CUPS (snap) no instalado"
fi
systemctl list-unit-files cups.service >/dev/null 2>&1 && systemctl disable --now cups cups-browsed 2>/dev/null
true

echo ""
echo "=== S2.2 — UFW: reglas por puerto desde manifiesto ==="
echo "  (Docker bypassea UFW — los binds protegen los contenedores)"

ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1

while IFS='|' read -r port proto sources svc; do
  [ -z "$port" ] && continue
  IFS=',' read -ra srcs <<< "$sources"
  for src in "${srcs[@]}"; do
    case "$src" in
      tailscale)
        ufw allow from "$TAILSCALE_NET" to any port "$port" proto "$proto" comment "$svc via Tailscale" >/dev/null 2>&1
        ;;
      lan)
        ufw allow from "$LAN_SUBNET" to any port "$port" proto "$proto" comment "$svc LAN" >/dev/null 2>&1
        ;;
    esac
  done
  ok "Puerto $port/$proto ($svc) — fuentes: $sources"
done < <(python3 -c "
import yaml
m = yaml.safe_load(open('$MANIFEST'))
for p in m.get('security', {}).get('allowed_ports', []):
    port = p.get('port', '')
    proto = p.get('proto', 'tcp')
    sources = ','.join(p.get('from', []))
    svc = p.get('service', 'unknown')
    print(f'{port}|{proto}|{sources}|{svc}')
")

echo ""
echo "  Caso especial: Hermes 9119 desde Docker (Uptime Kuma → monitoreo)"
ufw allow from 172.16.0.0/12 to any port 9119 proto tcp comment 'Kuma monitor -> Hermes' >/dev/null 2>&1

echo ""
echo "=== S2.3 — Eliminar regla amplia por interfaz (modelo viejo) ==="
if ufw status | grep -q "Anywhere on tailscale0.*ALLOW"; then
  ufw delete allow in on tailscale0 >/dev/null 2>&1 && ok "Regla 'allow in on tailscale0' eliminada" || warn "No se pudo eliminar regla por interfaz"
else
  ok "Regla por interfaz ya no existe"
fi

echo ""
if ufw status | grep -q "Status: active"; then
  ufw reload >/dev/null 2>&1 && ok "UFW recargado"
else
  ufw --force enable >/dev/null 2>&1 && ok "UFW habilitado" || err "No se pudo habilitar UFW"
fi

echo ""
echo "=== S2.4 — fail2ban ==="
if [ "$FAIL2BAN_REQUIRED" = "true" ]; then
  if ! command -v fail2ban-server &>/dev/null; then
    apt install -y fail2ban >/dev/null 2>&1 && ok "fail2ban instalado" || err "No se pudo instalar fail2ban"
  else
    ok "fail2ban ya instalado"
  fi

  if [ ! -f /etc/fail2ban/jail.local ]; then
    cat > /etc/fail2ban/jail.local <<'JAIL'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
findtime = 600
bantime = 3600
JAIL
    ok "jail.local creado para SSH"
  else
    ok "jail.local ya existe"
  fi

  systemctl enable fail2ban >/dev/null 2>&1
  systemctl restart fail2ban >/dev/null 2>&1
  if systemctl is-active fail2ban >/dev/null 2>&1; then
    ok "fail2ban activo"
  else
    err "fail2ban no pudo arrancar"
  fi
else
  ok "fail2ban no requerido por el manifiesto — saltando"
fi

echo ""
echo "=== S2.5 — Verificación final ==="

if ss -tln | grep -q ":631 "; then
  err "Puerto 631 (CUPS) sigue escuchando"
else
  ok "Puerto 631 cerrado"
fi

if ufw status | grep -q "22.*100.64.0.0/10"; then
  ok "SSH accesible desde Tailscale"
else
  err "FALTA regla SSH desde Tailscale — REVISAR ANTES DE CERRAR SESIÓN"
fi

if ufw status | grep -q "22.*$LAN_SUBNET"; then
  ok "SSH accesible desde LAN (anti-lockout)"
else
  err "FALTA regla SSH desde LAN"
fi

if ufw status | grep -q "Anywhere on tailscale0.*ALLOW"; then
  warn "Regla amplia por interfaz TODAVÍA presente"
else
  ok "Sin reglas amplias por interfaz"
fi

echo ""
echo "  Reglas UFW actuales:"
ufw status numbered | sed 's/^/    /'

echo ""
echo "=== Resumen: $PASS OK, $FAIL errores ==="
echo ""
echo "VALIDAR DESDE EL MAC (antes de cerrar esta terminal):"
echo "  1. ssh sigue funcionando (abrir segunda sesión SSH AHORA)"
echo "  2. Todos los servicios responden via Tailscale"
echo ""
echo "Si algo se rompió: sudo ufw disable"
exit $FAIL
