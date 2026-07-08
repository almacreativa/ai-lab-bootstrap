#!/bin/bash
# moolmesh-mcp.sh — MCP server para MoolMesh (read-only agent observability)
MCP_SERVER=$(uv run --with moolmesh python3 -c "import hub.mcp_server; print(hub.mcp_server.__file__)" 2>/dev/null)
if [ -z "$MCP_SERVER" ] || [ ! -f "$MCP_SERVER" ]; then
  echo "ERROR: no se encontró hub.mcp_server — verificar que moolmesh está instalado" >&2
  exit 1
fi
exec uv run "$MCP_SERVER" "$@"
