#!/bin/bash
# Módulo 05 — Docker: red ai-lab, Portainer, repos, Hermes service

log "Paso 5/6 — Docker stack..."

mkdir -p "$LAB_DIR/repos"

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
    NODE_VERSION=$(node --version 2>/dev/null || echo "v24.16.0")
    sed "s|{{LAB_USER}}|$LAB_USER|g; s|{{NODE_VERSION}}|$NODE_VERSION|g" "$HERMES_SERVICE_SRC" \
      | sudo tee /etc/systemd/system/hermes.service > /dev/null
    log "hermes.service instalado (Node $NODE_VERSION)."
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

warn "Antes de iniciar servicios, completar los secrets usando los templates en: $SCRIPT_DIR/templates/"

log "Módulo 05 completo."
