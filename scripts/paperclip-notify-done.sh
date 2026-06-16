#!/bin/bash
set -euo pipefail

# Wrapper: runs poll, formats results for human reading.
# Exit 0 with output = new completions found.
# Exit 0 no output = nothing new.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
results=$("$SCRIPT_DIR/paperclip-poll-done.sh" --quiet 2>/dev/null)

if [ -z "$results" ]; then
  exit 0
fi

count=$(echo "$results" | wc -l)
echo "📋 $count issue(s) completados:"
echo ""

echo "$results" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        company = d.get('company', '?')
        ident = d.get('identifier', '?')
        title = d.get('title', '')[:60]
        priority = d.get('priority', '')
        ts = d.get('completedAt', '')[:16].replace('T', ' ')
        print(f'  • [{company}] {ident}: {title} ({priority}) — {ts}')
    except json.JSONDecodeError:
        continue
"
