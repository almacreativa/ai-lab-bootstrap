#!/usr/bin/env bash
# cpu-temp-monitor.sh — Push a Uptime Kuma con la temperatura de los cores del CPU.
# Lee CPU_TEMP_KUMA_PUSH_URL desde ~/ai-lab/scripts/.env (monitor tipo Push creado en la UI),
# misma convención que KUMA_PUSH_URL en weekly-ingest.sh.
# Umbrales basados en los límites reales del chip (coretemp: high=94°C, crit=100°C).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HOME/ai-lab/logs/cpu-temp.log"
NOTIFY_SCRIPT="$HOME/ai-lab/scripts/telegram-notify.sh"
ENV_FILE="$SCRIPT_DIR/.env"

WARN_C=80
CRIT_C=90

mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1
echo "=== cpu-temp-monitor $(date -u '+%Y-%m-%d %H:%M UTC') ==="

PUSH_URL=""
if [[ -f "$ENV_FILE" ]]; then
  PUSH_URL=$(grep -E '^CPU_TEMP_KUMA_PUSH_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
fi

if ! command -v sensors >/dev/null 2>&1; then
  echo "[ERROR] lm-sensors no instalado"
  exit 1
fi

# Extrae la lectura real (primer valor de cada línea Package/Core).
# OJO: cada línea también tiene "(high = +94.0°C, crit = +100.0°C)" — esos
# son umbrales del chip, NO lecturas, y no deben entrar al cálculo del máximo.
# awk corta en el primer "(" para descartar los umbrales antes de buscar el número.
MAX_TEMP=$(sensors -A coretemp-isa-0000 2>/dev/null \
  | grep -E '^(Package id 0|Core [0-9]+):' \
  | awk -F'(' '{print $1}' \
  | grep -oP '\+\d+\.\d+(?=°C)' \
  | tr -d '+' \
  | sort -n | tail -1)

if [[ -z "$MAX_TEMP" ]]; then
  echo "[ERROR] no se pudo leer coretemp"
  STATUS="down"
  MSG="cpu-temp-monitor: lectura de sensores falló"
else
  MAX_INT=${MAX_TEMP%.*}
  echo "  Temp máxima detectada: ${MAX_TEMP}°C"
  if (( MAX_INT >= CRIT_C )); then
    STATUS="down"
    MSG="CPU a ${MAX_TEMP}°C — CRÍTICO (umbral ${CRIT_C}°C, chip crit=100°C)"
  elif (( MAX_INT >= WARN_C )); then
    STATUS="up"
    MSG="CPU a ${MAX_TEMP}°C — sobre umbral de warning (${WARN_C}°C)"
  else
    STATUS="up"
    MSG="CPU a ${MAX_TEMP}°C — normal"
  fi
fi

if [[ -n "$PUSH_URL" ]]; then
  curl -sS --max-time 10 "${PUSH_URL}?status=${STATUS}&msg=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$MSG")&ping=" \
    -o /dev/null || echo "[WARN] push a Kuma falló"
else
  echo "[WARN] CPU_TEMP_KUMA_PUSH_URL no configurado en $ENV_FILE — solo log local"
fi

if [[ -n "${MAX_INT:-}" ]] && (( MAX_INT >= CRIT_C )); then
  [[ -x "$NOTIFY_SCRIPT" ]] && "$NOTIFY_SCRIPT" "$MSG" "CRITICAL" 2>/dev/null || true
fi

echo "=== fin $(date -u '+%H:%M UTC') ==="
