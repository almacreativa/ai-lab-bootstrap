#!/bin/bash
# Watchdog de Paperclip: dos capas de defensa
#   1. Presión de memoria (>75%): mata todos los opencode activos + alerta Telegram
#   2. Zombies clásicos (status=running >10min sin output): mata + marca failed en DB
# Corre c/15min via Dagu (paperclip-watchdog DAG).

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER="paperclip-server-1"
MEM_ALERT_PCT=75
STATUS_DIR="${LAB_DIR:-$HOME/ai-lab}/ops-local/status"
MEM_PRESSURE=false
OOM_ACTION=false

if [[ "$(uname)" == "Darwin" ]]; then
  DB_CMD="psql -U paperclip -d paperclip"
  IS_DOCKER=false
else
  DB_CMD="docker exec paperclip-db-1 psql -U paperclip -d paperclip"
  IS_DOCKER=true
fi

kill_opencode_procs() {
  if $IS_DOCKER; then
    docker exec "$CONTAINER" sh -c \
      "kill \$(cat /proc/*/cmdline 2>/dev/null | tr '\0\n' '  ' | grep -o '[0-9]* /usr/local/bin/opencode' | awk '{print \$1}') 2>/dev/null" \
      2>/dev/null || true
  else
    pkill -f "opencode" 2>/dev/null || true
  fi
}

# ── Capa 1: presión de memoria ─────────────────────────────────────────────────
if $IS_DOCKER; then
  MEM_PCT=$(docker stats --no-stream --format "{{.MemPerc}}" "$CONTAINER" 2>/dev/null | tr -d '%' | cut -d'.' -f1)
  if [ -n "$MEM_PCT" ] && [ "$MEM_PCT" -ge "$MEM_ALERT_PCT" ] 2>/dev/null; then
    MSG="⚠️ Paperclip memoria alta: ${MEM_PCT}% — matando procesos opencode antes de OOM"
    echo "$(date): $MSG"
    kill_opencode_procs
    "$SCRIPTS_DIR/telegram-notify.sh" "$MSG" WARNING 2>/dev/null || true
    MEM_PRESSURE=true
    OOM_ACTION=true
  fi
fi

# ── Capa 2: zombies clásicos (>10min sin output) ───────────────────────────────
ZOMBIES=$($DB_CMD -t -c "
SELECT COUNT(*) FROM heartbeat_runs
WHERE status = 'running'
  AND stdout_excerpt IS NULL
  AND started_at < NOW() - INTERVAL '10 minutes';
" 2>/dev/null | tr -d ' ')

if [ "$ZOMBIES" -gt "0" ] 2>/dev/null; then
  kill_opencode_procs

  $DB_CMD -c "
    UPDATE heartbeat_runs
    SET status = 'failed',
        error = 'Watchdog: proceso colgado >10min sin output',
        finished_at = NOW()
    WHERE status = 'running'
      AND stdout_excerpt IS NULL
      AND started_at < NOW() - INTERVAL '10 minutes';
  " 2>/dev/null

  echo "$(date): watchdog eliminó $ZOMBIES zombie(s)"
fi

# ── Archivo de estado para el aggregator ──
mkdir -p "$STATUS_DIR"
python3 - "$STATUS_DIR/watchdog.json" "${ZOMBIES:-0}" "$MEM_PRESSURE" "$OOM_ACTION" "${MEM_PCT:-}" << 'PYEOF' 2>/dev/null || echo "[WARN] no se pudo escribir watchdog.json"
import json, sys, datetime
path, zombies, mem_pressure, oom_action, mem_pct = sys.argv[1:6]
out = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "zombies_killed": int(zombies) if zombies.isdigit() else 0,
    "memory_pressure": mem_pressure == "true",
    "oom_action": oom_action == "true",
    "memory_pct": int(mem_pct) if mem_pct.isdigit() else None,
}
with open(path, "w") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
PYEOF
