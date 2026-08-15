#!/bin/bash
# registry.sh — ÚNICA fuente de verdad de unidades instalables.
# Formato: id | stage | default(on/off) | obligatoria(si/no) | deps(coma) | descripción
# stage mapea a los módulos: 01=system 02=node 03=python 04=ai-tools 05=docker
#
# Agregar una herramienta nueva = agregar UNA línea acá. No enumerar herramientas
# en ningún otro lugar (los módulos solo consultan should_install <id>).

LAB_UNITS=(
  "docker|01|on|si||Docker CE + Compose (base)"
  "node|02|on|si||Node.js vía nvm (base)"
  "uv|03|on|si||uv (Python) (base)"
  "hermes|03|on|no|uv|Hermes Agent (operador)"
  "nlm|03|on|no|uv,chromium|notebooklm-mcp-cli"
  "chromium|04|on|no||Chromium headless (logins CDP)"
  "claude-code|04|on|no||Claude Code CLI"
  "opencode|04|on|no||OpenCode CLI"
  "engram|04|on|no||Memoria persistente cross-session"
  "moolmesh|04|on|no|uv|Observatorio de sesiones + systemd"
  "playwright-mcp|04|on|no|node|Playwright MCP visual testing"
  "tmux-bridge|04|on|no|node|tmux-bridge-mcp (inter-agente)"
  "clawhip|04|on|no||clawhip (orquestación tmux, prebuilt)"
  "tmux-gateway|04|on|no||tmux-gateway (API sobre tmux, prebuilt)"
  "paperclip|05|on|no|docker|Paperclip (clone + watchdogs)"
  "portainer|05|on|no|docker|Gestión de contenedores"
  "searxng|05|on|no|docker|Backend de búsqueda de Hermes"
  "uptime-kuma|05|on|no|docker|Monitoreo con alertas"
  "glance|05|on|no|docker|Dashboard Centro de Comando"
  "dagu|05|on|no||Orquestador de workflows (reemplaza crontab)"
  "odysseus|05|off|no|docker|Frontend LLM multi-modelo (receta pendiente — ver módulo 05 §Odysseus)"
)
