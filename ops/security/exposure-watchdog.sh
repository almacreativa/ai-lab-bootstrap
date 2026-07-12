#!/bin/bash
# exposure-watchdog: detecta exposición no aprobada y avisa por Telegram.
# Parte de la Fase 1 de hardening (2026-07-06). Corre por cron cada 15 min, sin sudo.
# Baseline de puertos wildcard aprobada: protegidos por UFW (deny incoming salvo tailscale0/22).
#
# REQUISITOS: hermes CLI en $PATH, crontab apuntando a este script.

HOSTNAME=$(hostname)
STATE="$HOME/.local/state/exposure-watchdog.last"
LOG="$HOME/logs/exposure-watchdog.log"
ALLOWED_WILDCARD_PORTS="22 631 4321 5200 22000"

mkdir -p "$(dirname "$STATE")" "$(dirname "$LOG")"
alerts=()

# 1) túneles hacia internet publico
tun=$(pgrep -af 'cloudflared|ngrok|frpc|frps|pagekite|localtunnel|serveo' 2>/dev/null | grep -v 'exposure-watchdog')
[ -n "$tun" ] && alerts+=("TUNEL A INTERNET DETECTADO:
$tun")

# 2) firewall y fail2ban vivos
[ "$(systemctl is-active ufw 2>/dev/null)" = "active" ] || alerts+=("UFW NO ESTA ACTIVO")
[ "$(systemctl is-active fail2ban 2>/dev/null)" = "active" ] || alerts+=("FAIL2BAN NO ESTA ACTIVO")

# 3) puertos escuchando en 0.0.0.0 / * / [::] fuera de baseline
while read -r port; do
  case " $ALLOWED_WILDCARD_PORTS " in
    *" $port "*) ;;
    *) alerts+=("PUERTO PUBLICO NUEVO fuera de baseline: $port") ;;
  esac
done < <(ss -tln | awk '$4 ~ /^(0\.0\.0\.0|\*|\[::\]):/ {sub(/.*:/,"",$4); print $4}' | sort -un)

# 4) contenedores docker publicando en 0.0.0.0 (docker puentea UFW)
dock=$(docker ps --format '{{.Names}} -> {{.Ports}}' 2>/dev/null | grep '0\.0\.0\.0')
[ -n "$dock" ] && alerts+=("DOCKER PUBLICANDO EN 0.0.0.0:
$dock")

ts=$(date '+%F %H:%M')
if [ ${#alerts[@]} -eq 0 ]; then
  echo "$ts OK" >> "$LOG"
  rm -f "$STATE"
  exit 0
fi

msg=$(printf '%s\n\n' "${alerts[@]}")
echo "$ts ALERTA
$msg" >> "$LOG"

hash=$(printf '%s' "$msg" | md5sum | cut -d' ' -f1)
last=$(cat "$STATE" 2>/dev/null)
if [ "$hash" != "$last" ]; then
  if printf '%s' "$msg" | hermes send --to telegram --subject "⚠️ [$HOSTNAME watchdog]" -q; then
    echo "$hash" > "$STATE"
  else
    echo "$ts ERROR: fallo hermes send (reintentara en la proxima pasada)" >> "$LOG"
  fi
fi
