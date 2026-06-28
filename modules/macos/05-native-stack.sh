#!/bin/bash
# Módulo 05 (macOS) — Stack nativo: repos, Paperclip, Hermes launchd, Dagu, scripts

log "Paso 5/6 — Stack nativo..."

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

# ── Build Paperclip nativo ──
if [ "$INSTALL_PAPERCLIP" = "true" ] && [ -d "$LAB_DIR/repos/paperclip" ]; then
  log "Compilando Paperclip..."
  cd "$LAB_DIR/repos/paperclip"
  pnpm install 2>/dev/null
  pnpm run build 2>/dev/null
  cd -
  log "Paperclip compilado."

  # Paperclip LaunchAgent
  PCP_PLIST_SRC="$SCRIPT_DIR/configs/com.almacreativa.paperclip.plist"
  PCP_START_SRC="$SCRIPT_DIR/configs/paperclip-start-macos.sh"
  PCP_PLIST_DST="$HOME/Library/LaunchAgents/com.almacreativa.paperclip.plist"

  if [ -f "$PCP_PLIST_DST" ]; then
    log "com.almacreativa.paperclip.plist ya existe — no se sobreescribe."
  elif [ -f "$PCP_PLIST_SRC" ]; then
    NODE_VERSION_DIR=$(basename "$(dirname "$(dirname "$(command -v node)")")" 2>/dev/null || echo "v24.0.0")
    sed "s|{{HOME}}|$HOME|g; s|{{NODE_VERSION}}|$NODE_VERSION_DIR|g" "$PCP_PLIST_SRC" > "$PCP_PLIST_DST"
    log "LaunchAgent de Paperclip instalado en $PCP_PLIST_DST"
  else
    warn "configs/com.almacreativa.paperclip.plist no encontrado — instalar manualmente."
  fi

  if [ -f /usr/local/bin/paperclip-start.sh ]; then
    log "paperclip-start.sh ya existe — no se sobreescribe."
  elif [ -f "$PCP_START_SRC" ]; then
    sed "s|{{HOME}}|$HOME|g" "$PCP_START_SRC" | sudo tee /usr/local/bin/paperclip-start.sh > /dev/null
    sudo chmod +x /usr/local/bin/paperclip-start.sh
    log "paperclip-start.sh instalado en /usr/local/bin/"
  else
    warn "configs/paperclip-start-macos.sh no encontrado — instalar manualmente."
  fi
fi

# ── Dagu (workflow orchestrator) ──
if ! command -v dagu &>/dev/null && [ ! -f "$HOME/.local/bin/dagu" ]; then
  log "Instalando Dagu..."
  curl -sSL https://raw.githubusercontent.com/dagu-org/dagu/main/scripts/installer.sh | bash
  log "Dagu $(dagu version 2>/dev/null || echo 'instalado')."
else
  log "Dagu ya instalado ($(dagu version 2>/dev/null || echo "$HOME/.local/bin/dagu"))."
fi

mkdir -p "$HOME/.config/dagu/dags"
DAGU_CONFIG_SRC="$SCRIPT_DIR/configs/dagu-config.yaml.example"
DAGU_BASE_SRC="$SCRIPT_DIR/configs/dagu-base.yaml.example"
DAGU_PLIST_SRC="$SCRIPT_DIR/configs/com.almacreativa.dagu.plist"

if [ ! -f "$HOME/.config/dagu/config.yaml" ] && [ -f "$DAGU_CONFIG_SRC" ]; then
  sed "s|{{HOME}}|$HOME|g" "$DAGU_CONFIG_SRC" > "$HOME/.config/dagu/config.yaml"
  log "Dagu config.yaml creado."
fi

if [ ! -f "$HOME/.config/dagu/base.yaml" ] && [ -f "$DAGU_BASE_SRC" ]; then
  sed "s|{{HOME}}|$HOME|g" "$DAGU_BASE_SRC" > "$HOME/.config/dagu/base.yaml"
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

# Dagu LaunchAgent
DAGU_PLIST_DST="$HOME/Library/LaunchAgents/com.almacreativa.dagu.plist"
if [ -f "$DAGU_PLIST_DST" ]; then
  log "com.almacreativa.dagu.plist ya existe — no se sobreescribe."
elif [ -f "$DAGU_PLIST_SRC" ]; then
  NODE_VERSION_DIR=$(basename "$(dirname "$(dirname "$(command -v node)")")" 2>/dev/null || echo "v24.0.0")
  sed "s|{{HOME}}|$HOME|g; s|{{NODE_VERSION}}|$NODE_VERSION_DIR|g" "$DAGU_PLIST_SRC" > "$DAGU_PLIST_DST"
  log "LaunchAgent de Dagu instalado en $DAGU_PLIST_DST"
else
  warn "configs/com.almacreativa.dagu.plist no encontrado — instalar manualmente."
fi

# ── Scripts operativos del lab ──
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

# Watchdog: mata heartbeats zombies de Paperclip (cross-platform)
if [ -f "$LAB_DIR/scripts/paperclip-watchdog.sh" ]; then
  log "paperclip-watchdog.sh ya existe — no se sobreescribe."
else
cat > "$LAB_DIR/scripts/paperclip-watchdog.sh" << 'WDEOF'
#!/bin/bash
if [[ "$(uname)" == "Darwin" ]]; then
  DB_CMD="psql -U paperclip -d paperclip"
else
  DB_CMD="docker exec paperclip-db-1 psql -U paperclip -d paperclip"
fi

