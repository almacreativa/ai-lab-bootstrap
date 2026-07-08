#!/usr/bin/env bash
# maintenance-check.sh — Detecta actualizaciones disponibles con ventana de estabilidad
# Cubre: hermes-agent, opencode, claude (Claude Code), engram, moolmesh, dagu, nlm.
# Filtra releases con <STABILITY_DAYS días, investiga con SearXNG, notifica por Telegram
# y escribe estado estructurado en ops-local/status/maintenance.json.
# Cron sugerido: 0 9 * * 1   (lunes 9am)

set -uo pipefail

STABILITY_DAYS=5
SEARXNG="http://localhost:8080/search"
HERMES_ENV="$HOME/.hermes-env/bin/pip"
OPENCODE_BIN="$HOME/.opencode/bin/opencode"
NOTIFY_SCRIPT="$HOME/ai-lab/scripts/telegram-notify.sh"
LOG="$HOME/ai-lab/logs/maintenance.log"
STATUS_DIR="${LAB_DIR:-$HOME/ai-lab}/ops-local/status"

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

# ── Fuentes de "última versión" (imprimen "version|fecha_iso" o nada) ──
pypi_latest() {
  curl -sf --max-time 10 "https://pypi.org/pypi/$1/json" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
v = d['info']['version']
files = d.get('releases', {}).get(v, []) or d.get('urls', [])
date = files[0]['upload_time'][:19] if files else ''
print(f'{v}|{date}')" 2>/dev/null || true
}

npm_latest() {
  npm view "$1" version time.modified --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f\"{d.get('version','')}|{d.get('time.modified','')[:19]}\")" 2>/dev/null || true
}

