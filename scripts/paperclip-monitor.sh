#!/usr/bin/env bash
# paperclip-monitor.sh — Monitor de salud de Paperclip (no-agent, cero tokens LLM)
# Registrar en Hermes: hermes cron create "0 */4 * * *" --name "Paperclip Monitor" \
#                        --no-agent --script paperclip-monitor.sh
# NOTA: copiar a ~/.hermes/scripts/ (Hermes rechaza symlinks — ejecuta desde ahí)

set -euo pipefail

ENV_FILE="${HOME}/.hermes/.env"
BASE_URL="http://${PAPERCLIP_HOST:-100.79.30.67}:3100"
TIMEOUT=10

# Leer API key desde .env
KEY=$(grep '^PCP_BOARD_KEY=' "$ENV_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
if [[ -z "$KEY" ]]; then
  echo "ERROR: PCP_BOARD_KEY no encontrada en $ENV_FILE"
  exit 1
fi

AUTH="Authorization: Bearer $KEY"
NOW=$(date '+%Y-%m-%d %H:%M:%S')

# ── Health check ──────────────────────────────────────────────────────────────
HEALTH=$(curl -sf --max-time "$TIMEOUT" "$BASE_URL/api/health" 2>/dev/null) || HEALTH=""

echo "📊 **Paperclip Monitor** — $NOW"
echo ""

if [[ -z "$HEALTH" ]]; then
  echo "**Salud:** ⚠️ Paperclip no responde en $BASE_URL"
  exit 0
fi

HEALTH_STATUS=$(HEALTH_DATA="$HEALTH" python3 << 'PYEOF'
import json, os
try:
    d = json.loads(os.environ['HEALTH_DATA'])
    print(d.get('status', 'unknown'))
except:
    print('unknown')
PYEOF
)
echo "**Salud:** $HEALTH_STATUS"

# ── Empresas desde DB (dinámico, no hardcodeado) ───────────────────────────────
COMPANIES=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA \
  -c "SELECT id, name FROM companies ORDER BY name;" 2>/dev/null) || COMPANIES=""

if [[ -z "$COMPANIES" ]]; then
  echo "Sin acceso a DB de empresas."
  exit 0
fi

# ── Por empresa ───────────────────────────────────────────────────────────────
while IFS='|' read -r CID COMPANY; do
  [[ -z "$CID" ]] && continue
  CID=$(echo "$CID" | xargs)
  COMPANY=$(echo "$COMPANY" | xargs)

  echo ""
  echo "**$COMPANY**"

  # Agentes
  AGENTS_JSON=$(curl -sf --max-time "$TIMEOUT" \
    -H "$AUTH" "$BASE_URL/api/companies/$CID/agents" 2>/dev/null) || AGENTS_JSON=""

  if [[ -z "$AGENTS_JSON" ]]; then
    echo "Sin actividad en las últimas 4 horas."
    continue
  fi

  AGENT_LINES=$(AGENTS_DATA="$AGENTS_JSON" python3 << 'PYEOF'
import json, os
data = json.loads(os.environ['AGENTS_DATA'])
agents = data if isinstance(data, list) else data.get('agents', data.get('data', []))
lines = []
for a in agents:
    name = a.get('name', '?')
    status = a.get('status', '?')
    model = (a.get('adapterConfig') or a.get('adapter_config') or {}).get('model', '')
    model = model.replace('opencode-go/', '').replace('opencode-zen/', 'zen/').replace('xai-hermes/', 'grok/').replace('opencode/', '')
    if len(model) > 22:
        model = model[:22] + '…'
    prefix = '⚠️ ' if status in ('error', 'paused') else '- '
    suffix = ' — **paused**' if status == 'paused' else ' — **error**' if status == 'error' else ''
    lines.append(f"{prefix}{name} — `{status}` | {model}{suffix}")
print('\n'.join(lines) if lines else 'Sin agentes.')
PYEOF
  )
  echo "Agentes:"
  echo "$AGENT_LINES"

  # Heartbeat runs
  RUNS_JSON=$(curl -sf --max-time "$TIMEOUT" \
    -H "$AUTH" "$BASE_URL/api/companies/$CID/heartbeat-runs?limit=10" 2>/dev/null) || RUNS_JSON=""

  RUN_SUMMARY=$(RUNS_DATA="$RUNS_JSON" AGENTS_DATA="$AGENTS_JSON" python3 << 'PYEOF'
import json, os
try:
    raw = os.environ.get('RUNS_DATA', '')
    if not raw:
        print("Sin runs recientes.")
    else:
        agents_list = json.loads(os.environ.get('AGENTS_DATA', '[]'))
        id_to_name = {a['id']: a.get('name', '?') for a in agents_list if isinstance(a, dict)}
        data = json.loads(raw)
        runs = data if isinstance(data, list) else data.get('runs', data.get('data', []))
        total = len(runs)
        if total == 0:
            print("Sin runs recientes.")
        else:
            last = runs[0]
            last_time = last.get('startedAt') or last.get('createdAt') or ''
            if last_time:
                try:
                    from datetime import datetime
                    dt = datetime.fromisoformat(last_time.replace('Z', '+00:00'))
                    last_time = dt.strftime('%H:%M')
                except:
                    last_time = last_time[:16]
            agent = id_to_name.get(last.get('agentId', ''), '?')
            status = last.get('status', '?')
            print(f"{total} — Último: {agent} `{status}` {last_time}")
except Exception as e:
    print(f"(error: {e})")
PYEOF
  )
  echo "Runs recientes: $RUN_SUMMARY"

  # Issues activos
  ISSUES_JSON=$(curl -sf --max-time "$TIMEOUT" \
    -H "$AUTH" "$BASE_URL/api/companies/$CID/issues?status=todo,in_progress,in_review,blocked&limit=10" 2>/dev/null) || ISSUES_JSON=""

  ISSUE_SUMMARY=$(ISSUES_DATA="$ISSUES_JSON" python3 << 'PYEOF'
import json, os
try:
    raw = os.environ.get('ISSUES_DATA', '')
    if not raw:
        print("0")
    else:
        data = json.loads(raw)
        issues = data if isinstance(data, list) else data.get('issues', data.get('data', []))
        total = len(issues)
        if total == 0:
            print("0")
        else:
            keys = [i.get('identifier') or i.get('key') or '' for i in issues[:5]]
            keys = [k for k in keys if k]
            print(f"{total} — {', '.join(keys)}" if keys else str(total))
except Exception as e:
    print(f"(error: {e})")
PYEOF
  )
  echo "Issues activos: $ISSUE_SUMMARY"

  # Dashboard / presupuesto
  DASH_JSON=$(curl -sf --max-time "$TIMEOUT" \
    -H "$AUTH" "$BASE_URL/api/companies/$CID/dashboard" 2>/dev/null) || DASH_JSON=""

  BUDGET=$(DASH_DATA="$DASH_JSON" python3 << 'PYEOF'
import json, os
try:
    raw = os.environ.get('DASH_DATA', '')
    if not raw:
        print("N/D")
    else:
        data = json.loads(raw)
        costs = data.get('costs', {})
        spent_cents = costs.get('monthSpendCents', 0)
        limit_cents = costs.get('monthBudgetCents', 0)
        spent = f"${spent_cents/100:.2f}"
        limit = f"${limit_cents/100:.2f}" if limit_cents else "sin límite"
        print(f"{spent} / {limit}")
except:
    print("N/D")
PYEOF
  )
  echo "Presupuesto: $BUDGET"
done <<< "$COMPANIES"
