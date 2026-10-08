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

# Hermes Agent — instalador oficial (canal git, pin por tag CalVer)
# El canal pip/PyPI fue retirado en 0.20.0 (PyPI quedó en 0.19.0) y los tags traen
# fixes críticos (OpenCode Go MissingSessionID, state.db). El instalador de la web
# sirve el de main y espera pm/ → usar SIEMPRE el del propio tag.
# Override con HERMES_TAG=v2026.x.y
HERMES_TAG="${HERMES_TAG:-v2026.9.24}"
if [ "$INSTALL_HERMES" = "true" ]; then
  HERMES_INSTALL_DIR="$HOME/.hermes/hermes-agent"
  if [ -x "$HERMES_INSTALL_DIR/venv/bin/hermes" ]; then
    INSTALLED_TAG="$(git -C "$HERMES_INSTALL_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
    log "Hermes ya instalado (${INSTALLED_TAG:-desconocido}), saltando."
    if [ -n "$INSTALLED_TAG" ] && [ "$INSTALLED_TAG" != "$HERMES_TAG" ]; then
      warn "Pin del bootstrap: $HERMES_TAG ≠ instalado: $INSTALLED_TAG — actualizar con el instalador del tag."
    fi
  else
    INSTALL_SH="$(mktemp)"
    curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_TAG}/scripts/install.sh" -o "$INSTALL_SH"
    if grep -q 'pm/lock.json' "$INSTALL_SH"; then
      err "instalador de ${HERMES_TAG} no corresponde al tag (parece el de main). Abortando."
    fi
    HERMES_HOME="$HOME/.hermes" bash "$INSTALL_SH" \
      --branch "$HERMES_TAG" \
      --dir "$HERMES_INSTALL_DIR" \
      --hermes-home "$HOME/.hermes" \
      --skip-setup
    rm -f "$INSTALL_SH"
    if [ ! -x "$HERMES_INSTALL_DIR/venv/bin/hermes" ]; then
      err "Hermes no quedó instalado en $HERMES_INSTALL_DIR — revisar salida del instalador."
    fi
    # Compat: ~/.hermes-env → venv del install git (launchers y scripts viejos siguen funcionando)
    if [ -e "$HOME/.hermes-env" ] && [ ! -L "$HOME/.hermes-env" ]; then
      warn "$HOME/.hermes-env existe y no es symlink (install pip viejo) — no se toca; migrar con el handoff 0.21.5."
    else
      ln -sfn "$HERMES_INSTALL_DIR/venv" "$HOME/.hermes-env"
    fi
    log "Hermes $("$HERMES_INSTALL_DIR/venv/bin/hermes" --version 2>/dev/null | head -1) instalado (git, $HERMES_TAG)."
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
