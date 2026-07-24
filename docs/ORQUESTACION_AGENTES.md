# Orquestación de agentes — guía operativa

**Actualizado:** 2026-07-23 (Horizonte 1 completado)

El laboratorio delega tareas a agentes de IA (Claude Code, OpenCode, Gemini CLI)
que corren en sesiones tmux. Tres servicios ortogonales resuelven el ciclo
completo de delegación: **crear la sesión → comunicarse con el agente → detectar
cuándo terminó o falló**.

---

## 1. Las tres capas (y por qué son tres)

```
CONTROL        tmux-gateway API (:8680)        crear/listar/matar sesiones
COMUNICACION   tmux-bridge-mcp (MCP stdio)     leer/escribir paneles entre agentes
DETECCION      clawhip (:25294) + dispatch     monitoreo push → Telegram
```

Cada capa es independiente: si una falla, las otras siguen operando. Si el
gateway no responde, se usa tmux directo. Si bridge-mcp no está disponible,
se usa el gateway para leer/escribir. Si clawhip se cae, se vuelve al
polling manual.

### Jerarquía de fallback

| Operación | Preferido | Fallback 1 | Fallback 2 |
|---|---|---|---|
| Crear sesión | tmux-gateway API | `tmux new-session -d` | — |
| Leer panel | tmux-bridge-mcp (`tmux_read`) | gateway (`/capture-pane`) | `tmux capture-pane` |
| Escribir panel | tmux-bridge-mcp (`tmux_type`) | gateway (`/send-keys`) | `tmux send-keys` |
| Detectar estado | clawhip (push automático) | `tmux capture-pane` manual | — |
| Matar sesión | tmux-gateway API | `tmux kill-session` | — |

---

## 2. CONTROL — tmux-gateway

Binario Rust que expone una API REST sobre tmux. Normaliza la interacción con
sesiones de agentes sin depender de que el caller conozca la sintaxis de tmux.

**Puerto:** `:8680` (bind `0.0.0.0`, accesible via Tailscale)
**Health:** `curl http://127.0.0.1:8680/health`
**Service:** `systemctl --user status tmux-gateway`

### Endpoints principales

```bash
# Listar sesiones activas
curl http://127.0.0.1:8680/sessions

# Crear sesión para un agente
curl -X POST http://127.0.0.1:8680/new \
  -H "Content-Type: application/json" \
  -d '{"name":"mi-agente","working_directory":"/home/usuario/proyecto"}'

# Enviar teclas (lanzar un CLI, enviar un prompt)
curl -X POST http://127.0.0.1:8680/send-keys \
  -H "Content-Type: application/json" \
  -d '{"target":"mi-agente:1.0","keys":["claude","Enter"]}'

# Capturar contenido visible del panel
curl "http://127.0.0.1:8680/capture-pane?target=mi-agente:1.0"

# Matar sesión (campo "target", NO "name")
curl -X POST http://127.0.0.1:8680/kill-session \
  -H "Content-Type: application/json" \
  -d '{"target":"mi-agente"}'
```

### Formato de targets

`session:window.pane` — ejemplo: `mi-agente:1.0`

- **window** usa `base-index 1` (configurado en `.tmux.conf`)
- **pane** usa `pane-base-index 0` (requerido por tmux-gateway)
- Una sesión nueva con un solo panel: `mi-agente:1.0`

### Otros endpoints

| Endpoint | Método | Descripción |
|---|---|---|
| `/health` | GET | Health check |
| `/sessions` | GET | Lista sesiones |
| `/new` | POST | Crear sesión |
| `/kill-session` | POST | Matar sesión (usa campo `target`) |
| `/send-keys` | POST | Enviar teclas |
| `/capture-pane` | GET | Capturar contenido visible |
| `/list-windows` | GET | Listar ventanas de una sesión |
| `/list-panes` | GET | Listar paneles de una ventana |
| `/rename-session` | POST | Renombrar sesión |
| `/new-window` | POST | Crear ventana |
| `/split-window` | POST | Dividir panel |
| `/select-layout` | POST | Aplicar layout |
| `/ws/pane/{target}` | WS | Stream en vivo del panel |

---

## 3. COMUNICACIÓN — tmux-bridge-mcp

