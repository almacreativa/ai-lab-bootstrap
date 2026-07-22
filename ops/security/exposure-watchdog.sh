#!/usr/bin/env bash
# exposure-watchdog.sh v2 — Monitorea exposición no aprobada del lab.
#
# Versión derivada del manifiesto: lee allowed_ports[] y docker_binds[] de
# core-manifest.yaml en lugar de mantener una lista propia.
#
# Corre cada 15 min vía Dagu (no cron directo). Sin sudo.
#
# Qué monitorea:
#   1. Túneles no autorizados hacia internet
#   2. UFW activo + deny incoming
#   3. fail2ban activo (si el manifiesto lo requiere)
#   4. Puertos bare-metal en 0.0.0.0 fuera del baseline del manifiesto
#   5. Docker publicando en 0.0.0.0 (bypassea UFW)
#
# Requisitos: LAB_DIR definido (default ~/ai-lab), telegram-notify.sh instalado.

set -euo pipefail

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
MANIFEST="$LAB_DIR/ops/core-manifest.yaml"
NOTIFY="$LAB_DIR/scripts/telegram-notify.sh"
STATE="$LAB_DIR/ops/state/exposure-watchdog.last"
LOG="$LAB_DIR/logs/exposure-watchdog.log"

mkdir -p "$(dirname "$STATE")" "$(dirname "$LOG")"
alerts=()

if [ ! -f "$MANIFEST" ]; then
  echo "$(date '+%F %H:%M') ERROR: Manifiesto no encontrado en $MANIFEST" >> "$LOG"
  exit 1
fi

read_from_manifest() {
  python3 -c "
import yaml
m = yaml.safe_load(open('$MANIFEST'))
sec = m.get('security', {})
ports = ' '.join(str(p.get('port','')) for p in sec.get('allowed_ports', []))
f2b = str(sec.get('fail2ban', False)).lower()
print(f'ALLOWED_PORTS=\"{ports}\"')
print(f'FAIL2BAN_REQUIRED=\"{f2b}\"')
" 2>/dev/null
}

eval "$(read_from_manifest)" || {
  echo "$(date '+%F %H:%M') ERROR: Fallo parseando manifiesto" >> "$LOG"
  exit 1
}

# ── 1) Túneles hacia internet público ──
tun=$(pgrep -af 'cloudflared|ngrok|frpc|frps|pagekite|localtunnel|serveo' 2>/dev/null | grep -v 'exposure-watchdog' || true)
if [ -n "$tun" ]; then
  alerts+=("TÚNEL A INTERNET DETECTADO:
$tun")
fi

# ── 2) Firewall vivo + deny incoming ──
ufw_status=$(systemctl is-active ufw 2>/dev/null || true)
if [ "$ufw_status" != "active" ] && [ "$ufw_status" != "unknown" ]; then
  alerts+=("UFW NO ESTÁ ACTIVO")
elif [ "$ufw_status" = "unknown" ]; then
  if ! ufw status 2>/dev/null | grep -q "^Status: active" && ! pgrep -f "ufw" &>/dev/null; then
    alerts+=("UFW NO SE PUEDE VERIFICAR (sin permisos systemctl)")
  fi
fi

if sudo ufw status verbose 2>/dev/null | grep -qi "Default:.*deny.*(incoming)"; then
  :
elif sudo ufw status 2>/dev/null | grep -q "^Status: active"; then
  alerts+=("UFW activo pero default no es deny incoming — posible degradación")
elif [ "$ufw_status" != "active" ]; then
  alerts+=("UFW NO ESTÁ ACTIVO")
fi

# ── 3) fail2ban vivo (si el manifiesto lo requiere) ──
if [ "$FAIL2BAN_REQUIRED" = "true" ]; then
  f2b_status=$(systemctl is-active fail2ban 2>/dev/null || true)
  if [ "$f2b_status" = "active" ]; then
    :
  elif pgrep -f "fail2ban-server" &>/dev/null; then
    :
  else
    alerts+=("FAIL2BAN NO ESTÁ ACTIVO (requerido por el manifiesto)")
  fi
fi

# ── 4) Puertos wildcard fuera del baseline del manifiesto ──
while read -r port; do
  [ -z "$port" ] && continue
  [ "$port" -gt 32767 ] 2>/dev/null && continue
  case " $ALLOWED_PORTS " in
    *" $port "*) ;;
    *) alerts+=("PUERTO PÚBLICO fuera del manifiesto: $port") ;;
  esac
done < <(ss -tln | awk '$4 ~ /^(0\.0\.0\.0|\*|\[::\]):/ {sub(/.*:/,"",$4); print $4}' | sort -un)

# ── 5) Docker expuesto en 0.0.0.0 (bypassea UFW) ──
dock=$(docker ps --format '{{.Names}} -> {{.Ports}}' 2>/dev/null | grep '0\.0\.0\.0' || true)
if [ -n "$dock" ]; then
  alerts+=("DOCKER PUBLICANDO EN 0.0.0.0 (bypassea UFW):
$dock")
fi

# ── Sin alertas: registrar OK y salir ──
ts=$(date '+%F %H:%M')
if [ ${#alerts[@]} -eq 0 ]; then
  echo "$ts OK" >> "$LOG"
  rm -f "$STATE"
  exit 0
fi

# ── Alertas: notificar solo si cambiaron desde la última vez ──
msg=$(printf '%s\n\n' "${alerts[@]}")
echo "$ts ALERTA
$msg" >> "$LOG"

hash=$(printf '%s' "$msg" | md5sum | cut -d' ' -f1)
last=$(cat "$STATE" 2>/dev/null || true)
if [ "$hash" != "$last" ]; then
  if [ -x "$NOTIFY" ]; then
    "$NOTIFY" "$msg" WARNING 2>/dev/null || true
  else
    echo "$ts ERROR: $NOTIFY no encontrado o no ejecutable" >> "$LOG"
  fi
  echo "$hash" > "$STATE"
fi
