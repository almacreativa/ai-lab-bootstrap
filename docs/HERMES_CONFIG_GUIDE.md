# Hermes Agent — Guía de configuración

Referencia para configurar Hermes en el lab. Sin secrets — las API keys
viven en `~/.hermes/.env` (fuera del repo).

Template completo: `configs/hermes-config.yaml.example`

---

## Estructura del config.yaml

**Ubicación:** `~/.hermes/config.yaml`

```yaml
model:
  provider: opencode-go
  default: deepseek-v4-pro
```

`provider` define quién sirve los modelos. El lab usa OpenCode como proveedor
centralizado de inferencia — un solo proveedor con acceso a múltiples modelos.
La API key vive en `~/.hermes/.env` como `OPENCODE_GO_API_KEY`.

---

## Providers disponibles

Hermes soporta múltiples providers. Los que usa este stack:

### opencode_go — Provider principal

Suscripción mensual (~$10/mes) con presupuesto de requests por modelo.
Acceso a los modelos más capaces.

| Modelo | Perfil de uso |
|---|---|
| `deepseek-v4-pro` | Tareas complejas, código, arquitectura — **default del lab** |
| `deepseek-v4-flash` | Tareas simples, alto volumen, menor costo |
| `kimi-k2.6` | Contexto largo, decisión estratégica |
| `qwen3.7-plus` | Razonamiento general, multilingüe |

API key: `OPENCODE_GO_API_KEY` en `~/.hermes/.env`
Endpoint: `https://opencode.ai/zen/go/v1`

**Modelos disponibles en opencode-go:**

| Modelo | Req/5h | Cuándo usarlo |
|---|---|---|
| `deepseek-v4-flash` | ~31.650 | Alto volumen, tareas repetitivas |
| `mimo-v2.5` | ~30.100 | Muy alto volumen |
| `qwen3.7-plus` | ~4.300 | Razonamiento estratégico — **recomendado para Hermes** |
| `deepseek-v4-pro` | ~3.450 | Análisis profundo, código complejo |
| `mimo-v2.5-pro` | ~3.250 | Depuración, refactorización |
| `qwen3.6-plus` | ~3.300 | Alternativa a qwen3.7-plus |
| `minimax-m2.5` | ~6.300 | Latencia muy baja |
| `minimax-m2.7` | ~3.400 | Latencia baja |
| `minimax-m3` | ~1.400 | Latencia baja, repetitivo |
| `kimi-k2.5` | ~1.850 | Contexto largo |
| `kimi-k2.6` | ~1.150 | Contexto muy largo, decisión estratégica |
| `glm-5` | ~1.150 | Lógica compleja |
| `glm-5.1` | ~880 | Análisis de dependencias |
| `qwen3.7-max` | ~950 | Razonamiento fuerte, menor volumen |

### opencode-zen — Fallback gratuito

Tier gratuito de OpenCode. Se activa automáticamente cuando el provider
principal falla (503, rate limit, presupuesto agotado).

| Modelo | Notas |
|---|---|
| `opencode/nemotron-3-ultra-free` | Más capaz del tier gratuito — usado como fallback y vision |
| `opencode/deepseek-v4-flash-free` | Rápido y gratuito — usado para compresión de contexto |
| `opencode/big-pickle` | Uso general gratuito |
| `opencode/mimo-v2.5-free` | Gratuito |
| `opencode/minimax-m3-free` | Gratuito |

API key: `OPENCODE_ZEN_API_KEY` en `~/.hermes/.env`

---

## Secciones del config.yaml explicadas

### `delegation` — Política de complejidad (subagentes)

```yaml
delegation:
  provider: ollama-cloud
  model: qwen3-coder-next
  reasoning_effort: medium
  max_iterations: 50
  max_concurrent_children: 3
```

Cuando Hermes delega una subtarea via `delegate_task`, los subagentes usan este
provider/modelo en lugar de heredar el del agente principal. Esto implementa una
**política de complejidad**:

