#!/usr/bin/env bash
# guard-lib.sh — funciones compartidas para los guards del lab
# Source este archivo al inicio de cada guard script.
# Usa archivos temporales para contadores (evita pérdida en subshells de pipes).

GUARD_OUTPUT_DIR="${HOME}/ai-lab/logs/guard"
GUARD_NOTIFY_SCRIPT="${HOME}/ai-lab/scripts/telegram-notify.sh"

mkdir -p "$GUARD_OUTPUT_DIR"

_GUARD_NAME=""
_GUARD_TMPDIR=""

guard_init() {
  _GUARD_NAME="$1"
  _GUARD_TMPDIR=$(mktemp -d)
  echo "0" > "$_GUARD_TMPDIR/ok"
  echo "0" > "$_GUARD_TMPDIR/gap"
  echo "0" > "$_GUARD_TMPDIR/drift"
  echo "[]" > "$_GUARD_TMPDIR/checks"
}

_inc() {
  local file="$_GUARD_TMPDIR/$1"
  local val
  val=$(cat "$file")
  echo $((val + 1)) > "$file"
}

_add_check() {
  local json_entry="$1"
  python3 -c "
import json
with open('$_GUARD_TMPDIR/checks') as f:
    checks = json.load(f)
checks.append(json.loads('$json_entry'))
with open('$_GUARD_TMPDIR/checks', 'w') as f:
    json.dump(checks, f)
"
}

report_ok() {
  local type="$1" name="$2"
  _inc ok
  _add_check "{\"type\":\"$type\",\"name\":\"$name\",\"status\":\"ok\"}"
}

report_gap() {
  local type="$1" name="$2" detail="$3"
  _inc gap
  _add_check "{\"type\":\"$type\",\"name\":\"$name\",\"status\":\"gap\",\"detail\":\"$detail\"}"
  echo "  GAP: [$type] $name — $detail"
}

report_drift() {
  local type="$1" name="$2" expected="$3" actual="$4"
  _inc drift
  _add_check "{\"type\":\"$type\",\"name\":\"$name\",\"status\":\"drift\",\"expected\":\"$expected\",\"actual\":\"$actual\"}"
  echo "  DRIFT: [$type] $name — esperado: $expected, actual: $actual"
}

emit_json() {
  local ok gap drift checks
  ok=$(cat "$_GUARD_TMPDIR/ok")
  gap=$(cat "$_GUARD_TMPDIR/gap")
  drift=$(cat "$_GUARD_TMPDIR/drift")
  checks=$(cat "$_GUARD_TMPDIR/checks")
  local output_file="$GUARD_OUTPUT_DIR/${_GUARD_NAME}-$(date +%Y-%m-%d).json"

  python3 -c "
import json
report = {
    'guard': '${_GUARD_NAME}',
    'timestamp': '$(date -Iseconds)',
    'hostname': '$(hostname)',
    'summary': {'ok': ${ok}, 'gap': ${gap}, 'drift': ${drift}},
    'checks': json.loads('''${checks}''')
}
with open('${output_file}', 'w') as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
print('${output_file}')
"
}

emit_telegram() {
  local ok gap drift checks
  ok=$(cat "$_GUARD_TMPDIR/ok")
  gap=$(cat "$_GUARD_TMPDIR/gap")
  drift=$(cat "$_GUARD_TMPDIR/drift")
  checks=$(cat "$_GUARD_TMPDIR/checks")
  local total=$((ok + gap + drift))
  local msg=""

  if [ "$gap" -eq 0 ] && [ "$drift" -eq 0 ]; then
    msg="Guard ${_GUARD_NAME}: ${ok}/${total} OK"
    if [ -x "$GUARD_NOTIFY_SCRIPT" ]; then
      "$GUARD_NOTIFY_SCRIPT" "$msg" INFO 2>/dev/null || true
    fi
  else
    local details
    details=$(python3 -c "
import json
checks = json.loads('''${checks}''')
lines = []
for c in checks:
    if c['status'] == 'gap':
        lines.append(f\"  GAP: {c['type']}/{c['name']} — {c.get('detail','')}\")
    elif c['status'] == 'drift':
        lines.append(f\"  DRIFT: {c['type']}/{c['name']} — {c.get('expected','')} vs {c.get('actual','')}\")
print('\n'.join(lines[:10]))
")
    msg="Guard ${_GUARD_NAME}: ${gap} GAPs, ${drift} DRIFTs (de ${total})
${details}"
    if [ -x "$GUARD_NOTIFY_SCRIPT" ]; then
      "$GUARD_NOTIFY_SCRIPT" "$msg" WARN 2>/dev/null || true
    fi
  fi

  echo "$msg"
}

guard_exit_code() {
  local gap
  gap=$(cat "$_GUARD_TMPDIR/gap" 2>/dev/null || echo "0")
  rm -rf "$_GUARD_TMPDIR"
  [ "$gap" -eq 0 ]
}
