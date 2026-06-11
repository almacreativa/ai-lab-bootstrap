#!/usr/bin/env bash
# telegram-notify.sh — Envía notificaciones a Telegram
# Lee TELEGRAM_BOT_TOKEN y TELEGRAM_CHAT_ID desde ~/.hermes/.env
# Uso: ./telegram-notify.sh "Mensaje" [CRITICAL|WARNING|INFO]
#
# Variables de entorno (opcionales, sobrescriben .env):
#   TELEGRAM_BOT_TOKEN  — Token del bot (si ~/.hermes/.env no existe o no tiene la key)
#   TELEGRAM_CHAT_ID    — ID del chat (si ~/.hermes/.env no existe o no tiene la key)

set -euo pipefail

# ── Cargar credenciales desde ~/.hermes/.env ──
ENV_FILE="$HOME/.hermes/.env"
if [[ -f "$ENV_FILE" ]]; then
  # Extraer solo las variables necesarias, sin exponer otras
  eval "$(grep -E '^TELEGRAM_(BOT_TOKEN|CHAT_ID)=' "$ENV_FILE" 2>/dev/null || true)"
fi

# ── Validar que tenemos lo mínimo ──
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "[ERROR] TELEGRAM_BOT_TOKEN no definido. Poner en ~/.hermes/.env o como env var." >&2
  exit 1
fi

if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "[ERROR] TELEGRAM_CHAT_ID no definido. Poner en ~/.hermes/.env o como env var." >&2
  exit 1
fi

# ── Parámetros ──
MESSAGE="${1:-Sistema auto-healing: evento detectado.}"
SEVERITY="${2:-INFO}"

# ── Construir payload ──
HOSTNAME="$(hostname 2>/dev/null || echo 'unknown')"
TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

case "$SEVERITY" in
  CRITICAL) EMOJI="🔴" ;;
  WARNING)  EMOJI="🟡" ;;
  *)        EMOJI="🔵" ;;
esac

# Formatear mensaje con metadatos
FORMATTED="*${EMOJI} [${SEVERITY}] ${HOSTNAME}*

${MESSAGE}
⏱ ${TIMESTAMP}
🖥 Auto-healing System"

# ── Enviar ──
curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": $(printf '%s' "$FORMATTED" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'), \"parse_mode\": \"Markdown\"}" 2>&1
