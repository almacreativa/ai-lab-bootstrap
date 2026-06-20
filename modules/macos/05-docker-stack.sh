#!/bin/bash
# Módulo 05 (macOS) — Docker: red ai-lab, Portainer, repos, Hermes launchd service

log "Paso 5/6 — Docker stack..."

if ! docker info &>/dev/null; then
  warn "Docker Desktop no está corriendo. Abriéndolo..."
  open -a Docker
  log "Esperando a que Docker Desktop levante (hasta 60s)..."
  for i in $(seq 1 30); do
    docker info &>/dev/null && break
    sleep 2
  done
  docker info &>/dev/null || err "Docker Desktop no respondió. Ábrelo manualmente y vuelve a correr este módulo."
fi

mkdir -p "$LAB_DIR/repos"
mkdir -p "$LAB_DIR/logs"

# Carpeta de conocimiento compartido — sincronizada con Syncthing, usada por Hermes
mkdir -p "$LAB_DIR/knowledge/projects"
mkdir -p "$LAB_DIR/knowledge/research"
mkdir -p "$LAB_DIR/knowledge/daily"
log "Estructura knowledge/ creada en $LAB_DIR/knowledge/"

# Clonar repos base
if [ ! -d "$LAB_DIR/repos/paperclip/.git" ]; then
  git clone https://github.com/paperclipai/paperclip.git "$LAB_DIR/repos/paperclip"
  log "Paperclip clonado."
else
  log "Paperclip ya existe, saltando."
fi

if [ "$INSTALL_HERMES" = "true" ]; then
  if [ ! -d "$LAB_DIR/repos/hermes-agent/.git" ]; then
    git clone https://github.com/NousResearch/hermes-agent.git "$LAB_DIR/repos/hermes-agent"
    log "Hermes-agent clonado."
  else
    log "Hermes-agent ya existe, saltando."
  fi

  # Build del frontend (genera hermes_cli/web_dist/)
  if [ ! -f "$LAB_DIR/repos/hermes-agent/hermes_cli/web_dist/index.html" ]; then
    log "Compilando frontend de Hermes..."
    cd "$LAB_DIR/repos/hermes-agent/web"
    npm install --silent
    npm run build
    cd -
    log "Frontend de Hermes compilado."
  else
    log "Frontend de Hermes ya compilado, saltando."
  fi

  # Hermes como LaunchAgent (equivalente macOS de systemd --user)
  HERMES_PLIST_SRC="$SCRIPT_DIR/configs/com.almacreativa.hermes.plist"
  HERMES_START_SRC="$SCRIPT_DIR/configs/hermes-start-macos.sh"
  HERMES_PLIST_DST="$HOME/Library/LaunchAgents/com.almacreativa.hermes.plist"

  mkdir -p "$HOME/Library/LaunchAgents"

  if [ -f "$HERMES_PLIST_DST" ]; then
    log "com.almacreativa.hermes.plist ya existe — no se sobreescribe."
  elif [ -f "$HERMES_PLIST_SRC" ]; then
    NODE_VERSION_DIR=$(basename "$(dirname "$(dirname "$(command -v node)")")" 2>/dev/null || echo "v24.0.0")
    sed "s|{{HOME}}|$HOME|g; s|{{NODE_VERSION}}|$NODE_VERSION_DIR|g" "$HERMES_PLIST_SRC" > "$HERMES_PLIST_DST"
    log "LaunchAgent de Hermes instalado en $HERMES_PLIST_DST (Node $NODE_VERSION_DIR)"
  else
    warn "configs/com.almacreativa.hermes.plist no encontrado — instalar manualmente."
  fi

  if [ -f /usr/local/bin/hermes-start.sh ]; then
    log "hermes-start.sh ya existe — no se sobreescribe."
  elif [ -f "$HERMES_START_SRC" ]; then
    sed "s|{{HOME}}|$HOME|g" "$HERMES_START_SRC" | sudo tee /usr/local/bin/hermes-start.sh > /dev/null
    sudo chmod +x /usr/local/bin/hermes-start.sh
    log "hermes-start.sh instalado en /usr/local/bin/"
  else
    warn "configs/hermes-start-macos.sh no encontrado — instalar manualmente."
  fi
fi

# Red Docker dedicada para el lab
if ! docker network inspect ai-lab &>/dev/null; then
  docker network create --driver bridge --subnet 172.30.0.0/24 ai-lab
  log "Red Docker 'ai-lab' creada (172.30.0.0/24)."
else
  log "Red ai-lab ya existe."
fi

# Portainer
if ! docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
  docker run -d \
    --name portainer \
    --restart unless-stopped \
    -p 8000:8000 \
    -p 9443:9443 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  log "Portainer arrancado en :9443"
else
  log "Portainer ya existe."
fi

# SearXNG — motor de búsqueda self-hosted, backend nativo de Hermes
if ! docker ps -a --format '{{.Names}}' | grep -q "^searxng$"; then
  docker run -d \
    --name searxng \
    --restart unless-stopped \
    -p 127.0.0.1:8080:8080 \
    --network ai-lab \
    searxng/searxng:latest
  log "SearXNG arrancado en localhost:8080."
  warn "Agregar SEARXNG_URL=http://localhost:8080 a ~/.env_agents para que Hermes lo use."
else
  log "SearXNG ya existe."
fi

# Scripts operativos del lab
mkdir -p "$LAB_DIR/scripts"

if [ -f "$LAB_DIR/scripts/lab-session.sh" ]; then
  log "lab-session.sh ya existe — no se sobreescribe."
