#!/usr/bin/env bash
# Deploy promptTemplate to Paperclip agents via DB.
# Assembles: Section 1 (execution contract) + Section 2 (company rules) + Section 3 (agent role)
# and writes the result to adapter_config.promptTemplate for each agent.
#
# Usage:
#   bash deploy-agent-prompts.sh all                  # all companies
#   bash deploy-agent-prompts.sh company-a                # all agents in a company (slug from templates dir)
#   bash deploy-agent-prompts.sh company-a content-producer  # single agent
#
# Templates live in ~/ai-lab/knowledge/shared/templates/
# Companies are discovered automatically from prompt-section2-*.md files in the templates dir.

set -euo pipefail

TEMPLATES="${HOME}/ai-lab/knowledge/shared/templates"
S1="${TEMPLATES}/prompt-section1-execution-contract.md"
DB_CONTAINER="paperclip-db-1"
LOG="${HOME}/ai-lab/logs/deploy-agent-prompts.log"

mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

if [ ! -f "$S1" ]; then
  log "ERROR: Section 1 not found: $S1"
  exit 1
fi

COMPANY_FILTER="${1:-all}"
AGENT_FILTER="${2:-}"

# Derive company slug from issue_prefix via lowercase conversion.
# La función se mantiene genérica: convierte prefijo a minúsculas.
# Si se necesita un mapeo especial, agregar casos aquí.
get_company_slug() {
  local prefix="$1"
  echo "$prefix" | tr '[:upper:]' '[:lower:]'
}

get_agent_slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

deploy_agent() {
  local agent_name="$1"
  local agent_id="$2"
  local company_prefix="$3"
  local company_slug
  company_slug=$(get_company_slug "$company_prefix")
  local agent_slug
  agent_slug=$(get_agent_slug "$agent_name")

  local s2="${TEMPLATES}/prompt-section2-${company_slug}.md"
  local s3="${TEMPLATES}/prompt-section3/${company_slug}-${agent_slug}.md"

  if [ ! -f "$s2" ]; then
    log "SKIP $company_prefix/$agent_name: Section 2 not found ($s2)"
    return 1
  fi
  if [ ! -f "$s3" ]; then
    log "SKIP $company_prefix/$agent_name: Section 3 not found ($s3)"
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp /tmp/prompt-XXXXXX.sql)

  local prompt
  prompt="$(cat "$S1")

$(cat "$s2")

$(cat "$s3")"

  python3 -c "
import json, sys
prompt = sys.stdin.read()
json_value = json.dumps(prompt)
agent_id = sys.argv[1]
sql = \"UPDATE agents SET adapter_config = jsonb_set(adapter_config, '{promptTemplate}', '\" + json_value.replace(\"'\", \"''\") + \"'::jsonb) WHERE id = '\" + agent_id + \"';\"
print(sql)
" "$agent_id" <<< "$prompt" > "$tmpfile"

  docker exec -i "$DB_CONTAINER" psql -U paperclip -d paperclip -q < "$tmpfile" 2>&1
  local rc=$?
  rm -f "$tmpfile"

  if [ $rc -eq 0 ]; then
    log "OK $company_prefix/$agent_name ($agent_id)"
  else
    log "FAIL $company_prefix/$agent_name ($agent_id) — rc=$rc"
  fi
  return $rc
}

AGENTS=$(docker exec "$DB_CONTAINER" psql -U paperclip -d paperclip -tA \
  -c "SELECT a.name, a.id, c.issue_prefix FROM agents a JOIN companies c ON c.id = a.company_id ORDER BY c.issue_prefix, a.name;")

ok=0
fail=0

while IFS='|' read -r aname aid prefix; do
  [ -z "$aname" ] && continue
  aname=$(echo "$aname" | xargs)
  aid=$(echo "$aid" | xargs)
  prefix=$(echo "$prefix" | xargs)

  cslug=$(get_company_slug "$prefix")

  if [ "$COMPANY_FILTER" != "all" ] && [ "$cslug" != "$COMPANY_FILTER" ]; then
    continue
  fi

  if [ -n "$AGENT_FILTER" ]; then
    aslug=$(get_agent_slug "$aname")
    if [ "$aslug" != "$AGENT_FILTER" ]; then
      continue
    fi
  fi

  if deploy_agent "$aname" "$aid" "$prefix"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
done <<< "$AGENTS"

log "Done: $ok deployed, $fail failed/skipped"
