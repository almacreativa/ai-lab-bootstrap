#!/usr/bin/env bash
# Ingest semanal de knowledge management, parametrizado por empresa (Fase 6 del plan).
#
# Uso:        bash weekly-ingest.sh <company_id>
# Alma:       bash weekly-ingest.sh <company-id>
# Cron:       0 2 * * 0 $HOME/ai-lab/scripts/weekly-ingest.sh <company-id> >> $HOME/ai-lab/logs/ingest-<company-id>.log 2>&1
#
# Config opcional en ~/ai-lab/scripts/.env (NO commitear):
#   TELEGRAM_BOT_TOKEN=...   TELEGRAM_CHAT_ID=...   KUMA_PUSH_URL=https://.../api/push/XXXX
#
# Diseño (decisiones cerradas del plan):
#   - Lock contra ejecución concurrente
#   - Healthcheck de Hermes con reintento a +30min
#   - Si un paso falla: log + notificación + CONTINUAR con el siguiente
#   - Timeout individual por paso
#   - Estado incremental: lo manejan los extractores y skills (.processed.yaml)

set -u

COMPANY_ID="${1:?Uso: weekly-ingest.sh <company_id>}"
LOCK_FILE="/tmp/weekly-ingest-${COMPANY_ID}.lock"
KNOWLEDGE_DIR="$HOME/ai-lab/knowledge/companies/${COMPANY_ID}"

# ── Mapa por empresa ─────────────────────────────────────────────────────────
# LAB_PRIMARY: la empresa operadora del lab. Las sesiones de Claude Code/OpenCode/
# Hermes son fuentes DEL HOST y se atribuyen a ella por defecto (lo etiquetado
# [company:X] lo enruta el clasificador del skill de Hermes).
# CONFIGURAR: ID de la empresa primaria (las sesiones del host se atribuyen a ella)
# y el directorio de deliverables de cada empresa.
LAB_PRIMARY="${LAB_PRIMARY:-changeme-empresa-a}"
case "$COMPANY_ID" in
  changeme-empresa-a) DELIVERABLES_DIR="$HOME/ai-lab/ops/deliverables-empresa-a" ;;
  changeme-empresa-b) DELIVERABLES_DIR="$HOME/ai-lab/ops/deliverables-empresa-b" ;;
  *)                  DELIVERABLES_DIR="$HOME/ai-lab/ops/deliverables-${COMPANY_ID}" ;;
esac
SESSIONS_DIR="$KNOWLEDGE_DIR/sessions"
EXTRACTORS_DIR="$HOME/shared/demos/process_sessions"
HERMES_DASHBOARD="http://localhost:9119"
HERMES_BIN="$HOME/.hermes-env/bin/hermes"   # ruta completa: el cron no tiene hermes en PATH
ZEN_MODEL="opencode/deepseek-v4-flash-free"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
KUMA_PUSH_URL="${KUMA_PUSH_URL:-}"

ERRORS=()
SUMMARY=()

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify_telegram() {
  local msg="$1"
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    curl -sf -m 15 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" -d text="$msg" >/dev/null \
      || log "WARN: fallo el envio de Telegram"
  else
    log "NOTIFY (sin Telegram configurado): $msg"
  fi
}

# Ejecuta un paso con timeout. Si falla: registra, notifica y CONTINÚA.
run_step() {
  local name="$1" timeout_s="$2"; shift 2
  log "PASO: $name (timeout ${timeout_s}s)"
  local start=$SECONDS
  if timeout "$timeout_s" "$@"; then
    log "OK: $name ($((SECONDS - start))s)"
    SUMMARY+=("✅ $name")
  else
    local rc=$?
    log "ERROR: $name fallo (rc=$rc tras $((SECONDS - start))s) — continuando"
    ERRORS+=("$name (rc=$rc)")
    SUMMARY+=("❌ $name")
  fi
}

# ── Lock ─────────────────────────────────────────────────────────────────────
if [ -e "$LOCK_FILE" ]; then
  log "ABORT: lock existente ($LOCK_FILE). ¿Otra instancia corriendo? Si es un lock huérfano, borrarlo a mano."
  exit 1
fi
echo "$$ $(date -Is)" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log "=== Ingest semanal — empresa $COMPANY_ID ==="

# ── Healthcheck de Hermes (reintento a +30min si no responde) ────────────────
if ! curl -sf -m 10 "$HERMES_DASHBOARD" >/dev/null 2>&1; then
  log "Hermes no responde en $HERMES_DASHBOARD — reprogramando a +30min"
  notify_telegram "⚠️ Ingest $COMPANY_ID: Hermes no responde. Reintento en 30 min."
  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --user --on-active=30min "$SCRIPT_DIR/weekly-ingest.sh" "$COMPANY_ID" \
      && log "Reintento programado via systemd-run" \
      || log "WARN: no se pudo programar el reintento — correr a mano"
  fi
  exit 1
