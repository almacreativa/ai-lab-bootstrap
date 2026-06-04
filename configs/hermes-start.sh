#!/bin/bash
# Hermes bare-metal launcher — generado por bootstrap.sh con LAB_USER
set -e

HERMES_BIN="/home/{{LAB_USER}}/.hermes-env/bin/hermes"
HERMES_HOME="/home/{{LAB_USER}}/.hermes"
DASHBOARD_HOST="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
DASHBOARD_PORT="${HERMES_DASHBOARD_PORT:-9119}"
HERMES_WEB_DIST="/home/{{LAB_USER}}/ai-lab/repos/hermes-agent/hermes_cli/web_dist"

export HERMES_HOME
export HERMES_WEB_DIST

echo "[hermes-start] Iniciando dashboard en ${DASHBOARD_HOST}:${DASHBOARD_PORT}"
"$HERMES_BIN" dashboard \
    --host "$DASHBOARD_HOST" \
    --port "$DASHBOARD_PORT" \
    --no-open \
    --insecure \
    &

DASHBOARD_PID=$!
echo "[hermes-start] Dashboard PID: $DASHBOARD_PID"

echo "[hermes-start] Iniciando gateway..."
exec "$HERMES_BIN" gateway run --accept-hooks
