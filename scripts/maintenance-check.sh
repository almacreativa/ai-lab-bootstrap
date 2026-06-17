#!/usr/bin/env bash
# maintenance-check.sh — Detecta actualizaciones disponibles con ventana de estabilidad
# Verifica hermes-agent y opencode, filtra releases con <5 días, investiga con SearXNG
# Cron sugerido: 0 9 * * 1   (lunes 9am)

set -euo pipefail

STABILITY_DAYS=5
SEARXNG="http://localhost:8080/search"
HERMES_ENV="$HOME/.hermes-env/bin/pip"
OPENCODE_BIN="$HOME/.opencode/bin/opencode"
NOTIFY_SCRIPT="$HOME/ai-lab/scripts/telegram-notify.sh"
LOG="$HOME/ai-lab/logs/maintenance.log"

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "=== maintenance-check $(date -u '+%Y-%m-%d %H:%M UTC') ==="

# ── Leer TELEGRAM_CHAT_ID desde .env (con fallback a TELEGRAM_ALLOWED_USERS) ──
ENV_FILE="$HOME/.hermes/.env"
CHAT_ID=""
if [[ -f "$ENV_FILE" ]]; then
  CHAT_ID=$(grep -E '^TELEGRAM_CHAT_ID=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
  [[ -z "$CHAT_ID" ]] && \
    CHAT_ID=$(grep -E '^TELEGRAM_ALLOWED_USERS=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | cut -d, -f1 || true)
fi

notify() {
  local msg="$1" sev="${2:-INFO}"
  if [[ -n "$CHAT_ID" && -x "$NOTIFY_SCRIPT" ]]; then
    TELEGRAM_CHAT_ID="$CHAT_ID" "$NOTIFY_SCRIPT" "$msg" "$sev" 2>/dev/null || true
  fi
  echo "[NOTIFY/$sev] $msg"
}

# ── Calcular días desde una fecha ISO ──
days_since() {
  local iso="$1"
  local then
  then=$(date -d "${iso%%T*}" +%s 2>/dev/null) || then=$(date -j -f "%Y-%m-%d" "${iso%%T*}" +%s 2>/dev/null) || { echo 999; return; }
  echo $(( ( $(date +%s) - then ) / 86400 ))
}

# ── Buscar menciones de seguridad/bugs en SearXNG ──
search_issues() {
  local query="$1"
  local encoded
  encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query" 2>/dev/null || echo "$query")
  local result
  result=$(curl -sf --max-time 10 \
    "${SEARXNG}?q=${encoded}&format=json&language=en&categories=it,general&time_range=month" \
    2>/dev/null) || { echo "  (SearXNG no disponible)"; return; }

  echo "$result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])[:4]
    if not results:
        print('  Sin resultados relevantes')
    for r in results:
        title = r.get('title','?')[:80]
        url   = r.get('url','')
        print(f'  • {title}')
        print(f'    {url}')
except Exception as e:
    print(f'  (error al parsear: {e})')
" 2>/dev/null || echo "  (error en búsqueda)"
}

UPDATES_FOUND=0
REPORT=""

# ════════════════════════════════════════════════
# 1. hermes-agent
# ════════════════════════════════════════════════
echo ""
echo "[ hermes-agent ]"
INSTALLED_H=$("$HERMES_ENV" show hermes-agent 2>/dev/null | grep ^Version | awk '{print $2}' || echo "desconocido")
LATEST_H=$("$HERMES_ENV" index versions hermes-agent 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "")
RELEASE_DATE_H=$(curl -sf "https://pypi.org/pypi/hermes-agent/${LATEST_H}/json" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); files=d.get('urls',[]); print(files[0]['upload_time'] if files else '')" \
  2>/dev/null || echo "")

echo "  Instalado : $INSTALLED_H"
echo "  Disponible: $LATEST_H  (publicado: ${RELEASE_DATE_H:-desconocido})"

if [[ -n "$LATEST_H" && "$LATEST_H" != "$INSTALLED_H" ]]; then
  DAYS_H=999
  [[ -n "$RELEASE_DATE_H" ]] && DAYS_H=$(days_since "$RELEASE_DATE_H")
  echo "  Días desde release: $DAYS_H"

  if [[ "$DAYS_H" -ge "$STABILITY_DAYS" ]]; then
    echo "  → Pasa ventana de estabilidad ($STABILITY_DAYS días). Investigando..."
    VULN_H=$(search_issues "hermes-agent $LATEST_H vulnerability security issue")
    BUG_H=$(search_issues "hermes-agent $LATEST_H bug regression breaking")
    UPDATES_FOUND=$(( UPDATES_FOUND + 1 ))
    REPORT+="
*hermes-agent*: \`$INSTALLED_H\` → \`$LATEST_H\` (hace ${DAYS_H}d)

_Seguridad/issues:_
${VULN_H}

_Bugs/regresiones:_
${BUG_H}
"
  else
    echo "  → Solo ${DAYS_H}d desde el release — esperando ventana de ${STABILITY_DAYS}d (faltan $((STABILITY_DAYS - DAYS_H))d)"
  fi
else
  echo "  → Al día"
fi

# ════════════════════════════════════════════════
# 2. opencode
# ════════════════════════════════════════════════
echo ""
echo "[ opencode ]"
INSTALLED_OC=$("$OPENCODE_BIN" --version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "desconocido")
NPM_INFO=$(npm view opencode-ai version time.modified --json 2>/dev/null || echo "{}")
LATEST_OC=$(echo "$NPM_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('version',''))" 2>/dev/null || echo "")
RELEASE_DATE_OC=$(echo "$NPM_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('time.modified','')[:19])" 2>/dev/null || echo "")

echo "  Instalado : $INSTALLED_OC"
echo "  Disponible: $LATEST_OC  (publicado: ${RELEASE_DATE_OC:-desconocido})"

if [[ -n "$LATEST_OC" && "$LATEST_OC" != "$INSTALLED_OC" ]]; then
  DAYS_OC=999
  [[ -n "$RELEASE_DATE_OC" ]] && DAYS_OC=$(days_since "$RELEASE_DATE_OC")
  echo "  Días desde release: $DAYS_OC"

  if [[ "$DAYS_OC" -ge "$STABILITY_DAYS" ]]; then
    echo "  → Pasa ventana de estabilidad. Investigando..."
    VULN_OC=$(search_issues "opencode $LATEST_OC vulnerability security issue")
    BUG_OC=$(search_issues "opencode $LATEST_OC bug regression breaking")
    UPDATES_FOUND=$(( UPDATES_FOUND + 1 ))
    REPORT+="
*opencode*: \`$INSTALLED_OC\` → \`$LATEST_OC\` (hace ${DAYS_OC}d)

_Seguridad/issues:_
${VULN_OC}

_Bugs/regresiones:_
${BUG_OC}
"
  else
    echo "  → Solo ${DAYS_OC}d desde el release — esperando ventana de ${STABILITY_DAYS}d (faltan $((STABILITY_DAYS - DAYS_OC))d)"
  fi
else
  echo "  → Al día"
fi

# ════════════════════════════════════════════════
# Resultado final
# ════════════════════════════════════════════════
echo ""
if [[ "$UPDATES_FOUND" -gt 0 ]]; then
  HEADER="🔧 *Mantenimiento del lab — ${UPDATES_FOUND} actualización(es) disponible(s)*

Versiones con ≥${STABILITY_DAYS} días de estabilidad. Revisar antes de actualizar:"
  notify "${HEADER}${REPORT}

_Para actualizar:_
• hermes-agent: \`pip install --upgrade hermes-agent\` + reiniciar servicio
• opencode: \`curl -fsSL https://opencode.ai/install | bash\`" "INFO"
  echo "Notificación enviada."
else
  echo "Todo al día o dentro de la ventana de estabilidad. Sin notificación."
fi

echo "=== fin $(date -u '+%H:%M UTC') ==="