- **Principal** (`opencode-go/deepseek-v4-pro`) — orquestación, razonamiento estratégico, decisiones
- **Subagentes** (`ollama-cloud/qwen3-coder-next`) — ejecución, código, tareas específicas — gratis

Sin `delegation` configurado, los subagentes heredan el modelo principal y consumen
la misma cuota cara para tareas simples.

Para máxima capacidad de código en subagentes, cambiar a `qwen3-coder:480b`.

---

### `fallback_providers` — Respaldo automático

```yaml
fallback_providers:
  - provider: ollama-cloud
    model: minimax-m3
  - provider: opencode-zen
    model: opencode/nemotron-3-ultra-free
```

Cuando el provider principal falla, Hermes redirige automáticamente al primer fallback disponible.
La cadena es:

1. **ollama-cloud/minimax-m3** — gratuito, flagship multimodal de MiniMax con 1M de contexto.
   Diseñado para uso agéntico (74.2% MCP Atlas, mayor Claw-Eval entre modelos evaluados).
   Es el mejor sustituto del orquestador principal porque mantiene capacidad de razonamiento
   general, seguimiento de instrucciones y uso de herramientas. Disponibilidad variable.
2. **opencode-zen/nemotron-3-ultra-free** — tier gratuito de OpenCode, siempre disponible.
   Capacidad reducida pero garantizada. Actúa como último recurso si ollama-cloud no responde.

**Por qué no `qwen3-coder-next` como fallback del orquestador:**  
Es un modelo especializado en código (64K contexto). Cuando el orquestador usa el fallback,
sigue necesitando razonamiento general, planificación y comunicación — no solo código.

`OLLAMA_API_KEY` requerida en `~/.hermes/.env`. Obtener desde `~/.local/share/opencode/auth.json`
(clave del provider `ollama-cloud`).

---

### `auxiliary` — Modelos para tareas internas

```yaml
auxiliary:
  compression:
    provider: opencode-zen
    model: opencode/deepseek-v4-flash-free
  vision:
    provider: opencode-zen
    model: opencode/nemotron-3-ultra-free
```

Las tareas internas de Hermes (comprimir contexto, procesar imágenes) usan
modelos separados para no consumir la cuota del modelo principal.

- **compression:** Resumen automático cuando la conversación llena el contexto.
  Usa un modelo rápido y gratuito porque la tarea es mecánica.
- **vision:** Procesamiento de imágenes enviadas en la conversación.

---

### `agent` — Comportamiento

```yaml
agent:
  max_turns: 45
  verbose: false
  reasoning_effort: medium
```

- **max_turns:** Límite de iteraciones en una tarea autónoma. Previene loops.
  `45` es suficiente para tareas complejas de múltiples pasos.
- **reasoning_effort:** Cuánto "piensa" el agente antes de actuar:
  - `low` — consultas simples, resúmenes rápidos
  - `medium` — uso general, balance velocidad/calidad
  - `high` — código complejo, arquitectura, análisis profundo

Para cambiar el esfuerzo en una tarea puntual sin editar el config,
se puede indicar directamente: *"usá razonamiento alto para esto"*.

---

### `compression` — Gestión de contexto

```yaml
compression:
  enabled: true
  threshold: 0.4
```

Cuando la conversación llega al 40% del contexto disponible, Hermes la comprime
usando el modelo auxiliar definido en `auxiliary.compression`. Permite sesiones
largas sin perder continuidad. `0.4` es más agresivo que el default (`0.5`) —
comprime antes para tener más margen en tareas complejas.

---

### `terminal` — Ejecución de comandos

```yaml
terminal:
  backend: local
  cwd: ~/ai-lab/workspace
  timeout: 180
  lifetime_seconds: 300
  container_persistent: true
```

