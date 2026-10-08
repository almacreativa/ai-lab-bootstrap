#!/bin/bash
# Hermes launcher (macOS) — generado por bootstrap-macos.sh con HOME
# (install git ≥0.21.x: el web_dist viene dentro del propio install, sin HERMES_WEB_DIST)
set -e

HERMES_BIN="{{HOME}}/.hermes-env/bin/hermes"
HERMES_HOME="{{HOME}}/.hermes"
DASHBOARD_HOST="${HERMES_DASHBOARD_HOST:-127.0.0.1}"
DASHBOARD_PORT="${HERMES_DASHBOARD_PORT:-9119}"

export HERMES_HOME

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
