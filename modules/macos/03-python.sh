#!/bin/bash
# Módulo 03 (macOS) — uv, Hermes Agent venv, notebooklm-mcp-cli

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
# Hermes requiere Python >=3.11,<3.14 — se usa uv para garantizar la versión exacta
if [ "$INSTALL_HERMES" = "true" ]; then
  if [ ! -f "$HOME/.hermes-env/bin/hermes" ]; then
    uv venv "$HOME/.hermes-env" --python 3.12
    "$HOME/.hermes-env/bin/pip" install --upgrade pip -q
    "$HOME/.hermes-env/bin/pip" install hermes-agent -q
    log "Hermes Agent instalado en ~/.hermes-env (Python $("$HOME/.hermes-env/bin/python" --version))"
  else
    log "Hermes ya instalado (Python $("$HOME/.hermes-env/bin/python" --version)), saltando."
  fi
fi

# notebooklm-mcp-cli — cliente CLI + servidor MCP para NotebookLM
if [ "$INSTALL_NLM" = "true" ]; then
  if ! command -v nlm &>/dev/null; then
    uv tool install notebooklm-mcp-cli
    log "notebooklm-mcp-cli instalado (comando: nlm)."
    warn "Para autenticar nlm, ver sección de pasos manuales al final (en Mac es más simple: navegador real, sin Xvfb/CDP)."
  else
    log "nlm ya instalado, saltando."
  fi
fi

log "Módulo 03 completo."
