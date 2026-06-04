#!/bin/bash
# Módulo 03 — Python: uv, Hermes Agent venv, notebooklm-mcp-cli

log "Paso 3/6 — Python tools..."

# uv — gestor Python rápido (Astral)
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  log "uv instalado."
else
  log "uv ya instalado, saltando."
fi

# Hermes Agent en venv aislado
if [ "$INSTALL_HERMES" = "true" ]; then
  if [ ! -f "$HOME/.hermes-env/bin/hermes" ]; then
    python3 -m venv "$HOME/.hermes-env"
    "$HOME/.hermes-env/bin/pip" install --upgrade pip -q
    "$HOME/.hermes-env/bin/pip" install hermes-agent -q
    log "Hermes Agent instalado en ~/.hermes-env"
  else
    log "Hermes ya instalado, saltando."
  fi
fi

# notebooklm-mcp-cli — cliente CLI + servidor MCP para NotebookLM
if [ "$INSTALL_NLM" = "true" ]; then
  if ! command -v nlm &>/dev/null; then
    uv tool install notebooklm-mcp-cli
    log "notebooklm-mcp-cli instalado (comando: nlm)."
    warn "Para autenticar nlm, ver sección de pasos manuales al final."
  else
    log "nlm ya instalado, saltando."
  fi
fi

log "Módulo 03 completo."
