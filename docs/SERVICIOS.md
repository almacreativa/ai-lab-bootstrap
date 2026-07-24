# Inventario de servicios — <HOSTNAME>
**Actualizado:** 2026-07-23 (Horizonte 1 — orquestación de agentes)

## Servicios y binds (regla: NADA en 0.0.0.0 salvo SSH con UFW)

| Servicio | Runtime | Puerto / bind | RAM aprox | Acceso |
|----------|---------|---------------|-----------|--------|
| SSH | systemd | 0.0.0.0:22 — UFW: solo Tailscale + LAN | — | Mac/tailnet |
| Hermes gateway + dashboard | bare metal (`$HOME/.hermes-env/bin/hermes`) | 0.0.0.0:9119 — UFW: Tailscale + 172.16/12 (Kuma) | ~200MB | tailnet |
| Paperclip server | Docker | `<SERVER_IP>:3100` | ~1GB (limit 4g) | tailnet |
| Paperclip DB (pgvector/pg17, vol `paperclip_pgdata_v2`) | Docker | `127.0.0.1:5432` | ~170MB | local |
| Mem0 (wrapper FastAPI) | Docker | `127.0.0.1:8765` + red `paperclip_default` (`mem0:8765`) | ~380MB limit | local + contenedores |
| Ollama (nomic-embed-text) | Docker | `127.0.0.1:11434` | ~512MB limit | local + red mem0 |
| Outline | (RETIRADO 2026-06-28 — datos preservados en volumes) |
| Uptime Kuma | Docker | `<SERVER_IP>:3001` + redes outline/mem0 | 128MB limit | tailnet |
| SearXNG | Docker | `127.0.0.1:8080` | ~150MB | local |
| Portainer | Docker | `<SERVER_IP>:9443` | ~80MB | tailnet |
| **NLM Gateway** | host (uvicorn, cron @reboot) | 0.0.0.0:8770 — UFW: solo 172.16/12 (contenedores) y local | ~80MB | contenedores Paperclip |
| **tmux-gateway** | host (binario Rust, systemd user) | `0.0.0.0:8680` — UFW: Tailscale | ~11MB | Hermes, agentes, tailnet |
| **clawhip** | host (binario Rust, systemd user) | `127.0.0.1:25294` | ~10MB | local (monitorea tmux) |
| **clawhip-dispatch** | host (bash, systemd user) | sin puerto (tail -F) | ~4MB | clawhip → telegram-notify.sh |
| **tmux-bridge-mcp** | host (Node.js, stdio MCP bajo demanda) | sin puerto (stdio) | ~5MB por sesión, 0 en reposo | Hermes, Claude Code, OpenCode |
| **Engram** | host (binario Go, stdio MCP bajo demanda) | sin puerto (stdio) | ~5-15MB por sesión, 0 en reposo | Claude Code, OpenCode, Antigravity |
| **Playwright MCP** | host (Node.js, stdio MCP bajo demanda) | sin puerto (stdio) | ~200MB por sesión (Chromium headless) | Claude Code, OpenCode, Hermes |
| Syncthing | systemd user | GUI `127.0.0.1:8384`; P2P 22000 — UFW: Tailscale + LAN | ~60MB | — |

**RAM total en uso:** verificar con `free -h`. Engram no suma RAM residente (stdio efímero).

## Carpetas Syncthing (↔ Mac)

| ID | Servidor | Contenido |
|----|----------|-----------|
| `ai-lab-knowledge` | `~/ai-lab/knowledge` | knowledge multi-empresa + wikis de agentes (Obsidian) |
| `ai-lab-ops` | `~/ai-lab/ops` | espejos de deliverables por empresa |
| `shared-demos` | `~/shared/demos` | intercambio de trabajo |

## Redes Docker relevantes

- `paperclip_default`: paperclip-server, paperclip-db, **mem0** (conectado para que los agentes lleguen a `mem0:8765`), **uptime-kuma**
- `mem0_default`: mem0, ollama, uptime-kuma
- `outline_default`: outline, outline-postgres, outline-redis, uptime-kuma

## UFW (baseline)

Modelo **per-port**: las reglas se leen de `~/ai-lab/ops/core-manifest.yaml`
(sección `security.allowed_ports`). No hay lista fija hardcodeada; el script
de aplicación deriva las reglas del manifiesto.

**10 puertos bare-metal permitidos** (todos TCP, `deny incoming` por defecto):

| Puerto | Servicio | Desde |
|-------:|----------|-------|
| 22     | SSH                 | Tailscale + LAN |
| 9119   | Hermes dashboard    | Tailscale |
| 22000  | Syncthing P2P       | Tailscale + LAN |
| 8480   | Dagu                | Tailscale |
| 5200   | MoolMesh            | Tailscale |
| 9001   | centro-de-comando   | Tailscale |
| 8770   | NLM gateway         | Tailscale |
| 8646   | Hermes xAI proxy    | Tailscale |
| 8384   | Syncthing GUI       | Tailscale |
| 9000   | Glance (host network) | Tailscale |

