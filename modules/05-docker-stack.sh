#!/bin/bash
# Módulo 05 — Docker: red ai-lab, Portainer, repos, Hermes service

log "Paso 5/6 — Docker stack..."

# H3 — el grupo 'docker' recién agregado en el módulo 01 (usermod -aG) NO está
# activo en ESTA shell (la membresía de grupo se aplica en un login nuevo). En la
# 1ª pasada del bootstrap, invocar docker directo daría 'permission denied' en
# docker.sock y la red ai-lab no se crearía. Detectamos acceso una vez y usamos un
# wrapper: $DOCKER para todas las invocaciones de TIEMPO DE INSTALACIÓN. Los
# 'docker exec' dentro de los scripts generados (watchdog/boot-cleanup/health-check)
# NO se tocan: corren en runtime, cuando el grupo ya está activo.
if docker info >/dev/null 2>&1; then
  DOCKER="docker"
else
  DOCKER="sudo docker"
  warn "docker sin acceso directo (grupo no activo en esta sesión) — usando 'sudo docker'."
fi

mkdir -p "$LAB_DIR/repos"

# Carpeta de conocimiento compartido — sincronizada con Syncthing, usada por Hermes
mkdir -p "$LAB_DIR/knowledge/projects"
mkdir -p "$LAB_DIR/knowledge/research"
mkdir -p "$LAB_DIR/knowledge/daily"
log "Estructura knowledge/ creada en $LAB_DIR/knowledge/"

# Clonar repos base
if should_install paperclip; then
  if [ ! -d "$LAB_DIR/repos/paperclip/.git" ]; then
    git clone https://github.com/paperclipai/paperclip.git "$LAB_DIR/repos/paperclip"
    log "Paperclip clonado."
  else
    log "Paperclip ya existe, saltando."
  fi
  mark_done paperclip
fi

if should_install hermes; then
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
    sed "s|{{LAB_USER}}|$LAB_USER|g; s|{{NODE_VERSION}}|$NODE_VERSION|g; s|{{LAB_BIND_ADDR}}|${LAB_BIND_ADDR:-127.0.0.1}|g" "$HERMES_SERVICE_SRC" \
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
  mark_done hermes
fi

# Red Docker dedicada para el lab
if ! $DOCKER network inspect ai-lab &>/dev/null; then
  $DOCKER network create --driver bridge --subnet 172.30.0.0/24 ai-lab
  log "Red Docker 'ai-lab' creada (172.30.0.0/24)."
else
  log "Red ai-lab ya existe."
fi

# Portainer
if should_install portainer; then
 if ! $DOCKER ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
  $DOCKER run -d \
    --name portainer \
    --restart unless-stopped \
    -p ${LAB_BIND_ADDR:-127.0.0.1}:8000:8000 \
    -p ${LAB_BIND_ADDR:-127.0.0.1}:9443:9443 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  log "Portainer arrancado en :9443"
 else
  log "Portainer ya existe."
 fi
 mark_done portainer
fi

# SearXNG — motor de búsqueda self-hosted, backend nativo de Hermes
# Escucha solo en localhost:8080 (Hermes lo accede localmente)
if should_install searxng; then
 if ! $DOCKER ps -a --format '{{.Names}}' | grep -q "^searxng$"; then
  $DOCKER run -d \
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
 mark_done searxng
fi

# Uptime Kuma — monitoreo de servicios con alertas push
if should_install uptime-kuma; then
 if ! $DOCKER ps -a --format '{{.Names}}' | grep -q "^uptime-kuma$"; then
  $DOCKER run -d \
    --name uptime-kuma \
    --restart unless-stopped \
    -p ${LAB_BIND_ADDR:-127.0.0.1}:3001:3001 \
    -v uptime-kuma-data:/app/data \
    louislam/uptime-kuma:latest
  log "Uptime Kuma arrancado en ${LAB_BIND_ADDR}:3001"
  warn "Con bind a loopback (default), abrir vía túnel SSH: ssh -L 3001:127.0.0.1:3001 <host>. Luego crear usuario admin y configurar monitores."
 else
  log "Uptime Kuma ya existe."
 fi
 mark_done uptime-kuma
