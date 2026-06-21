# Inventario de servicios — <HOSTNAME>
**Actualizado:** 2026-06-20 (lab-health-check + inventario de automatización)

## Servicios y binds (regla: NADA en 0.0.0.0 salvo SSH con UFW)

| Servicio | Runtime | Puerto / bind | RAM aprox | Acceso |
|----------|---------|---------------|-----------|--------|
| SSH | systemd | 0.0.0.0:22 — UFW: solo Tailscale + LAN | — | Mac/tailnet |
| Hermes gateway + dashboard | bare metal (`$HOME/.hermes-env/bin/hermes`) | 0.0.0.0:9119 — UFW: Tailscale + 172.16/12 (Kuma) | ~200MB | tailnet |
| Paperclip server | Docker | `<SERVER_IP>:3100` | ~1GB (limit 4g) | tailnet |
| Paperclip DB (pgvector/pg17, vol `paperclip_pgdata_v2`) | Docker | `127.0.0.1:5432` | ~170MB | local |
| Mem0 (wrapper FastAPI) | Docker | `127.0.0.1:8765` + red `paperclip_default` (`mem0:8765`) | ~380MB limit | local + contenedores |
| Ollama (nomic-embed-text) | Docker | `127.0.0.1:11434` | ~512MB limit | local + red mem0 |
| Outline | Docker | `127.0.0.1:3010` ← `tailscale serve` → `https://<HOSTNAME>.<TAILSCALE_DOMAIN>` | ~1GB limit | tailnet (HTTPS) |
| Outline Postgres 16 / Redis 7 | Docker | internos | 384/256MB limit | — |
| Uptime Kuma | Docker | `<SERVER_IP>:3001` + redes outline/mem0 | 128MB limit | tailnet |
| SearXNG | Docker | `127.0.0.1:8080` | ~150MB | local |
| Portainer | Docker | `<SERVER_IP>:9443` | ~80MB | tailnet |
| **NLM Gateway** | host (uvicorn, cron @reboot) | 0.0.0.0:8770 — UFW: solo 172.16/12 (contenedores) y local | ~80MB | contenedores Paperclip |
| **Engram** | host (binario Go, stdio MCP bajo demanda) | sin puerto (stdio) | ~5-15MB por sesión, 0 en reposo | Claude Code, OpenCode, Antigravity |
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

`deny incoming` por defecto. Permitidos: 22 (Tailscale `100.64.0.0/10` + LAN `192.168.0.0/24`),
9119 (Tailscale + `172.16.0.0/12` para el monitor de Kuma), 22000 (Tailscale + LAN).
**Importante:** UFW NO protege puertos publicados por Docker — la protección es el bind.
Script idempotente: `~/ai-lab/scripts/security-apply-sudo.sh`.

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
| `sync-agent-instructions.sh` | Reconcilia instrucciones de agentes con la DB |
| `deploy-agent-prompts.sh` | Despliega `promptTemplate` (S1 contrato + S2 reglas empresa + S3 rol) vía DB |

### Multi-empresa / Knowledge Management

| Script | Disparador | Función |
|---|---|---|
| `onboard-company.sh` | manual | Onboarding completo de empresa nueva (aislamiento en todas las capas) |
| `sync-company.sh <slug>` | cron escalonado por empresa (minutos distintos para evitar solapamiento) | entradas/ → validar → issue → contenedor → outputs/ → repo. Config en `stacks/sync-config/<slug>.json` |
| `sync-<slug>-knowledge.sh` | manual | Sync específico de una empresa: contenedor↔repo de contenido propio |
| `sync-outline.sh --all` | cron `15,45 * * * *` | Espejo completo del knowledge a Outline |
| `weekly-ingest.sh <uuid>` | cron domingo (escalonado por empresa) | Ingesta semanal de KM por empresa (Fase 6) |
| `nlm-sync.sh` | manual | Sync semi-manual knowledge → cuaderno NotebookLM (Fase 5) |
| `nlm-distill.sh` | manual | Destilación batch: cuaderno NLM → knowledge curado |

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
| `outline/` | `docker-compose.yml` del wiki Outline |
| `paperclip-config/` | `opencode.jsonc` — config compartida de los agentes Paperclip |
| `sync-config/` | `<slug>.json` por empresa — config que lee `sync-company.sh` |

### Fuera de `ai-lab/` por completo

- `~/<empresa>/ops/backup-deliverables.sh` — cron `0 */6 * * *`, backup global de `deliverables*` por empresa (independiente del real-time que ya maneja `sync-company.sh`)
- `hermes.service` (systemd, `Restart=always`) — `ExecStart=/usr/local/bin/hermes-start.sh`, único servicio bare-metal fuera de Docker, lee `~/.hermes/.env`

### Cron — fuente de verdad

Ver siempre `crontab -l`. Los scripts arriba documentan *qué hace cada uno*, no el
horario exacto (que puede cambiar). `systemctl list-timers` no tiene nada propio del
lab — toda la automatización propia vive en `crontab -l` + `hermes.service`.

**Explícitamente fuera de este inventario:** `repos/{hermes-agent,paperclip,ai-lab-bootstrap,i7local-lab}/scripts/`
son scripts del código fuente de cada repo (build/test/release upstream), no
automatización operativa del lab.
