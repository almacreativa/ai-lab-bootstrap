#!/bin/bash
# Watchdog de Paperclip: mata heartbeats zombies antes de que se acumulen
# Criterio zombie: status=running + sin output + más de 10 minutos corriendo

ZOMBIES=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -t -c "
SELECT COUNT(*) FROM heartbeat_runs
WHERE status = 'running'
  AND stdout_excerpt IS NULL
  AND started_at < NOW() - INTERVAL '10 minutes';
" 2>/dev/null | tr -d ' ')

if [ "$ZOMBIES" -gt "0" ] 2>/dev/null; then
  # Matar procesos opencode colgados en el contenedor
  docker exec paperclip-server-1 sh -c \
    "kill \$(cat /proc/*/cmdline 2>/dev/null | tr '\0\n' '  ' | grep -o '[0-9]* /usr/local/bin/opencode' | awk '{print \$1}') 2>/dev/null" \
    2>/dev/null

  # Marcar zombies como fallidos en DB
  docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
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
