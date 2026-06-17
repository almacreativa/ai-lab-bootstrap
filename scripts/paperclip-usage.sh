#!/usr/bin/env bash
# paperclip-usage.sh — Reporte semanal de consumo de tokens en Paperclip
# Fuente: DB directa (heartbeat_runs.usage_json) — sin API dedicada de usage
# Uso: bash paperclip-usage.sh [días]   (default: 7)
# Registrar en Hermes: hermes cron create "0 8 * * 1" --name "Paperclip Usage Report" \
#                        --no-agent --script paperclip-usage.sh
# NOTA: copiar a ~/.hermes/scripts/ (Hermes rechaza symlinks — ejecuta desde ahí)

set -euo pipefail

DAYS="${1:-7}"
DB_CMD="docker exec paperclip-db-1 psql -U paperclip -d paperclip"
NOW=$(date '+%Y-%m-%d %H:%M')

echo "📈 **Paperclip Usage — últimos ${DAYS} días** — $NOW"
echo ""

# ── Resumen por empresa ────────────────────────────────────────────────────────
echo "**Resumen por empresa**"
$DB_CMD -t -A -F'|' -c "
SELECT
  c.name,
  COUNT(*) as runs,
  SUM((hr.usage_json->>'inputTokens')::bigint) as input_tok,
  SUM((hr.usage_json->>'outputTokens')::bigint) as output_tok,
  SUM((hr.usage_json->>'cachedInputTokens')::bigint) as cached_tok,
  ROUND(SUM((hr.usage_json->>'costUsd')::numeric), 4) as cost_usd
FROM heartbeat_runs hr
JOIN agents a ON hr.agent_id = a.id
JOIN companies c ON a.company_id = c.id
WHERE hr.usage_json IS NOT NULL
  AND hr.started_at > NOW() - INTERVAL '${DAYS} days'
GROUP BY c.name
ORDER BY cost_usd DESC, input_tok DESC;
" 2>/dev/null | while IFS='|' read -r company runs input output cached cost; do
  [[ -z "$company" ]] && continue
  echo "- **$company**: ${runs} runs | in=$input out=$output cached=$cached | \$$cost"
done

echo ""

# ── Distribución por modelo ────────────────────────────────────────────────────
echo "**Por modelo**"
$DB_CMD -t -A -F'|' -c "
SELECT
  usage_json->>'model' as model,
  COUNT(*) as runs,
  SUM((usage_json->>'inputTokens')::bigint) as input_tok,
  SUM((usage_json->>'outputTokens')::bigint) as output_tok,
  ROUND(SUM((usage_json->>'costUsd')::numeric), 4) as cost_usd
FROM heartbeat_runs
WHERE usage_json IS NOT NULL
  AND started_at > NOW() - INTERVAL '${DAYS} days'
GROUP BY model
ORDER BY cost_usd DESC, input_tok DESC;
" 2>/dev/null | while IFS='|' read -r model runs input output cost; do
  [[ -z "$model" ]] && continue
  short=$(echo "$model" | sed 's|opencode-go/||;s|opencode-zen/||;s|opencode/||;s|xai-hermes/||;s|ollama-cloud/||;s|nvidia/||;s|openrouter/||')
  echo "- \`$short\`: ${runs} runs | in=$input out=$output | \$$cost"
done

echo ""

# ── Top 5 agentes por consumo ──────────────────────────────────────────────────
echo "**Top 5 agentes (por tokens de entrada)**"
$DB_CMD -t -A -F'|' -c "
SELECT
  c.name as company,
  a.name as agent,
  COUNT(*) as runs,
  SUM((hr.usage_json->>'inputTokens')::bigint) as input_tok,
  SUM((hr.usage_json->>'outputTokens')::bigint) as output_tok,
  ROUND(SUM((hr.usage_json->>'costUsd')::numeric), 4) as cost_usd
FROM heartbeat_runs hr
JOIN agents a ON hr.agent_id = a.id
JOIN companies c ON a.company_id = c.id
WHERE hr.usage_json IS NOT NULL
  AND hr.started_at > NOW() - INTERVAL '${DAYS} days'
GROUP BY c.name, a.name
ORDER BY input_tok DESC
LIMIT 5;
" 2>/dev/null | while IFS='|' read -r company agent runs input output cost; do
  [[ -z "$agent" ]] && continue
  echo "- $company/$agent: ${runs} runs | in=$input out=$output | \$$cost"
done

echo ""

# ── Tendencia diaria (últimos 7 días) ─────────────────────────────────────────
echo "**Tendencia diaria**"
$DB_CMD -t -A -F'|' -c "
SELECT
  DATE(started_at) as day,
  COUNT(*) as runs,
  SUM((usage_json->>'inputTokens')::bigint) as input_tok,
  SUM((usage_json->>'outputTokens')::bigint) as output_tok,
  ROUND(SUM((usage_json->>'costUsd')::numeric), 4) as cost_usd
FROM heartbeat_runs
WHERE usage_json IS NOT NULL
  AND started_at > NOW() - INTERVAL '7 days'
GROUP BY day
ORDER BY day DESC;
" 2>/dev/null | while IFS='|' read -r day runs input output cost; do
  [[ -z "$day" ]] && continue
  echo "- $day: ${runs} runs | in=$input out=$output | \$$cost"
done

echo ""

# ── Fallos (últimos 7 días) ────────────────────────────────────────────────────
FAIL_COUNT=$($DB_CMD -t -A -c "
SELECT COUNT(*) FROM heartbeat_runs hr
JOIN agents a ON hr.agent_id = a.id
WHERE hr.status = 'failed'
  AND hr.started_at > NOW() - INTERVAL '7 days';
" 2>/dev/null | tr -d ' ')

echo "**Fallos (7 días):** ${FAIL_COUNT:-0} runs fallidos"
if [[ "${FAIL_COUNT:-0}" -gt 0 ]]; then
  $DB_CMD -t -A -F'|' -c "
  SELECT c.name, a.name, COUNT(*) as fails, MAX(hr.error) as last_error
  FROM heartbeat_runs hr
  JOIN agents a ON hr.agent_id = a.id
  JOIN companies c ON a.company_id = c.id
  WHERE hr.status = 'failed'
    AND hr.started_at > NOW() - INTERVAL '7 days'
  GROUP BY c.name, a.name
  ORDER BY fails DESC
  LIMIT 5;
  " 2>/dev/null | while IFS='|' read -r company agent fails error; do
    [[ -z "$agent" ]] && continue
    echo "- $company/$agent: ${fails} fallos — $(echo "${error:-}" | head -c 80)"
  done
fi