Servidor MCP (stdio, Node.js) que convierte tmux en un bus de mensajes. Cada
agente que lo tiene configurado obtiene 9 tools para comunicarse con otros
paneles tmux.

**Modo:** stdio (on-demand por sesión MCP, sin daemon)
**Anti-loop:** detecta `$TMUX_PANE` — un agente no puede escribirse a sí mismo
**Script:** `~/ai-lab/scripts/tmux-bridge-mcp.sh`

### Tools disponibles

| Tool | Descripción |
|---|---|
| `tmux_list` | Lista sesiones y paneles tmux activos |
| `tmux_read` | Lee el output visible de un panel |
| `tmux_type` | Escribe texto en un panel (como teclado) |
| `tmux_message` | Envía mensaje con cabecera estructurada |
| `tmux_keys` | Envía teclas especiales (Enter, C-c, etc.) |
| `tmux_name` | Obtiene nombre del panel actual |
| `tmux_resolve` | Resuelve target de panel |
| `tmux_id` | Obtiene ID único de un panel |
| `tmux_doctor` | Diagnostica estado de tmux y permisos |

### Ejemplo: Hermes envía instrucción a un agente

```
1. tmux_list              → identifica paneles activos
2. tmux_read(target=X:Y.Z) → verifica que el agente está listo
3. tmux_type(target=X:Y.Z, text="Refactorizar módulo auth") → envía tarea
4. tmux_read(target=X:Y.Z) → monitorea progreso
```

### Configuración en agentes

Agregar al config MCP del agente:
- **Nombre:** `tmux-bridge`
- **Tipo:** stdio
- **Comando:** `bash`
- **Args:** `/home/<usuario>/ai-lab/scripts/tmux-bridge-mcp.sh`

---

## 4. DETECCIÓN — clawhip + dispatch

Daemon Rust que monitorea **todas** las sesiones tmux en tiempo real. Detecta
dos tipos de eventos sin polling manual:

| Detección | Mecanismo | Latencia |
|---|---|---|
| **Keywords** en output | Substring match windowed (`keyword_window_secs=5`) | ~10-15s |
| **Stale/idle** | Panel sin cambios por N minutos (`stale_minutes=15`) | 15 min |

**Puerto:** `:25294` (bind `127.0.0.1`, solo local)
**Health:** `curl http://127.0.0.1:25294/health`
**Services:** `systemctl --user status clawhip clawhip-dispatch`

### Pipeline de notificación

```
clawhip daemon (poll tmux cada 5s)
    → detección de keyword o stale
    → localfile sink: ~/ai-lab/logs/clawhip/events.jsonl
        → clawhip-dispatch.sh (tail -F + jq)
            → cooldown dedup (1h por evento+sesión)
            → telegram-notify.sh
                → Telegram
```

### Keywords monitoreados

```toml
keywords = ["Error", "error:", "FAILED", "fatal", "panic:", "command not found"]
```

Configurables en `~/.clawhip/config.toml`. El matching es case-insensitive
con filtro de negación (ignora "0 errors").

### Relación con otros sistemas de monitoreo

| Sistema | Tipo | Latencia | Qué cubre |
|---|---|---|---|
| **clawhip** | Push (daemon) | ~15s | Keywords y stale en sesiones tmux |
| **session-watchdog DAG** | Poll (DAG periódico) | ~5 min | Bash inactivo, agente finalizado, espera permiso |
| **MoolMesh** | Archivo histórico | Posterior | Todas las sesiones para consulta y dashboards |

clawhip alerta en tiempo real; el watchdog cubre escenarios que clawhip no
detecta (espera-permiso); MoolMesh documenta todo para análisis posterior.

---

## 5. Ciclo completo: delegar una tarea a un agente

```
                    ┌─────────────┐
                    │   Hermes    │
                    │ (director)  │
                    └──────┬──────┘
                           │
              ┌────────────┼─────────────┐
              │            │             │
              ▼            ▼             ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ CONTROL  │ │ COMUNIC. │ │ DETECCION│
        │ gateway  │ │ bridge   │ │ clawhip  │
        │ :8680    │ │ MCP      │ │ :25294   │
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             │            │             │
             └────────────┼─────────────┘
                          │
                    ┌─────▼─────┐
                    │   tmux    │
                    │ (agente)  │
                    └─────┬─────┘
                          │
                    ┌─────▼─────┐
                    │ Telegram  │
                    │ (usuario) │
                    └───────────┘
```

