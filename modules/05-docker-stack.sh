#!/bin/bash
# Módulo 05 — Docker: red ai-lab, Portainer, repos, Hermes service

log "Paso 5/6 — Docker stack..."

mkdir -p "$LAB_DIR/repos"

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

  # Hermes systemd service
  HERMES_SERVICE_SRC="$SCRIPT_DIR/configs/hermes.service"
  HERMES_START_SRC="$SCRIPT_DIR/configs/hermes-start.sh"

  if [ -f /etc/systemd/system/hermes.service ]; then
    log "hermes.service ya existe — no se sobreescribe."
  elif [ -f "$HERMES_SERVICE_SRC" ]; then
    NODE_VERSION=$(node --version 2>/dev/null || echo "v24.16.0")
    sed "s|{{LAB_USER}}|$LAB_USER|g; s|{{NODE_VERSION}}|$NODE_VERSION|g" "$HERMES_SERVICE_SRC" \
      | sudo tee /etc/systemd/system/hermes.service > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable hermes
    log "hermes.service instalado y habilitado (Node $NODE_VERSION)."
  else
    warn "configs/hermes.service no encontrado — instalar manualmente."
  fi

  if [ -f /usr/local/bin/hermes-start.sh ]; then
    log "hermes-start.sh ya existe — no se sobreescribe."
  elif [ -f "$HERMES_START_SRC" ]; then
    sed "s|{{LAB_USER}}|$LAB_USER|g" "$HERMES_START_SRC" \
      | sudo tee /usr/local/bin/hermes-start.sh > /dev/null
    sudo chmod +x /usr/local/bin/hermes-start.sh
    log "hermes-start.sh instalado en /usr/local/bin/"
  else
    warn "configs/hermes-start.sh no encontrado — instalar manualmente."
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
# Escucha solo en localhost:8080 (Hermes lo accede localmente)
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

# Sesión tmux persistente con 4 ventanas predefinidas
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

# Health-check: repara redes Docker faltantes (p. ej. tras un reinicio en frío,
# uptime-kuma puede perder su conexión a mem0_default/paperclip_default y
# reportar Ollama/Mem0 como caídos aunque estén sanos) y reinicia contenedores
# que no respondan en su endpoint HTTP.
if [ -f "$LAB_DIR/scripts/lab-health-check.sh" ]; then
  log "lab-health-check.sh ya existe — no se sobreescribe."
else
cat > "$LAB_DIR/scripts/lab-health-check.sh" << 'HCEOF'
#!/usr/bin/env bash
# lab-health-check.sh — Verifica que cada contenedor del lab esté arriba y
# conectado a las redes Docker que necesita; reconecta/reinicia si no.
# Cron sugerido: @reboot (con sleep) + cada 10-15 min para detectar drift.

set -uo pipefail

LOG="$HOME/ai-lab/logs/lab-health.log"
NOTIFY_SCRIPT="$HOME/ai-lab/scripts/telegram-notify.sh"
ENV_FILE="$HOME/.hermes/.env"

mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1
echo "=== lab-health-check $(date -u '+%Y-%m-%d %H:%M UTC') ==="

CHAT_ID=""
if [[ -f "$ENV_FILE" ]]; then
  CHAT_ID=$(grep -E '^TELEGRAM_CHAT_ID=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
  [[ -z "$CHAT_ID" ]] && \
    CHAT_ID=$(grep -E '^TELEGRAM_ALLOWED_USERS=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | cut -d, -f1 || true)
fi

ISSUES=()

notify() {
  local msg="$1"
  echo "[NOTIFY] $msg"
  if [[ -n "$CHAT_ID" && -x "$NOTIFY_SCRIPT" ]]; then
    TELEGRAM_CHAT_ID="$CHAT_ID" "$NOTIFY_SCRIPT" "$msg" "WARN" 2>/dev/null || true
  fi
}

container_networks() {
  docker inspect "$1" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null \
    | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin).keys()))" 2>/dev/null
}

# Mapa declarativo: contenedor -> redes requeridas (según docs/SERVICIOS.md)
declare -A REQUIRED_NETWORKS=(
  [uptime-kuma]="outline_default mem0_default paperclip_default"
  [mem0]="mem0_default paperclip_default"
  [ollama]="mem0_default"
)

for container in "${!REQUIRED_NETWORKS[@]}"; do
  if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    if docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
      echo "  $container existe pero no está corriendo — iniciando..."
      docker start "$container" >/dev/null 2>&1
      ISSUES+=("$container estaba detenido — se inició")
    else
      echo "  $container no existe — fuera de alcance de este script"
      continue
    fi
  fi

  current=$(container_networks "$container")
  for net in ${REQUIRED_NETWORKS[$container]}; do
    if ! echo " $current " | grep -q " $net "; then
      echo "  $container: falta red $net — conectando..."
      if docker network connect "$net" "$container" 2>&1; then
        ISSUES+=("$container reconectado a red $net")
      else
        ISSUES+=("$container: fallo al conectar a $net")
      fi
    fi
  done