fi

# Glance — Centro de Comando (dashboard de estado del lab)
if should_install glance; then
mkdir -p "$LAB_DIR/stacks/glance/config"
if ! $DOCKER ps -a --format '{{.Names}}' | grep -q "^glance$"; then
  if [ ! -f "$LAB_DIR/stacks/glance/config/glance.yml" ]; then
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")
    cat > "$LAB_DIR/stacks/glance/config/glance.yml" << GLANCEEOF
pages:
  - name: Lab
    columns:
      - size: full
        widgets:
          - type: monitor
            title: Servicios
            cache: 1m
            sites:
              - title: Dagu
                url: http://${TS_IP}:8480
              - title: Uptime Kuma
                url: http://${TS_IP}:3001
GLANCEEOF
    log "Glance config base creado — personalizar en $LAB_DIR/stacks/glance/config/glance.yml"
  fi
  # Heredoc SIN comillas en el delimitador para interpolar ${LAB_BIND_ADDR}.
  # El cuerpo no tiene ninguna otra variable $ que escapar.
  cat > "$LAB_DIR/stacks/glance/docker-compose.yml" << GLANCEDCEOF
services:
  glance:
    image: glanceapp/glance
    container_name: glance
    restart: unless-stopped
    ports:
      - "${LAB_BIND_ADDR:-127.0.0.1}:9000:8080"
    volumes:
      - ./config:/app/config:ro
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
GLANCEDCEOF
  cd "$LAB_DIR/stacks/glance"
  $DOCKER compose up -d
  cd -
  log "Glance (Centro de Comando) arrancado en :9000"
else
  log "Glance ya existe."
fi
mark_done glance
fi

