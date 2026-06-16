#!/bin/bash
# Limpia heartbeats zombies tras reinicio inesperado.
# Corre al boot con @reboot, espera a que Postgres esté listo.

MAX_WAIT=120
WAITED=0

until docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "SELECT 1" &>/dev/null; do
  sleep 5
  WAITED=$((WAITED + 5))
  if [ $WAITED -ge $MAX_WAIT ]; then
    echo "$(date): timeout esperando Postgres — abortando boot cleanup"
    exit 1
  fi
done

docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE heartbeat_runs
SET status = 'failed',
    error = 'Proceso interrumpido por reinicio del servidor',
    finished_at = NOW()
WHERE status IN ('running', 'queued')
  AND stdout_excerpt IS NULL;
" 2>/dev/null

echo "$(date): boot cleanup completado"
