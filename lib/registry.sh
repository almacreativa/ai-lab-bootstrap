#!/bin/bash
# registry.sh — ÚNICA fuente de verdad de unidades instalables.
# Formato: id | stage | default(on/off) | obligatoria(si/no) | deps(coma) | descripción | layer
# stage mapea a los módulos: 01=system 02=node 03=python 04=ai-tools 05=docker
# layer es una agrupación NARRATIVA (builder/operator/explorer/addons) para --layer
# y los encabezados de --interactive. NO es lo mismo que "perfil" (forja/vitrina).
#
# Agregar una herramienta nueva = agregar UNA línea acá. No enumerar herramientas
# en ningún otro lugar (los módulos solo consultan should_install <id>).

LAB_UNITS=(
  "docker|01|on|si||Docker CE + Compose (base)|builder"
  "node|02|on|si||Node.js vía nvm (base)|builder"
  "antigravity|02|on|no||Antigravity CLI (agy) — agente de código de Google|builder"
  "uv|03|on|si||uv (Python) (base)|builder"
  "hermes|03|on|no|uv|Hermes Agent (operador)|operator"
  "nlm|03|on|no|uv,chromium|notebooklm-mcp-cli|addons"
  "chromium|04|on|no||Chromium headless (logins CDP)|addons"
  "claude-code|04|on|no||Claude Code CLI|builder"
  "opencode|04|on|no||OpenCode CLI|builder"
  "engram|04|on|no||Memoria persistente cross-session|operator"
  "moolmesh|04|on|no|uv|Observatorio de sesiones + systemd|addons"
  "playwright-mcp|04|on|no|node|Playwright MCP visual testing|explorer"
  "tmux-bridge|04|on|no|node|tmux-bridge-mcp (inter-agente)|explorer"
  "clawhip|04|on|no||clawhip (orquestación tmux, prebuilt)|addons"
  "tmux-gateway|04|on|no||tmux-gateway (API sobre tmux, prebuilt)|addons"
  "paperclip|05|on|no|docker|Paperclip (clone + watchdogs)|addons"
  "portainer|05|on|no|docker|Gestión de contenedores|addons"
  "searxng|05|on|no|docker|Backend de búsqueda de Hermes|operator"
  "uptime-kuma|05|on|no|docker|Monitoreo con alertas|addons"
  "glance|05|on|no|docker|Dashboard Centro de Comando|addons"
  "dagu|05|on|no||Orquestador de workflows (reemplaza crontab)|addons"
  "odysseus|05|on|no|docker|Frontend LLM multi-modelo (workspace AI)|explorer"
)
