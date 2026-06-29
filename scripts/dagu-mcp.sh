#!/bin/bash
# dagu-mcp.sh — Bridge stdio→HTTP para Dagu MCP
# Obtiene JWT fresco de Dagu y levanta mcp-proxy como stdio
# Requiere: DAGU_AUTH_USER y DAGU_AUTH_PASS en $ENV_FILE
#           uvx (uv) instalado para mcp-proxy
ENV_FILE="$HOME/.hermes/.env"
source "${LAB_DIR:-$HOME/ai-lab}/scripts/.env" 2>/dev/null
DAGU_URL="http://${LAB_IP:-127.0.0.1}:8480"

DAGU_USER=$(grep '^DAGU_AUTH_USER=' "$ENV_FILE" | cut -d= -f2)
DAGU_PASS=$(grep '^DAGU_AUTH_PASS=' "$ENV_FILE" | cut -d= -f2)

TOKEN=$(curl -sf -X POST "${DAGU_URL}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${DAGU_USER}\",\"password\":\"${DAGU_PASS}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo '{"error":"Failed to authenticate with Dagu"}' >&2
  exit 1
fi

exec uvx --from mcp-proxy mcp-proxy "${DAGU_URL}/mcp" \
  --transport streamablehttp \
  -H Authorization "Bearer ${TOKEN}" \
  "$@"