ZOMBIES=$($DB_CMD -t -c "
SELECT COUNT(*) FROM heartbeat_runs
WHERE status = 'running' AND stdout_excerpt IS NULL
  AND started_at < NOW() - INTERVAL '10 minutes';
" 2>/dev/null | tr -d ' ')

if [ "$ZOMBIES" -gt "0" ] 2>/dev/null; then
  if [[ "$(uname)" == "Darwin" ]]; then
    pkill -f "opencode" 2>/dev/null || true
  else
    docker exec paperclip-server-1 sh -c \
      "kill \$(cat /proc/*/cmdline 2>/dev/null | tr '\0\n' '  ' | grep -o '[0-9]* /usr/local/bin/opencode' | awk '{print \$1}') 2>/dev/null" 2>/dev/null
  fi
  $DB_CMD -c "
    UPDATE heartbeat_runs SET status='failed',
    error='Watchdog: proceso colgado >10min sin output', finished_at=NOW()
    WHERE status='running' AND stdout_excerpt IS NULL
    AND started_at < NOW() - INTERVAL '10 minutes';" 2>/dev/null
  echo "$(date): watchdog eliminó $ZOMBIES zombie(s)"
fi
WDEOF
chmod +x "$LAB_DIR/scripts/paperclip-watchdog.sh"
fi

# Boot cleanup: limpia zombies en DB tras reinicio inesperado (cross-platform)
if [ -f "$LAB_DIR/scripts/paperclip-boot-cleanup.sh" ]; then
  log "paperclip-boot-cleanup.sh ya existe — no se sobreescribe."
else
cat > "$LAB_DIR/scripts/paperclip-boot-cleanup.sh" << 'BCEOF'
#!/bin/bash
MAX_WAIT=120; WAITED=0

if [[ "$(uname)" == "Darwin" ]]; then
  until pg_isready -U paperclip -d paperclip &>/dev/null; do
    sleep 5; WAITED=$((WAITED+5))
    [ $WAITED -ge $MAX_WAIT ] && echo "$(date): timeout esperando Postgres" && exit 1
  done
  DB_CMD="psql -U paperclip -d paperclip"
else
  until docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "SELECT 1" &>/dev/null; do
    sleep 5; WAITED=$((WAITED+5))
    [ $WAITED -ge $MAX_WAIT ] && echo "$(date): timeout esperando Postgres" && exit 1
  done
  DB_CMD="docker exec paperclip-db-1 psql -U paperclip -d paperclip"
fi

$DB_CMD -c "
UPDATE heartbeat_runs SET status='failed',
error='Proceso interrumpido por reinicio del servidor', finished_at=NOW()
WHERE status IN ('running','queued') AND stdout_excerpt IS NULL;" 2>/dev/null
echo "$(date): boot cleanup completado"
BCEOF
chmod +x "$LAB_DIR/scripts/paperclip-boot-cleanup.sh"
fi

# Health-check: verifica servicios y endpoints (cross-platform)
if [ -f "$LAB_DIR/scripts/lab-health-check.sh" ]; then
  log "lab-health-check.sh ya existe — no se sobreescribe."
else
cat > "$LAB_DIR/scripts/lab-health-check.sh" << 'HCEOF'
#!/usr/bin/env bash
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

if [[ "$(uname)" == "Darwin" ]]; then
  # macOS: verificar servicios launchd y brew
  for svc in com.almacreativa.hermes com.almacreativa.paperclip com.almacreativa.dagu; do
    if ! launchctl list "$svc" &>/dev/null; then
      echo "  $svc no está corriendo — intentando cargar..."
      launchctl load "$HOME/Library/LaunchAgents/${svc}.plist" 2>/dev/null || true
      ISSUES+=("$svc no estaba corriendo — se cargó")
    fi
  done

  if ! brew services list | grep -q "postgresql@17.*started"; then
    echo "  PostgreSQL no está corriendo — iniciando..."
    brew services start postgresql@17 2>/dev/null || true
    ISSUES+=("PostgreSQL no estaba corriendo — se inició")
  fi
else
  # Linux: verificar contenedores Docker y redes
  container_networks() {
    docker inspect "$1" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null \
      | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin).keys()))" 2>/dev/null
  }

  declare -A REQUIRED_NETWORKS=(
    [uptime-kuma]="mem0_default paperclip_default"
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
fi

# Endpoints HTTP a verificar (ambas plataformas)
declare -A HEALTH_URLS=(
  [paperclip]="http://127.0.0.1:3100/api/health"
  [hermes]="http://127.0.0.1:9119"
)

for svc in "${!HEALTH_URLS[@]}"; do
  url="${HEALTH_URLS[$svc]}"
  if ! curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
    echo "  $svc: no responde en $url"
    if [[ "$(uname)" == "Darwin" ]]; then
      launchctl kickstart -k "gui/$(id -u)/com.almacreativa.${svc}" 2>/dev/null || true
    else
      docker restart "$svc" >/dev/null 2>&1 || true
    fi
    ISSUES+=("$svc no respondía en $url — se reinició")
  fi
done

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  SUMMARY="lab-health-check encontró y corrigió:
$(printf '  - %s\n' "${ISSUES[@]}")"
  notify "$SUMMARY"
else
  echo "  Todo sano. Sin acciones."
fi

echo "=== fin $(date -u '+%H:%M UTC') ==="
HCEOF
chmod +x "$LAB_DIR/scripts/lab-health-check.sh"
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

# Alias lab en shell rc
SHELL_RC="$HOME/.zshrc"
[ "$(basename "$SHELL")" = "bash" ] && SHELL_RC="$HOME/.bash_profile"
grep -q "alias lab=" "$SHELL_RC" 2>/dev/null || \
  echo "alias lab=\"$LAB_DIR/scripts/lab-session.sh\"" >> "$SHELL_RC"

warn "Antes de iniciar servicios, completar los secrets usando los templates en: $SCRIPT_DIR/templates/"

log "Módulo 05 completo."