github_latest() {
  # Toma el release más reciente cuyo tag sea "v<numero>..." (algunos repos
  # publican otros artefactos con tags distintos en el mismo repo).
  curl -sfL --max-time 10 "https://api.github.com/repos/$1/releases?per_page=15" 2>/dev/null | python3 -c "
import json, sys, re
for r in json.load(sys.stdin):
    tag = r.get('tag_name', '')
    if re.match(r'^v?[0-9]+\.[0-9]+', tag):
        print(f\"{tag.lstrip('v')}|{r.get('published_at','')[:19]}\")
        break" 2>/dev/null || true
}

UPDATES_FOUND=0
REPORT=""
TOOL_STATES=()   # formato: nombre|instalado|disponible|dias|estable

# ── Chequeo genérico de una herramienta ──
check_tool() {
  local name="$1" installed="$2" latest_pair="$3" hint="$4"
  local latest="${latest_pair%%|*}"
  local release_date="${latest_pair#*|}"
  [[ "$release_date" == "$latest_pair" ]] && release_date=""

  echo ""
  echo "[ $name ]"
  echo "  Instalado : ${installed:-desconocido}"
  echo "  Disponible: ${latest:-desconocido}  (publicado: ${release_date:-desconocido})"

  local days=0 stable=false
  if [[ -n "$latest" && -n "$installed" && "$installed" != "desconocido" && "$latest" != "$installed" ]]; then
    days=999
    [[ -n "$release_date" ]] && days=$(days_since "$release_date")
    echo "  Días desde release: $days"

    if [[ "$days" -ge "$STABILITY_DAYS" ]]; then
      stable=true
      echo "  → Pasa ventana de estabilidad ($STABILITY_DAYS días). Investigando..."
      local vuln bug
      vuln=$(search_issues "$name $latest vulnerability security issue")
      bug=$(search_issues "$name $latest bug regression breaking")
      UPDATES_FOUND=$(( UPDATES_FOUND + 1 ))
      REPORT+="
*$name*: \`$installed\` → \`$latest\` (hace ${days}d)
_Actualizar:_ $hint

_Seguridad/issues:_
${vuln}

_Bugs/regresiones:_
${bug}
"
    else
      echo "  → Solo ${days}d desde el release — esperando ventana de ${STABILITY_DAYS}d (faltan $((STABILITY_DAYS - days))d)"
    fi
  else
    echo "  → Al día"
  fi
  TOOL_STATES+=("$name|${installed:-desconocido}|${latest:-}|${days}|${stable}")
}

# ════════════════════════════════════════════════
# Inventario de herramientas
# ════════════════════════════════════════════════

INSTALLED=$("$HERMES_ENV" show hermes-agent 2>/dev/null | grep ^Version | awk '{print $2}' || echo "desconocido")
check_tool "hermes-agent" "$INSTALLED" "$(pypi_latest hermes-agent)" \
  '`pip install --upgrade hermes-agent` + reiniciar servicio'

INSTALLED=$("$OPENCODE_BIN" --version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "desconocido")
check_tool "opencode" "$INSTALLED" "$(npm_latest opencode-ai)" \
  '`curl -fsSL https://opencode.ai/install | bash`'

INSTALLED=$(claude --version 2>/dev/null | grep -oP '^[\d]+\.[\d]+\.[\d]+' | head -1 || echo "desconocido")
check_tool "claude-code" "$INSTALLED" "$(npm_latest @anthropic-ai/claude-code)" \
  '`claude update` (o `npm i -g @anthropic-ai/claude-code`)'

INSTALLED=$(engram --version 2>/dev/null | awk '{print $2}' || echo "desconocido")
check_tool "engram" "$INSTALLED" "$(github_latest Gentleman-Programming/engram)" \
  'descargar release de GitHub (ver bootstrap módulo 04-ai-tools)'

INSTALLED=$(mool --version 2>/dev/null | awk '{print $2}' || echo "desconocido")
check_tool "moolmesh" "$INSTALLED" "$(pypi_latest moolmesh)" \
  '`pipx upgrade moolmesh` + reiniciar servicio moolmesh'

INSTALLED=$(dagu version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "desconocido")
check_tool "dagu" "$INSTALLED" "$(github_latest dagu-org/dagu)" \
  'reinstalar binario — OJO: el installer crea un system service que choca (runbook)'

INSTALLED=$(nlm --version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "desconocido")
check_tool "nlm" "$INSTALLED" "$(pypi_latest notebooklm-mcp-cli)" \
  '`uv tool upgrade notebooklm-mcp-cli` (o pipx upgrade)'

# ════════════════════════════════════════════════
# Resultado final
# ════════════════════════════════════════════════
echo ""
if [[ "$UPDATES_FOUND" -gt 0 ]]; then
  HEADER="🔧 *Mantenimiento del lab — ${UPDATES_FOUND} actualización(es) disponible(s)*

Versiones con ≥${STABILITY_DAYS} días de estabilidad. Revisar antes de actualizar:"
  notify "${HEADER}${REPORT}" "INFO"
  echo "Notificación enviada."
else
  echo "Todo al día o dentro de la ventana de estabilidad. Sin notificación."
fi

# ── Archivo de estado para el aggregator ──
mkdir -p "$STATUS_DIR"
printf '%s\n' "${TOOL_STATES[@]}" | STATUS_FILE="$STATUS_DIR/maintenance.json" python3 -c "
import json, os, sys, datetime
tools = []
all_current = True
for line in sys.stdin.read().splitlines():
    if not line:
        continue
    name, installed, latest, days, stable = (line.split('|') + ['']*5)[:5]
    pending = bool(latest) and latest != installed and installed != 'desconocido'
    if pending:
        all_current = False
    tools.append({
        'tool': name,
        'installed': installed,
        'available': latest or None,
        'update_pending': pending,
        'days_since_release': int(days) if days.isdigit() else None,
        'stable': stable == 'true',
    })
out = {
    'timestamp': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
    'updates_available': [t for t in tools if t['update_pending']],
    'tools': tools,
    'all_current': all_current,
}
with open(os.environ['STATUS_FILE'], 'w') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
" 2>/dev/null || echo "[WARN] no se pudo escribir maintenance.json"

echo "=== fin $(date -u '+%H:%M UTC') ==="