else
cat > "$LAB_DIR/scripts/lab-session.sh" << 'TMUXEOF'
#!/bin/bash
SESSION="lab"
BOOT_MODE=false
[[ "$1" == "--boot" ]] && BOOT_MODE=true

if tmux has-session -t "$SESSION" 2>/dev/null; then
  if ! $BOOT_MODE; then tmux attach-session -t "$SESSION"; fi
  exit 0
fi

tmux new-session -d -s "$SESSION" -n "trabajo" -c "$HOME"
tmux new-window -t "$SESSION" -n "hermes" -c "$HOME"
tmux new-window -t "$SESSION" -n "paperclip" -c "$HOME"
tmux new-window -t "$SESSION" -n "monitor" -c "$HOME"
tmux send-keys -t "$SESSION:monitor" "htop" Enter
tmux select-window -t "$SESSION:trabajo"

if ! $BOOT_MODE; then tmux attach-session -t "$SESSION"; fi
TMUXEOF
chmod +x "$LAB_DIR/scripts/lab-session.sh"
fi

# Watchdog: mata heartbeats zombies de Paperclip cada 15 minutos
if [ -f "$LAB_DIR/scripts/paperclip-watchdog.sh" ]; then
  log "paperclip-watchdog.sh ya existe — no se sobreescribe."
else
cat > "$LAB_DIR/scripts/paperclip-watchdog.sh" << 'WDEOF'
#!/bin/bash
ZOMBIES=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -t -c "
SELECT COUNT(*) FROM heartbeat_runs
WHERE status = 'running' AND stdout_excerpt IS NULL
  AND started_at < NOW() - INTERVAL '10 minutes';
" 2>/dev/null | tr -d ' ')

if [ "$ZOMBIES" -gt "0" ] 2>/dev/null; then
  docker exec paperclip-server-1 sh -c \
    "kill \$(cat /proc/*/cmdline 2>/dev/null | tr '\0\n' '  ' | grep -o '[0-9]* /usr/local/bin/opencode' | awk '{print \$1}') 2>/dev/null" 2>/dev/null
  docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
    UPDATE heartbeat_runs SET status='failed',
    error='Watchdog: proceso colgado >10min sin output', finished_at=NOW()
    WHERE status='running' AND stdout_excerpt IS NULL
    AND started_at < NOW() - INTERVAL '10 minutes';" 2>/dev/null
  echo "$(date): watchdog eliminó $ZOMBIES zombie(s)"
fi
WDEOF
chmod +x "$LAB_DIR/scripts/paperclip-watchdog.sh"
fi

# Boot cleanup: limpia zombies en DB tras reinicio inesperado
if [ -f "$LAB_DIR/scripts/paperclip-boot-cleanup.sh" ]; then
  log "paperclip-boot-cleanup.sh ya existe — no se sobreescribe."
else
cat > "$LAB_DIR/scripts/paperclip-boot-cleanup.sh" << 'BCEOF'
#!/bin/bash
MAX_WAIT=120; WAITED=0
until docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "SELECT 1" &>/dev/null; do
  sleep 5; WAITED=$((WAITED+5))
  [ $WAITED -ge $MAX_WAIT ] && echo "$(date): timeout esperando Postgres" && exit 1
done
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE heartbeat_runs SET status='failed',
error='Proceso interrumpido por reinicio del servidor', finished_at=NOW()
WHERE status IN ('running','queued') AND stdout_excerpt IS NULL;" 2>/dev/null
echo "$(date): boot cleanup completado"
BCEOF
chmod +x "$LAB_DIR/scripts/paperclip-boot-cleanup.sh"
fi

# Cron jobs — macOS todavía soporta crontab (aunque Apple recomienda launchd)
CRON_CHANGED=false
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

add_cron_if_missing() {
  local pattern="$1" entry="$2"
  if ! echo "$CURRENT_CRON" | grep -q "$pattern"; then
    CURRENT_CRON="$CURRENT_CRON
$entry"
    CRON_CHANGED=true
  fi
}

add_cron_if_missing "paperclip-watchdog" "*/15 * * * * $LAB_DIR/scripts/paperclip-watchdog.sh >> $LAB_DIR/scripts/watchdog.log 2>&1"
add_cron_if_missing "paperclip-boot-cleanup" "@reboot $LAB_DIR/scripts/paperclip-boot-cleanup.sh >> $LAB_DIR/scripts/watchdog.log 2>&1"
add_cron_if_missing "lab-session.sh --boot" "@reboot sleep 15 && $LAB_DIR/scripts/lab-session.sh --boot"
add_cron_if_missing "find /tmp -name" "0 * * * * find /tmp -name '*.so' -mmin +60 -not -lname '*.so' -delete 2>/dev/null"

if [ "$CRON_CHANGED" = true ]; then
  echo "$CURRENT_CRON" | crontab -
  log "Cron jobs del lab agregados (sin tocar los existentes)."
  warn "macOS no soporta '@reboot' en crontab por defecto sin permisos de Full Disk Access para cron/launchd — ver pasos manuales."
else
  log "Cron jobs del lab ya existen — no se modifican."
fi
log "Scripts operativos verificados en $LAB_DIR/scripts/"

# Alias lab en shell rc
SHELL_RC="$HOME/.zshrc"
[ "$(basename "$SHELL")" = "bash" ] && SHELL_RC="$HOME/.bash_profile"
grep -q "alias lab=" "$SHELL_RC" 2>/dev/null || \
  echo "alias lab=\"$LAB_DIR/scripts/lab-session.sh\"" >> "$SHELL_RC"

warn "Antes de iniciar servicios, completar los secrets usando los templates en: $SCRIPT_DIR/templates/"

log "Módulo 05 completo."