fi

mkdir -p "$SESSIONS_DIR"

# ── 1-3. Fuentes de sesiones del HOST: solo para la empresa primaria ─────────
# Las sesiones de CC/OC/Hermes no tienen atribución automática por empresa.
# Default: empresa primaria. El skill de Hermes enruta lo etiquetado [company:X].
if [ "$COMPANY_ID" = "$LAB_PRIMARY" ]; then
  run_step "extractor OpenCode" 300 \
    python3 "$EXTRACTORS_DIR/opencode_extract.py" \
      --company-id "$COMPANY_ID" --output-dir "$SESSIONS_DIR" --since-days 8

  run_step "extractor Claude Code" 600 \
    python3 "$EXTRACTORS_DIR/claude_code_extract.py" \
      --company-id "$COMPANY_ID" --output-dir "$SESSIONS_DIR" --since-days 8

  run_step "hermes-history-ingest" 1800 \
    "$HOME/.hermes-env/bin/hermes" chat --provider opencode-zen --model "$ZEN_MODEL" --max-turns 80 \
      -q "Ejecuta el skill hermes-history-ingest sobre ~/.hermes/sessions/ (últimos 8 días).
          Respeta el estado incremental en ~/ai-lab/knowledge/.state/hermes.processed.yaml.
          Empresas conocidas para clasificar: la empresa primaria (default),
          <company-b-id> (<EmpresaB> — solo sesiones etiquetadas [company:<company-b-id>] o
          claramente sobre <EmpresaB>). Lo administrativo del lab va a lab-insights.md."
else
  log "SKIP extractores de sesiones: ${COMPANY_ID} no es la empresa primaria (fuentes del host → ${LAB_PRIMARY})"
fi

# ── 4. Destilación de deliverables (por empresa) ─────────────────────────────
if [ -d "$DELIVERABLES_DIR" ]; then
  run_step "wiki-ingest deliverables" 1800 \
    "$HOME/.hermes-env/bin/hermes" chat --provider opencode-zen --model "$ZEN_MODEL" --max-turns 60 \
      -q "Ejecuta el skill wiki-ingest sobre ${DELIVERABLES_DIR}/
          con company_id=${COMPANY_ID}. Respeta el estado incremental.
          Output en ~/ai-lab/knowledge/companies/${COMPANY_ID}/patterns.md"
else
  log "SKIP wiki-ingest: no existe $DELIVERABLES_DIR"
fi

# ── 5. Refrescar insights y AGENTS.md de la empresa ─────────────────────────
run_step "refresh insights + AGENTS.md" 1200 \
  "$HOME/.hermes-env/bin/hermes" chat --provider opencode-zen --model "$ZEN_MODEL" --max-turns 40 \
    -q "Lee los archivos nuevos en ${SESSIONS_DIR} (los que no estén reflejados en
        insights.md). Actualiza ${SESSIONS_DIR}/insights.md agregando solo insights
        nuevos (no duplicar; los recurrentes se marcan con contador). Después revisa
        ${KNOWLEDGE_DIR}/AGENTS.md: si hay cambios sustanciales (proyectos nuevos,
        decisiones), actualizalo manteniéndolo bajo 500 palabras."

# ── 6. Ping a Uptime Kuma (dead man's switch) ────────────────────────────────
if [ -n "$KUMA_PUSH_URL" ]; then
  STATUS="up"; [ ${#ERRORS[@]} -gt 0 ] && STATUS="down"
  curl -sf -m 10 "${KUMA_PUSH_URL}?status=${STATUS}&msg=ingest-${COMPANY_ID}" >/dev/null \
    || log "WARN: fallo el ping a Uptime Kuma"
fi

# ── 7. Notificación final ────────────────────────────────────────────────────
NEW_FILES=$(find "$SESSIONS_DIR" -name "*.md" -mtime -1 2>/dev/null | wc -l)
MSG="📊 Ingest semanal — ${COMPANY_ID}
$(printf '%s\n' "${SUMMARY[@]}")
Archivos actualizados hoy: ${NEW_FILES}"
[ ${#ERRORS[@]} -gt 0 ] && MSG="$MSG
⚠️ Errores: ${ERRORS[*]}"

notify_telegram "$MSG"
log "=== Fin del ingest (${#ERRORS[@]} errores) ==="
[ ${#ERRORS[@]} -eq 0 ]
