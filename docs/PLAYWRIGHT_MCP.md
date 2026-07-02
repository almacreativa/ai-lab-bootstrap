# Playwright MCP — Visual Testing Headless para Agentes IA

## Problema

Los agentes de IA (Claude Code, OpenCode, Hermes, Antigravity) trabajan en servidores headless sin display.
No pueden "ver" las aplicaciones web que desarrollan o depuran. Playwright MCP les da ojos.

## Que provee

- **Navegacion web headless**: los agentes pueden abrir URLs y navegar paginas
- **Screenshots como base64**: capturas inyectadas directo al contexto del LLM (vision)
- **Accessibility tree**: representacion semantica de la pagina (200-400 tokens vs miles del DOM crudo)
- **Interaccion**: click, fill, drag, keyboard, file upload, dialog handling
- **29 tools MCP**: browser_navigate, browser_take_screenshot, browser_snapshot, browser_click, browser_fill_form, etc.

## Instalacion (automatica via bootstrap)

El modulo `04-ai-tools.sh` instala todo automaticamente:

```bash
# Lo que hace el bootstrap:
npm install -g @playwright/mcp          # Server MCP
npx playwright install --with-deps chromium  # Browser + ~23 paquetes de sistema
# Crea ~/ai-lab/scripts/playwright-mcp.sh
```

### Instalacion manual (lab existente)

```bash
npm install -g @playwright/mcp
npx playwright install --with-deps chromium
```

Crear `~/ai-lab/scripts/playwright-mcp.sh`:
```bash
#!/bin/bash
exec playwright-mcp \
  --headless \
  --browser chromium \
  --viewport-size 1280x720 \
  --caps vision \
  "$@"
```

```bash
chmod +x ~/ai-lab/scripts/playwright-mcp.sh
```

## Configuracion por agente

### Claude Code (`~/.claude/.mcp.json`)

```json
"playwright": {
  "command": "bash",
  "args": ["/home/<USER>/ai-lab/scripts/playwright-mcp.sh"]
}
```

Agregar `"playwright"` a `enabledMcpjsonServers` en `~/.claude/settings.local.json`.

### OpenCode (`~/.config/opencode/opencode.jsonc`)

```json
"playwright": {
  "type": "local",
  "command": ["bash", "/home/<USER>/ai-lab/scripts/playwright-mcp.sh"]
}
```

### Hermes (`~/.hermes/config.yaml`)

```yaml
mcp_servers:
  playwright:
    command: bash
    args:
    - /home/<USER>/ai-lab/scripts/playwright-mcp.sh
```

## Uso

Cada agente lanza su propio proceso Playwright via stdio (aislado, sin conflictos).
El browser se inicia bajo demanda y se cierra al terminar la sesion del agente.

### Ejemplo de flujo tipico

1. Agente navega a `http://localhost:3000`
2. Toma screenshot (devuelve base64 al LLM)
3. LLM analiza la imagen, detecta bug visual
4. Agente modifica CSS/HTML
5. Recarga y toma nuevo screenshot para verificar

### Gotcha importante

Playwright MCP bloquea `file://` por seguridad. Para ver archivos HTML locales,
el agente debe levantar un HTTP server:

```bash
python3 -m http.server 8989 --directory /ruta/al/proyecto &
# Luego navegar a http://127.0.0.1:8989/archivo.html
```

## Flags del wrapper

| Flag | Valor | Razon |
|---|---|---|
| `--headless` | (sin valor) | Obligatorio en servidor sin display |
| `--browser` | `chromium` | Unico browser instalado, suficiente para 95% de casos |
| `--viewport-size` | `1280x720` | Resolucion estandar, capturas deterministas |
| `--caps` | `vision` | Habilita screenshots base64 para LLMs con vision |

### Flags opcionales utiles

- `--caps vision,pdf` — habilita tambien generacion de PDF
- `--allowed-origins "localhost;*.tailscale.ts.net"` — restringir dominios accesibles
- `--viewport-size 1920x1080` — resolucion Full HD
- `--timeout-navigation 30000` — timeout de navegacion mas corto (default 60s)

## Recursos

- Servidor: ~200MB RAM por sesion (Chromium headless)
- Disco: ~300MB (binarios Chromium en `~/.cache/ms-playwright/`)
- Sin puerto fijo (stdio), sin servicio systemd
- Procesos se limpian automaticamente al cerrar la sesion del agente

## Referencia

- Notebook NotebookLM con 59 fuentes: arquitectura MCP, visual testing, transporte SSE/HTTP, memory management
- Repo oficial: https://github.com/microsoft/playwright-mcp
- Docs: https://playwright.dev/mcp/introduction