- **backend: local** — Hermes ejecuta comandos directamente en el host.
  En este stack Hermes corre bare metal (systemd), no en Docker, por lo que
  tiene acceso nativo a todas las herramientas del host (claude, opencode, gh, docker).
- **cwd** — Directorio de trabajo por defecto para terminales que abre Hermes.
  Ajustar a `~/ai-lab/workspace` o al workspace principal del proyecto.
- **container_persistent** — Mantiene el terminal abierto entre turnos.
  Sin esto, cada tool call abre y cierra un proceso nuevo.

---

### `mcp_servers` — Servidores MCP

```yaml
mcp_servers:
  notebooklm-mcp:
    command: uvx
    args: ["--from", "notebooklm-mcp-cli", "notebooklm-mcp"]
```

Hermes arranca automáticamente los servidores MCP al iniciar.
`notebooklm-mcp` requiere que las cookies de Google estén vigentes en
`~/.notebooklm-mcp-cli/`. Ver proceso de login en el README principal.

Para agregar otros MCP servers, agregar entradas al mismo bloque:

```yaml
mcp_servers:
  notebooklm-mcp:
    command: uvx
    args: ["--from", "notebooklm-mcp-cli", "notebooklm-mcp"]
  mi-otro-mcp:
    command: npx
    args: ["-y", "@nombre/paquete-mcp"]
```

---

### `web` — Búsqueda web

```yaml
web:
  search_backend: searxng
```

Hermes usa la instancia local de SearXNG levantada por el bootstrap en
`localhost:8080`. Sin API key, sin tracking, consulta más de 70 fuentes en paralelo.
Si SearXNG no está disponible, Hermes usa el backend por defecto.

---

## Archivo .env de Hermes

**Ubicación:** `~/.hermes/.env`  
**Permisos:** `chmod 600 ~/.hermes/.env`

```bash
# Provider principal
OPENCODE_GO_API_KEY=go_<tu-api-key>

# Provider fallback / auxiliares (tier gratuito OpenCode)
OPENCODE_ZEN_API_KEY=zen_<tu-api-key>

# ollama-cloud: modelos grandes gratuitos (minimax-m3, deepseek-v4-pro, kimi-k2.6, etc.)
# Extraer desde ~/.local/share/opencode/auth.json → key del provider "ollama-cloud"
OLLAMA_API_KEY=<key-de-ollama-cloud>

# Telegram gateway
TELEGRAM_BOT_TOKEN=<token-de-botfather>
TELEGRAM_ALLOWED_USERS=<chat-id-numerico>

# Timeouts
TERMINAL_TIMEOUT=120
TERMINAL_LIFETIME_SECONDS=300

# Debug (false en producción)
WEB_TOOLS_DEBUG=false
VISION_TOOLS_DEBUG=false
IMAGE_TOOLS_DEBUG=false
```

Obtener API keys en `https://opencode.ai` → Settings → API Keys.

---

## Comandos operativos

```bash
# Ver config activo
cat ~/.hermes/config.yaml

# Aplicar cambios (reiniciar servicio)
sudo systemctl restart hermes

# Cambiar modelo en caliente sin reiniciar
~/.hermes-env/bin/hermes model

# Ver MCP servers configurados
~/.hermes-env/bin/hermes mcp list

# Ver skills activos
~/.hermes-env/bin/hermes skills list

# Logs en tiempo real
journalctl -u hermes -f

# Estado del servicio
sudo systemctl status hermes
```

---

## Cuando se agota el presupuesto de opencode_go

El fallback a `opencode-zen` es automático. Para confirmar que está funcionando:

```bash
journalctl -u hermes -f | grep -i "fallback\|opencode-zen"
```

Para forzar el tier gratuito temporalmente, editar `~/.hermes/config.yaml`:

```yaml
model:
  provider: opencode-zen
  default: opencode/nemotron-3-ultra-free
```

Y restaurar cuando se resetee el periodo de opencode_go.