done

# Endpoints HTTP a verificar tras el saneo de redes (host networking)
declare -A HEALTH_URLS=(
  [mem0]="http://127.0.0.1:8765/health"
  [ollama]="http://127.0.0.1:11434/api/tags"
)

for container in "${!HEALTH_URLS[@]}"; do
  url="${HEALTH_URLS[$container]}"
  if ! curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
    echo "  $container: no responde en $url — reiniciando contenedor..."
    docker restart "$container" >/dev/null 2>&1
    ISSUES+=("$container no respondía en $url — se reinició")
  fi
done

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  SUMMARY="🔧 lab-health-check encontró y corrigió:
$(printf '  • %s\n' "${ISSUES[@]}")"
  notify "$SUMMARY"
else
  echo "  Todo sano. Sin acciones."
fi

echo "=== fin $(date -u '+%H:%M UTC') ==="
HCEOF
chmod +x "$LAB_DIR/scripts/lab-health-check.sh"
fi

# ── Dagu (workflow orchestrator — reemplaza crontab) ──
if ! command -v dagu &>/dev/null && [ ! -f "$HOME/.local/bin/dagu" ]; then
  log "Instalando Dagu..."
  curl -sSL https://raw.githubusercontent.com/dagu-org/dagu/main/scripts/installer.sh | bash
  log "Dagu $(dagu version 2>/dev/null || echo 'instalado')."
else
  log "Dagu ya instalado ($(dagu version 2>/dev/null || echo "$HOME/.local/bin/dagu"))."
fi

# Dagu config
mkdir -p "$HOME/.config/dagu/dags"
DAGU_CONFIG_SRC="$SCRIPT_DIR/configs/dagu-config.yaml.example"
DAGU_BASE_SRC="$SCRIPT_DIR/configs/dagu-base.yaml.example"
DAGU_SERVICE_SRC="$SCRIPT_DIR/configs/dagu.service"

if [ ! -f "$HOME/.config/dagu/config.yaml" ] && [ -f "$DAGU_CONFIG_SRC" ]; then
  sed "s|{{LAB_USER}}|$LAB_USER|g" "$DAGU_CONFIG_SRC" > "$HOME/.config/dagu/config.yaml"
  log "Dagu config.yaml creado."
fi

if [ ! -f "$HOME/.config/dagu/base.yaml" ] && [ -f "$DAGU_BASE_SRC" ]; then
  sed "s|{{LAB_USER}}|$LAB_USER|g" "$DAGU_BASE_SRC" > "$HOME/.config/dagu/base.yaml"
  log "Dagu base.yaml creado."
fi

# Copiar DAGs base (no sobreescribe si ya existen)
if [ -d "$SCRIPT_DIR/configs/dagu-dags" ]; then
  for dag in "$SCRIPT_DIR/configs/dagu-dags"/*.yaml; do
    dagname=$(basename "$dag")
    if [ ! -f "$HOME/.config/dagu/dags/$dagname" ]; then
      cp "$dag" "$HOME/.config/dagu/dags/$dagname"
      log "DAG copiado: $dagname"
    fi
  done
  log "DAGs base instalados. Templates (.template) requieren configuración manual."
fi

# Dagu systemd user service
mkdir -p "$HOME/.config/systemd/user"
if [ ! -f "$HOME/.config/systemd/user/dagu.service" ] && [ -f "$DAGU_SERVICE_SRC" ]; then
  sed "s|{{LAB_USER}}|$LAB_USER|g" "$DAGU_SERVICE_SRC" > "$HOME/.config/systemd/user/dagu.service"
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
  systemctl --user daemon-reload
  systemctl --user enable dagu.service
  log "dagu.service instalado y habilitado (systemd user)."
  warn "Iniciar con: systemctl --user start dagu"
else
  log "dagu.service ya existe — no se sobreescribe."
fi

# Crontab mínimo — solo lab-session (todo lo demás va en Dagu)
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

add_cron_if_missing "lab-session.sh --boot" "@reboot sleep 15 && $LAB_DIR/scripts/lab-session.sh --boot"

if [ "$CRON_CHANGED" = true ]; then
  echo "$CURRENT_CRON" | crontab -
  log "Crontab mínimo instalado (solo lab-session @reboot — el resto va en Dagu)."
else
  log "Crontab ya configurado."
fi
log "Scripts operativos verificados en $LAB_DIR/scripts/"

# Alias lab en .bashrc
grep -q "alias lab=" "$HOME/.bashrc" || \
  echo "alias lab=\"$LAB_DIR/scripts/lab-session.sh\"" >> "$HOME/.bashrc"

warn "Antes de iniciar servicios, completar los secrets usando los templates en: $SCRIPT_DIR/templates/"

log "Módulo 05 completo."