# ── Odysseus — Frontend LLM multi-modelo ──
# RECETA VALIDADA EN NODO FRESCO (i5local-l, 2026-08-15): --only odysseus instala
# docker, crea la red 'ai-lab', clona odysseus-dev/odysseus@main, construye la
# imagen y levanta odysseus (:7000, login 200) + chromadb. Unidad default=on.
# Notas de upstream:
#   1) Upstream: el repo canónico es odysseus-dev/odysseus (antes
#      pewdiepie-archdaemon/odysseus, renombrado). NO tiene releases ni tags: la
#      default branch 'dev' es inestable, así que fijamos a 'main' como línea más
#      estable disponible. Override con ODYSSEUS_REF. Cuando el upstream publique
#      una release/tag, cambiar ODYSSEUS_REF a ese tag.
#   2) Red Docker: RECONCILIADA. El template configs/odysseus/docker-compose.yml.example
#      se adjunta a la red externa 'ai-lab' (la que crea este módulo, L~90, donde vive
#      searxng). El compose vivo del host histórico usaba 'ai-lab-net'; en nodo fresco
#      la red canónica es 'ai-lab'.
# El bloque es idempotente y NO levanta nada sin un .env presente (600).
if should_install odysseus; then
  ODYSSEUS_REPO_URL="${ODYSSEUS_REPO_URL:-https://github.com/odysseus-dev/odysseus.git}"
  ODYSSEUS_REF="${ODYSSEUS_REF:-main}"
  # 1) Clonar el repo (build local del compose), fijado a la línea estable
  if [ ! -d "$LAB_DIR/repos/odysseus/.git" ]; then
    git clone --branch "$ODYSSEUS_REF" "$ODYSSEUS_REPO_URL" "$LAB_DIR/repos/odysseus" \
      && log "Odysseus clonado ($ODYSSEUS_REPO_URL @ $ODYSSEUS_REF)." \
      || warn "Odysseus: git clone falló — revisar ODYSSEUS_REPO_URL / ODYSSEUS_REF."
  else
    (cd "$LAB_DIR/repos/odysseus" && git fetch origin "$ODYSSEUS_REF" && git checkout "$ODYSSEUS_REF") \
      && log "Odysseus repo ya existe — actualizado a $ODYSSEUS_REF." \
      || warn "Odysseus: fetch/checkout de $ODYSSEUS_REF falló — revisar repo."
  fi
  # 2) Scaffolding del stack: compose desde template + placeholder de .env
  mkdir -p "$LAB_DIR/stacks/odysseus/config" "$LAB_DIR/data/core/odysseus/data" "$LAB_DIR/data/core/odysseus/logs"
  ODYSSEUS_COMPOSE_SRC="$SCRIPT_DIR/configs/odysseus/docker-compose.yml.example"
  if [ ! -f "$LAB_DIR/stacks/odysseus/docker-compose.yml" ] && [ -f "$ODYSSEUS_COMPOSE_SRC" ]; then
    sed "s|{{LAB_DIR}}|$LAB_DIR|g" "$ODYSSEUS_COMPOSE_SRC" > "$LAB_DIR/stacks/odysseus/docker-compose.yml"
    log "Odysseus docker-compose.yml generado desde template."
  fi
  if [ ! -f "$LAB_DIR/stacks/odysseus/.env.example" ] && [ -f "$SCRIPT_DIR/configs/odysseus/.env.example" ]; then
    cp "$SCRIPT_DIR/configs/odysseus/.env.example" "$LAB_DIR/stacks/odysseus/.env.example"
  fi
  # 3) Levantar SOLO si hay .env (secrets completos, permisos 600)
  if [ -f "$LAB_DIR/stacks/odysseus/.env" ]; then
    (cd "$LAB_DIR/stacks/odysseus" && $DOCKER compose up -d) \
      && log "Odysseus levantado en :7000." \
      || warn "Odysseus: docker compose up falló — revisar .env / red ai-lab."
  else
    warn "Odysseus requiere .env — copiar .env.example a .env, completar (chmod 600) y correr: (cd $LAB_DIR/stacks/odysseus && docker compose up -d)."
  fi
  mark_done odysseus
fi

# Estructura de datos persistentes (convención de volúmenes)
mkdir -p "$LAB_DIR/data/core"
mkdir -p "$LAB_DIR/data/profiles"
log "Estructura data/ creada en $LAB_DIR/data/ (core/ + profiles/)"

# Framework operativo (ops/)
mkdir -p "$LAB_DIR/ops/guards"
mkdir -p "$LAB_DIR/ops/backup"
mkdir -p "$LAB_DIR/ops/runbooks"
mkdir -p "$LAB_DIR/ops/manifests"
mkdir -p "$LAB_DIR/logs/guard"
log "Estructura ops/ creada en $LAB_DIR/ops/"

