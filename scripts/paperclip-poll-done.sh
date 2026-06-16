#!/bin/bash
set -euo pipefail

STATE_DIR="${HOME}/ai-lab/knowledge/.state"
STATE_FILE="${STATE_DIR}/paperclip-poll-done.json"
BASE_URL="http://${PAPERCLIP_HOST:-localhost}:3100/api"
TOKEN=$(grep PCP_BOARD_KEY "${HOME}/.hermes/.env" | cut -d= -f2)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Obtener empresas dinámicamente desde la DB
COMPANIES=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA \
  -c "SELECT id, name FROM companies ORDER BY name;")

mkdir -p "$STATE_DIR"
if [ ! -f "$STATE_FILE" ]; then
  echo '{}' > "$STATE_FILE"
fi

new_count=0

while IFS='|' read -r company_id company_name; do
  [ -z "$company_id" ] && continue
  company_id=$(echo "$company_id" | xargs)
  company_name=$(echo "$company_name" | xargs)

  last_seen=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('$company_id','1970-01-01T00:00:00.000Z'))")

  curl -s -H "Authorization: Bearer $TOKEN" \
    "${BASE_URL}/companies/${company_id}/issues?status=done&limit=50" \
    > "$TMP_DIR/issues.json"

  python3 - "$TMP_DIR/issues.json" "$last_seen" "$company_name" "$company_id" "$STATE_FILE" <<'PYEOF'
import json, sys

issues_file, last_seen, company_name, company_id, state_file = sys.argv[1:6]
issues = json.load(open(issues_file))
new = [i for i in issues if (i.get("completedAt") or "") > last_seen]
new.sort(key=lambda x: x.get("completedAt", ""))

for i in new:
    print(json.dumps({
        "company": company_name,
        "identifier": i.get("identifier", "?"),
        "title": i.get("title", ""),
        "completedAt": i.get("completedAt", ""),
        "agentId": i.get("assigneeAgentId", "unassigned"),
        "priority": i.get("priority", ""),
    }))

if new:
    state = json.load(open(state_file))
    all_completed = [i["completedAt"] for i in issues if i.get("completedAt")]
    state[company_id] = max(all_completed) if all_completed else last_seen
    json.dump(state, open(state_file, "w"), indent=2)
    print(f"__NEW_COUNT__:{len(new)}", file=sys.stderr)
PYEOF

done <<< "$COMPANIES"

if [ "${1:-}" != "--quiet" ]; then
  state_content=$(cat "$STATE_FILE")
  if [ "$state_content" = "{}" ]; then
    echo '{"status":"no_new_completions"}'
  fi
fi