**Regla especial — Hermes desde Docker:** el Hermes xAI proxy corre como
servicio systemd pero se expone para ser consumido por contenedores Docker
(paperclip-xai-proxy). UFW permite el tráfico desde las redes de contenedores
hacia 8646, manteniendo la coherencia con el modelo per-port.

**fail2ban** activo con jail SSH habilitado (`security.fail2ban: true` en el
manifiesto).

**Detalle completo de las reglas** (rangos exactos de Tailscale, LAN, etc.)
en `docs/SECURITY_GUIDE.md`.

**Script de aplicación idempotente:** `~/ai-lab/scripts/security-apply-sudo.sh`
(requiere `sudo`).

**Importante:** UFW NO protege puertos publicados por Docker — la protección
es el bind.

## Automatización — scripts, stacks y servicios

Inventario completo de todo lo que corre solo (cron, systemd) o se invoca manualmente
para operar el lab. Instalado/registrado por el módulo `05-docker-stack.sh` del
bootstrap salvo que se indique lo contrario.

### Salud / resiliencia del servidor

| Script | Disparador | Función |
|---|---|---|
| `lab-health-check.sh` | cron `@reboot sleep 60` + `*/15 * * * *` | Repara redes Docker faltantes (mapa declarativo: uptime-kuma→outline/mem0/paperclip_default, mem0→mem0/paperclip_default, ollama→mem0_default) y reinicia contenedores que no respondan en su endpoint HTTP. Notifica por Telegram solo si corrige algo. Origen: tras un reinicio en frío (corte de luz) `uptime-kuma` perdió su conexión a `mem0_default`/`paperclip_default` y reportó Ollama/Mem0 como caídos (`ENOTFOUND`) aunque estaban sanos |
| `paperclip-watchdog.sh` | cron `*/15 * * * *` | Mata heartbeats zombie de Paperclip (`status=running`, sin output, >10min) |
| `paperclip-boot-cleanup.sh` | cron `@reboot` | Marca como `failed` los heartbeats que quedaron `running`/`queued` tras un reinicio inesperado |
| `maintenance-check.sh` | cron lunes 9am | Detecta updates de hermes-agent/opencode, espera ventana de estabilidad de 5 días, investiga bugs/CVEs vía SearXNG, notifica por Telegram |
| `cleanup-tmp.sh` / cron inline | cron horario | Limpia `.so` temporales de OpenCode que causan ENOSPC en `/tmp` |
| `security-apply-sudo.sh` | manual | Aplica remediaciones de seguridad que requieren sudo (bloque S2) |

### Paperclip (orquestación de agentes)

| Script | Función |
|---|---|
| `paperclip-monitor.sh` | Monitor de Paperclip sin LLM |
| `paperclip-poll-done.sh` / `paperclip-notify-done.sh` | Polling de heartbeats completados + formateo legible |
| `paperclip-usage.sh` | Reporte semanal de tokens (lee `heartbeat_runs.usage_json` directo de la DB) |
| `paperclip-mcp-<slug>.sh` | Levantan el servidor MCP de Paperclip por empresa |
| `playwright-mcp.sh` | Playwright MCP headless: navegación web, screenshots, accessibility tree para agentes IA |
| `sync-agent-instructions.sh` | Reconcilia instrucciones de agentes con la DB |
| `deploy-agent-prompts.sh` | Despliega `promptTemplate` (S1 contrato + S2 reglas empresa + S3 rol) vía DB |

### Multi-empresa / Knowledge Management

| Script | Disparador | Función |
|---|---|---|
| `onboard-company.sh` | manual | Onboarding completo de empresa nueva (aislamiento en todas las capas) |
| `sync-company.sh <slug>` | cron escalonado por empresa (minutos distintos para evitar solapamiento) | entradas/ → validar → issue → contenedor → outputs/ → repo. Config en `stacks/sync-config/<slug>.json` |
| `sync-<slug>-knowledge.sh` | manual | Sync específico de una empresa: contenedor↔repo de contenido propio |
| `sync-outline.sh` | (obsoleto — Outline retirado; la visibilidad la da Odysseus sobre knowledge/) |
| `weekly-ingest.sh <uuid>` | cron domingo (escalonado por empresa) | Ingesta semanal de KM por empresa (Fase 6) |
| `nlm-sync.sh` | manual | Sync semi-manual knowledge → cuaderno NotebookLM (Fase 5) |
| `nlm-distill.sh` | manual | Destilación batch: cuaderno NLM → knowledge curado |

### Orquestación de agentes (Horizonte 1)