# Copiar scripts operativos del bootstrap si existen
BOOTSTRAP_OPS="$SCRIPT_DIR/ops"
if [ -d "$BOOTSTRAP_OPS" ]; then
  for subdir in guards backup manifests; do
    if [ -d "$BOOTSTRAP_OPS/$subdir" ]; then
      for script in "$BOOTSTRAP_OPS/$subdir"/*.sh; do
        [ -f "$script" ] || continue
        target="$LAB_DIR/ops/$subdir/$(basename "$script")"
        if [ ! -f "$target" ]; then
          cp "$script" "$target"
          chmod +x "$target"
          log "ops/$subdir/$(basename "$script") copiado."
        fi
      done
    fi
  done
  if [ -d "$BOOTSTRAP_OPS/runbooks" ]; then
    for doc in "$BOOTSTRAP_OPS/runbooks"/*.md; do
      [ -f "$doc" ] || continue
      target="$LAB_DIR/ops/runbooks/$(basename "$doc")"
      if [ ! -f "$target" ]; then
        cp "$doc" "$target"
      fi
    done
    log "Runbooks copiados a $LAB_DIR/ops/runbooks/"
  fi
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

# Watchdog + boot-cleanup de Paperclip (solo si la unidad paperclip está activa)
if should_install paperclip; then
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
mark_done paperclip
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
if should_install dagu; then
# IMPORTANTE: instalar SIN el wizard interactivo. Desde v2.8.3 el installer
# oficial corre un wizard que crea su propio /etc/systemd/system/dagu.service
# (data dir en /var/lib/dagu), chocando con el service que despliega este
# módulo. Canónico del lab: UN solo service (system-scope, configs/dagu.service),
# config en ~/.config/dagu/config.yaml, dags en ~/.config/dagu/dags.
# Los flags --no-prompt --service no instalan solo el binario.
if ! command -v dagu &>/dev/null && [ ! -f "$HOME/.local/bin/dagu" ]; then
  log "Instalando Dagu (solo binario, sin wizard)..."
  curl -fsSL https://raw.githubusercontent.com/dagu-org/dagu/main/scripts/installer.sh \
    | bash -s -- --no-prompt --service no --install-dir "$HOME/.local/bin"
  log "Dagu $(dagu version 2>/dev/null || echo 'instalado')."
else
  log "Dagu ya instalado ($(dagu version 2>/dev/null || echo "$HOME/.local/bin/dagu"))."
fi

# Si un install previo dejó el service del wizard, avisar (no lo tocamos solos)
if [ -f /etc/systemd/system/dagu.service ] && ! grep -q "config=$HOME/.config/dagu/config.yaml" /etc/systemd/system/dagu.service 2>/dev/null; then
  warn "Ya existe /etc/systemd/system/dagu.service (posible wizard del installer)."
  warn "Verificar que apunte a ~/.config/dagu/config.yaml — GOTCHA: el service del"
  warn "wizard usa /var/lib/dagu como data dir (DOS data dirs si conviven)."
fi

# Dagu config
mkdir -p "$HOME/.config/dagu/dags"
DAGU_CONFIG_SRC="$SCRIPT_DIR/configs/dagu-config.yaml.example"
DAGU_BASE_SRC="$SCRIPT_DIR/configs/dagu-base.yaml.example"
DAGU_SERVICE_SRC="$SCRIPT_DIR/configs/dagu.service"

if [ ! -f "$HOME/.config/dagu/config.yaml" ] && [ -f "$DAGU_CONFIG_SRC" ]; then
  sed "s|{{HOME}}|$HOME|g; s|{{HOSTNAME}}|$(hostname -s)|g; s|{{LAB_BIND_ADDR}}|${LAB_BIND_ADDR:-127.0.0.1}|g" "$DAGU_CONFIG_SRC" > "$HOME/.config/dagu/config.yaml"
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

# Dagu systemd service — UN solo service, system-scope, corriendo como $LAB_USER
if [ -f "$HOME/.config/systemd/user/dagu.service" ]; then
  warn "Existe un dagu.service de usuario (~/.config/systemd/user/) de una versión"
  warn "anterior del bootstrap — deshabilitarlo para no tener dos schedulers:"
  warn "  systemctl --user disable --now dagu.service && rm ~/.config/systemd/user/dagu.service"
fi
if [ ! -f /etc/systemd/system/dagu.service ] && [ -f "$DAGU_SERVICE_SRC" ]; then
  DAGU_BIN=$(command -v dagu 2>/dev/null || echo "$HOME/.local/bin/dagu")
  sed "s|{{HOME}}|$HOME|g; s|{{DAGU_PATH}}|$DAGU_BIN|g; s|{{LAB_USER}}|$LAB_USER|g" "$DAGU_SERVICE_SRC" \
    | sudo tee /etc/systemd/system/dagu.service > /dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable dagu.service
  log "dagu.service instalado y habilitado (systemd system, User=$LAB_USER)."
  warn "Iniciar con: sudo systemctl start dagu"
else
  log "dagu.service ya existe — no se sobreescribe."
fi
mark_done dagu
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
