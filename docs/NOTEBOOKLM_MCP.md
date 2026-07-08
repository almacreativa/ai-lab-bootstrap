# NotebookLM — conexión del lab (CLI, MCP y gateway)

NotebookLM es el motor de investigación del lab: los agentes no hacen web
search directo para investigaciones profundas — lanzan research en NotebookLM
y consultan cuadernos con fuentes curadas.

## Componentes

| Componente | Qué es | Dónde |
|---|---|---|
| `nlm` (CLI) | Autenticación y operaciones de línea de comandos | binario en PATH |
| `notebooklm-mcp` | Servidor MCP stdio que expone NotebookLM a los agentes | paquete `notebooklm-mcp-cli` |
| `nlm-gateway` | API HTTP local (:8770, systemd user) con aliases de cuadernos en `notebooks.yaml` | `stacks/nlm-gateway/` |
| `nlm-sync.sh` | Sincronización de knowledge → cuadernos | `scripts/` |

## Autenticación

`nlm login` necesita una sesión de Google. En servidor headless se hace vía
CDP (Chromium remoto) — procedimiento completo en `POST-BOOTSTRAP.md` §2.4.
Para cambiar de cuenta: `nlm login switch <perfil>` (el MCP usa el perfil
default activo al instante).

## Configuración por agente

**Claude Code** (`~/.claude.json` → `mcpServers`):
```json
"notebooklm-mcp": { "type": "stdio", "command": "notebooklm-mcp", "args": [] }
```

**Hermes** (`~/.hermes/config.yaml` → `mcp_servers`):
```yaml
notebooklm-mcp:
  command: uvx
  args: [--from, notebooklm-mcp-cli, notebooklm-mcp]
```

**OpenCode**: igual que Claude Code, en su config de MCPs.

## Workflow de investigación (obligatorio)

1. `research_start` — lanza la investigación (devuelve un task id)
2. `research_status` — poll hasta completar
3. `research_import` — **sin este paso el cuaderno queda vacío**: importa las
   fuentes encontradas al cuaderno

Para consultas sobre cuadernos existentes: `notebook_query` (o
`cross_notebook_query` para varios). El gateway (:8770) permite a scripts y
crons consultar cuadernos por alias sin hablar MCP.
