# Paperclip MCP — conexión genérica por empresa

Los agentes del host (Hermes, Claude Code, OpenCode) operan Paperclip vía MCP.
La regla de aislamiento del lab aplica también aquí: **un servidor MCP por
empresa**, cada uno con su `COMPANY_ID` fijo — un agente conectado al MCP de
una empresa no puede tocar issues de otra.

## Template

`scripts/paperclip-mcp-company.sh.template`:

```bash
#!/bin/bash
export PAPERCLIP_BASE_URL="http://{{PAPERCLIP_HOST}}:3100/api"
export PAPERCLIP_API_KEY=$(grep PCP_BOARD_KEY ${HOME}/.hermes/.env | cut -d= -f2)
export PAPERCLIP_COMPANY_ID="{{COMPANY_ID}}"
exec uvx paperclip-mcp --transport stdio "$@"
```

- `{{PAPERCLIP_HOST}}` — host de Paperclip (`127.0.0.1` si es local)
- `{{COMPANY_ID}}` — UUID completo de la empresa en Paperclip
- La API key se lee de `~/.hermes/.env` (`PCP_BOARD_KEY`), nunca va en el script

## Instanciación (parte del onboarding de empresa)

```bash
sed -e 's/{{PAPERCLIP_HOST}}/127.0.0.1/' -e 's/{{COMPANY_ID}}/<uuid>/' \
  scripts/paperclip-mcp-company.sh.template > ~/ai-lab/scripts/paperclip-mcp-<slug>.sh
chmod +x ~/ai-lab/scripts/paperclip-mcp-<slug>.sh
```

Registrar en cada agente:

**Hermes** (`~/.hermes/config.yaml` → `mcp_servers`):
```yaml
paperclip_<slug>:
  command: bash
  args: [/home/<user>/ai-lab/scripts/paperclip-mcp-<slug>.sh]
```

**Claude Code** (`~/.claude.json` → `mcpServers`): mismo comando/args con
`"type": "stdio"`.

## Qué expone

~21 tools por empresa (issues, agentes, runs, wiki, goals, heartbeat
on-demand). Los scripts instanciados (`paperclip-mcp-<slug>.sh`) son
personalización de instancia: viven en `~/ai-lab/scripts/` y se versionan en
el repo privado, no en este repo.
