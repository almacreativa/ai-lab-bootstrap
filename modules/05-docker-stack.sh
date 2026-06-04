#!/bin/bash
# Módulo 05 — Docker: red ai-lab, Portainer, repos, Hermes service

log "Paso 5/6 — Docker stack..."

# Estructura de directorios
mkdir -p "$LAB_DIR/repos"
mkdir -p "$LAB_DIR/workspace"
mkdir -p "$HOME/.hermes/memories"
mkdir -p "$HOME/.hermes/skills"

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

  if [ -f "$HERMES_SERVICE_SRC" ]; then
    sed "s|{{LAB_USER}}|$LAB_USER|g" "$HERMES_SERVICE_SRC" \
      | sudo tee /etc/systemd/system/hermes.service > /dev/null
    log "hermes.service instalado."
  else
    warn "configs/hermes.service no encontrado — instalar manualmente."
  fi

  if [ -f "$HERMES_START_SRC" ]; then
    sed "s|{{LAB_USER}}|$LAB_USER|g" "$HERMES_START_SRC" \
      | sudo tee /usr/local/bin/hermes-start.sh > /dev/null
    sudo chmod +x /usr/local/bin/hermes-start.sh
    log "hermes-start.sh instalado en /usr/local/bin/"
  else
    warn "configs/hermes-start.sh no encontrado — instalar manualmente."
  fi

  sudo systemctl daemon-reload
  sudo systemctl enable hermes
  log "hermes.service habilitado (no iniciado — configurar secrets primero)."
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

# Templates de secrets (solo si no existen ya)
TEMPLATES_DIR="$SCRIPT_DIR/templates"
if [ -f "$TEMPLATES_DIR/hermes.env.example" ] && [ ! -f "$HOME/.hermes/.env" ]; then
  cp "$TEMPLATES_DIR/hermes.env.example" "$HOME/.hermes/.env.example"
  warn "Completar ~/.hermes/.env antes de iniciar Hermes. Ver .env.example de referencia."
fi
if [ -f "$TEMPLATES_DIR/agents.env.example" ] && [ ! -f "$HOME/.env_agents" ]; then
  cp "$TEMPLATES_DIR/agents.env.example" "$HOME/.env_agents.example"
  warn "Completar ~/.env_agents antes de usar agentes del lab."
fi
if [ "$INSTALL_PAPERCLIP" = "true" ] && \
   [ -f "$TEMPLATES_DIR/paperclip.env.example" ] && \
   [ ! -f "$LAB_DIR/repos/paperclip/.env.paperclip" ]; then
  cp "$TEMPLATES_DIR/paperclip.env.example" "$LAB_DIR/repos/paperclip/.env.paperclip.example"
  warn "Completar paperclip/.env.paperclip antes de levantar Paperclip."
fi

log "Módulo 05 completo."