| Script / servicio | Función |
|---|---|
| `tmux-gateway` (systemd user) | API REST :8680 para crear/listar/matar sesiones tmux de agentes — 24 endpoints |
| `tmux-bridge-mcp` (MCP stdio) | 9 tools MCP para comunicación inter-agente via paneles tmux |
| `clawhip` (systemd user) | Daemon Rust que monitorea output tmux: detecta keywords y sesiones idle → eventos JSONL |
| `clawhip-dispatch.sh` (systemd user) | Watcher de eventos clawhip (tail -F): cooldown dedup + enrutamiento a telegram-notify.sh |

### Sesión / utilidades

| Script | Función |
|---|---|
| `lab-session.sh` | Sesión tmux persistente (ventanas: trabajo/hermes/paperclip/monitor); `--boot` para cron sin attach |
| `create-routine.sh` | Crea rutinas (cron-agents de Paperclip) |
| `telegram-notify.sh` | Punto único de notificación Telegram (lee `~/.hermes/.env`), usado por casi todos los demás scripts |

### Stacks standalone (`~/ai-lab/stacks/`)

No son scripts sueltos sino mini-servicios con su propio `docker-compose.yml`/app:

| Stack | Contenido |
|---|---|
| `mem0/` | `app.py` + `Dockerfile` + `docker-compose.yml` — wrapper FastAPI que corre como contenedor `mem0` |
| `nlm-gateway/` | `app.py` + `start.sh` + `notebooks.yaml` — gateway HTTP a NotebookLM (puerto 8770, bare-metal, cron `@reboot sleep 20`) |
| `outline/` | compose del wiki Outline (retirado, referencia) |
| `paperclip-config/` | `opencode.jsonc` — config compartida de los agentes Paperclip |
| `sync-config/` | `<slug>.json` por empresa — config que lee `sync-company.sh` |

### Fuera de `ai-lab/` por completo

- `hermes.service` (systemd, `Restart=always`) — `ExecStart=/usr/local/bin/hermes-start.sh`, único servicio bare-metal fuera de Docker, lee `~/.hermes/.env`

### Cron — fuente de verdad

Ver siempre `crontab -l`. Los scripts arriba documentan *qué hace cada uno*, no el
horario exacto (que puede cambiar). `systemctl list-timers` no tiene nada propio del
lab — toda la automatización propia vive en `crontab -l` + `hermes.service`.

**Explícitamente fuera de este inventario:** `repos/{hermes-agent,paperclip,ai-lab-bootstrap,lab-private}/scripts/`
son scripts del código fuente de cada repo (build/test/release upstream), no
automatización operativa del lab.

---

## Variante Windows (nativo)

En Windows 10/11, el lab corre **100% nativo** (sin WSL2, sin Docker).
Todos los servicios se gestionan con **Servy** como service manager.
Guia completa de instalacion: `docs/WINDOWS-INSTALL.md`.

### Servicios y puertos

| Servicio | Runtime | Puerto | Servy |
|---|---|---|---|
| Hermes Gateway | bare metal (uv + Python 3.12) | :9119 | HermesGateway |
| Hermes Dashboard | bare metal (uv + Python 3.12) | :9119 | HermesDashboard |
| MoolMesh | bare metal (uv tool) | :5200 | MoolMesh |
| Dagu | binario Go | :8480 | Dagu |
| Uptime Kuma | Node.js | :3001 | UptimeKuma |
| Glance | binario Go | :9000 | Glance |
| Paperclip | Node.js (PG embebido) | :3100 | Paperclip |
| Odysseus | bare metal (uv + Python 3.12) | :7000 | Odysseus |
| Claude Code | interactivo | -- | No |
| OpenCode | interactivo | -- | No |
| Engram | stdio MCP (bajo demanda) | -- | No |
| Playwright MCP | stdio MCP (bajo demanda) | -- | No |
| NotebookLM MCP | stdio MCP (bajo demanda) | -- | No |
| Tailscale | Windows service | -- | No (nativo Windows) |
| SearXNG | **remoto** (no soportado nativo) | -- | No |

### Diferencias clave vs servidor Linux

- **Sin Docker**: Paperclip usa PG embebido (zero-config). Odysseus corre nativo (fork `amish-github/odysseus`)
- **Package manager**: Scoop (no apt). WinGet no funciona en LTSC
- **Service manager**: Servy (no systemd). Comandos: `servy start/stop/restart/list/logs`
- **Python**: uv + Python 3.12 fijado (ChromaDB tiene bugs con 3.14)
- **Terminal**: psmux (no tmux)
- **SearXNG**: consumido remoto via Tailscale (`SEARXNG_URL` en `~/.env_agents`)
- **Firewall**: reglas Windows Firewall para interfaz Tailscale (modulo 05)
- **Defender**: exclusiones para `~/ai-lab` y `~/.local/bin`
- **Suspend**: si Windows duerme, los servicios Servy se detienen
- **VC++ Redistributable**: requerido para PG embebido de Paperclip (modulo 01 lo instala)
