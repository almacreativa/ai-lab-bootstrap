#!/bin/bash
# playwright-mcp.sh — Playwright MCP server para agentes IA (headless)
# Navegación web, screenshots, accessibility tree en servidor sin display
exec playwright-mcp \
  --headless \
  --browser chromium \
  --viewport-size 1280x720 \
  --caps vision \
  "$@"
