#!/usr/bin/env bash
# lab-health-check.sh — Verifica que los servicios del lab estén sanos.
# Linux: contenedores Docker + redes. macOS: launchd + brew services.
# Cron/Dagu: cada 10-15 min para detectar drift.

set -uo pipefail

LOG="$HOME/ai-lab/logs/lab-health.log"
NOTIFY_SCRIPT="$HOME/ai-lab/scripts/telegram-notify.sh"
ENV_FILE="$HOME/.hermes/.env"

mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1
echo "=== lab-health-check $(date -u '+%Y-%m-%d %H:%M UTC') ==="

CHAT_ID=""
if [[ -f "$ENV_FILE" ]]; then
  CHAT_ID=$(grep -E '^TELEGRAM_CHAT_ID=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
  [[ -z "$CHAT_ID" ]] && \
    CHAT_ID=$(grep -E '^TELEGRAM_ALLOWED_USERS=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | cut -d, -f1 || true)
fi

ISSUES=()

notify() {
  local msg="$1"
  echo "[NOTIFY] $msg"
  if [[ -n "$CHAT_ID" && -x "$NOTIFY_SCRIPT" ]]; then
    TELEGRAM_CHAT_ID="$CHAT_ID" "$NOTIFY_SCRIPT" "$msg" "WARN" 2>/dev/null || true
  fi
}

if [[ "$(uname)" == "Darwin" ]]; then
  # ── macOS: verificar servicios launchd y brew ──
  for svc in com.almacreativa.hermes com.almacreativa.paperclip com.almacreativa.dagu; do
    if ! launchctl list "$svc" &>/dev/null; then
      echo "  $svc no está corriendo — intentando cargar..."
      launchctl load "$HOME/Library/LaunchAgents/${svc}.plist" 2>/dev/null || true
      ISSUES+=("$svc no estaba corriendo — se cargó")
    fi
  done

  if ! brew services list | grep -q "postgresql@17.*started"; then
    echo "  PostgreSQL no está corriendo — iniciando..."
    brew services start postgresql@17 2>/dev/null || true
    ISSUES+=("PostgreSQL no estaba corriendo — se inició")
  fi

  # Endpoints HTTP
  declare -A HEALTH_URLS=(
    [paperclip]="http://127.0.0.1:3100/api/health"
    [hermes]="http://127.0.0.1:9119"
  )

  for svc in "${!HEALTH_URLS[@]}"; do
    url="${HEALTH_URLS[$svc]}"
    if ! curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
      echo "  $svc: no responde en $url — reiniciando..."
      launchctl kickstart -k "gui/$(id -u)/com.almacreativa.${svc}" 2>/dev/null || true
      ISSUES+=("$svc no respondía en $url — se reinició")
    fi
  done

else
  # ── Linux: verificar contenedores Docker y redes ──
  container_networks() {
    docker inspect "$1" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null \
      | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin).keys()))" 2>/dev/null
  }

  declare -A REQUIRED_NETWORKS=(
    [uptime-kuma]="mem0_default paperclip_default"
    [mem0]="mem0_default paperclip_default"
    [ollama]="mem0_default"
  )

  for container in "${!REQUIRED_NETWORKS[@]}"; do
    if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
      if docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
        echo "  $container existe pero no está corriendo — iniciando..."
        docker start "$container" >/dev/null 2>&1
        ISSUES+=("$container estaba detenido — se inició")
      else
        echo "  $container no existe — fuera de alcance de este script"
        continue
      fi
    fi

    current=$(container_networks "$container")
    for net in ${REQUIRED_NETWORKS[$container]}; do
      if ! echo " $current " | grep -q " $net "; then
        echo "  $container: falta red $net — conectando..."
        if docker network connect "$net" "$container" 2>&1; then
          ISSUES+=("$container reconectado a red $net")
        else
          ISSUES+=("$container: fallo al conectar a $net")
        fi
      fi
    done
  done

  declare -A HEALTH_URLS=(
    [mem0]="http://127.0.0.1:8765/health"
    [ollama]="http://127.0.0.1:11434/api/tags"
  )

  for container in "${!HEALTH_URLS[@]}"; do
    url="${HEALTH_URLS[$container]}"
    if ! curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
      echo "  $container: no responde en $url — reiniciando contenedor..."
      docker restart "$container" >/dev/null 2>&1
      ISSUES+=("$container no respondía en $url — se reinició")
    fi
  done
fi

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  SUMMARY="lab-health-check encontró y corrigió:
$(printf '  - %s\n' "${ISSUES[@]}")"
  notify "$SUMMARY"
else
  echo "  Todo sano. Sin acciones."
fi

echo "=== fin $(date -u '+%H:%M UTC') ==="