### Pasos concretos

1. **Crear sesión** (CONTROL):
   ```bash
   curl -X POST http://127.0.0.1:8680/new \
     -d '{"name":"tarea-42","working_directory":"/proyecto"}'
   ```

2. **Lanzar agente** (CONTROL):
   ```bash
   curl -X POST http://127.0.0.1:8680/send-keys \
     -d '{"target":"tarea-42:1.0","keys":["claude","Enter"]}'
   # Esperar trust dialog
   sleep 4
   curl -X POST http://127.0.0.1:8680/send-keys \
     -d '{"target":"tarea-42:1.0","keys":["Enter"]}'
   ```

3. **Enviar tarea** (COMUNICACIÓN):
   ```bash
   # Via MCP (preferido):
   tmux_type(target="tarea-42:1.0", text="Refactorizar auth a JWT")
   # Via gateway (fallback):
   curl -X POST http://127.0.0.1:8680/send-keys \
     -d '{"target":"tarea-42:1.0","keys":["Refactorizar auth a JWT","Enter"]}'
   ```

4. **Detección automática** (DETECCIÓN):
   clawhip monitorea la sesión. Cuando el agente termina o falla:
   - Evento → events.jsonl → dispatch → Telegram
   - El usuario (o Hermes vía Telegram) decide qué hacer

5. **Limpiar sesión** (CONTROL):
   ```bash
   curl -X POST http://127.0.0.1:8680/kill-session \
     -d '{"target":"tarea-42"}'
   ```

---

## 6. Configuración

### Config de clawhip (`~/.clawhip/config.toml`)

```toml
[daemon]
bind_host = "127.0.0.1"
port = 25294

[monitors]
poll_interval_secs = 5

[[monitors.tmux.sessions]]
session = "*"
keywords = ["Error", "error:", "FAILED", "fatal", "panic:", "command not found"]
keyword_window_secs = 5
stale_minutes = 15
format = "alert"

[[routes]]
event = "*"
sink = "localfile"
local_path = "/home/<usuario>/ai-lab/logs/clawhip/events.jsonl"
format = "alert"
```

### Config de tmux (requisitos)

```bash
# En .tmux.conf — OBLIGATORIO para tmux-gateway:
set -g base-index 1          # ventanas empiezan en 1
setw -g pane-base-index 0    # paneles empiezan en 0
```

---

## 7. Troubleshooting

### tmux-gateway no responde en :8680

```bash
systemctl --user status tmux-gateway
# Si está muerto:
systemctl --user restart tmux-gateway
# Verificar:
curl http://127.0.0.1:8680/health
```

### clawhip no detecta keywords

1. Verificar `keyword_window_secs` — valores altos (>10) agregan latencia
2. Verificar que el daemon está corriendo: `curl http://127.0.0.1:25294/health`
3. Verificar eventos: `tail -f ~/ai-lab/logs/clawhip/events.jsonl`

### dispatch no envía a Telegram

```bash
systemctl --user status clawhip-dispatch
# Verificar cooldown (no repite misma alerta en 1h):
cat ~/ai-lab/logs/clawhip/dispatch-cooldown.json
```

### Targets incorrectos ("can't find pane")

- Asegurarse de usar formato `session:window.pane`
- Ventana 1 (no 0) por `base-index 1`
- Panel 0 (no 1) por `pane-base-index 0`
- Verificar con: `tmux list-panes -t session:window`

---

## 8. Evolución planificada (Horizonte 2)

| Mejora | Descripción | Estado |
|---|---|---|
| Loop cerrado Dagu | dispatch.sh → `dagu start <dag>` para continuación automática | Diseñado, no implementado |
| Webhook Hermes | Si Hermes 0.19+ soporta webhook: clawhip → Hermes directo | Pendiente upstream |
| Reemplazo session-watchdog | Si clawhip es confiable tras N días, simplificar el DAG | En evaluación |
| Sink HTTP en clawhip | Eliminaría la necesidad de dispatch.sh como intermediario | Pendiente upstream |

---

*Documento operativo del bootstrap. Referencia técnica detallada en
`~/.hermes/skills/.../tmux-agent-communication.md`.*
