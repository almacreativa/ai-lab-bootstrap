#!/usr/bin/env bash
# exposure-watchdog.sh — Monitorea exposición no aprobada del lab.
#
# Corre cada 15 min vía Dagu (no cron directo). Sin sudo — complementa a
# security-apply-sudo.sh monitoreando que sus reglas sigan vigentes.
#
# Baseline de seguridad (definida en security-apply-sudo.sh):
#   - UFW: deny incoming, solo Tailscale (100.64.0.0/10) + LAN (192.168.0.0/24)
#   - Puertos expuestos: 22 (SSH), 9119 (Hermes dashboard), 22000 (Syncthing)
#   - CUPS (631): deshabilitado
#   - Docker: los binds ya fueron corregidos aparte
#
# Qué monitorea:
#   1. Túneles no autorizados hacia internet (cloudflared, ngrok, frp, etc.)
#   2. UFW y fail2ban vivos
#   3. Puertos nuevos en 0.0.0.0 fuera del baseline
#   4. Contenedores Docker publicando en 0.0.0.0 (Docker puentea UFW)
#
# Requisitos: LAB_DIR definido (default ~/ai-lab), telegram-notify.sh instalado.

set -euo pipefail

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
NOTIFY="$LAB_DIR/scripts/telegram-notify.sh"
STATE="$LAB_DIR/ops/state/exposure-watchdog.last"
LOG="$LAB_DIR/logs/exposure-watchdog.log"

# Puertos baseline — los que security-apply-sudo.sh deja expuestos
ALLOWED_WILDCARD_PORTS="22 9119 22000"

mkdir -p "$(dirname "$STATE")" "$(dirname "$LOG")"
alerts=()

# ── 1) Túneles hacia internet público ──
tun=$(pgrep -af 'cloudflared|ngrok|frpc|frps|pagekite|localtunnel|serveo' 2>/dev/null | grep -v 'exposure-watchdog' || true)
if [ -n "$tun" ]; then
  alerts+=("TÚNEL A INTERNET DETECTADO:
$tun")
fi

# ── 2) Firewall y fail2ban vivos ──
# systemctl is-active puede devolver "unknown" sin sudo; fallback por proceso/comando
ufw_status=$(systemctl is-active ufw 2>/dev/null || true)
if [ "$ufw_status" != "active" ] && [ "$ufw_status" != "unknown" ]; then
  alerts+=("UFW NO ESTÁ ACTIVO — las reglas de security-apply-sudo.sh pueden haberse caído")
elif [ "$ufw_status" = "unknown" ]; then
  # Sin permisos systemctl — verificar por comando ufw status o proceso
  if ! ufw status 2>/dev/null | grep -q "^Status: active" && ! pgrep -f "ufw" &>/dev/null; then
    alerts+=("UFW NO SE PUEDE VERIFICAR (sin permisos systemctl)")
  fi
fi

fail2ban_status=$(systemctl is-active fail2ban 2>/dev/null || true)
if [ "$fail2ban_status" != "active" ] && [ "$fail2ban_status" != "unknown" ]; then
  alerts+=("FAIL2BAN NO ESTÁ ACTIVO")
elif [ "$fail2ban_status" = "unknown" ]; then
  # Sin permisos systemctl — verificar por proceso fail2ban-server
  if ! pgrep -f "fail2ban-server" &>/dev/null; then
    alerts+=("FAIL2BAN NO SE PUEDE VERIFICAR (sin permisos systemctl)")
  fi
fi

# ── 3) Puertos wildcard fuera de baseline ──
while read -r port; do
  case " $ALLOWED_WILDCARD_PORTS " in
    *" $port "*) ;;
    *) alerts+=("PUERTO PÚBLICO NUEVO fuera de baseline: $port") ;;
  esac
done < <(ss -tln | awk '$4 ~ /^(0\.0\.0\.0|\*|\[::\]):/ {sub(/.*:/,"",$4); print $4}' | sort -un)

# ── 4) Docker expuesto en 0.0.0.0 (bypassea UFW) ──
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
