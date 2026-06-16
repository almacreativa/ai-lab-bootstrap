# Guia del operador — administrar el lab dia a dia
**Actualizado:** 2026-06-16 · Para el humano que opera el laboratorio.

Esto es lo que haces VOS. Lo que hace el sistema solo esta en `KM_RUNBOOK.md`.

---

## Tus puertas de entrada (todas via Tailscale desde el Mac)

| Herramienta | URL / acceso | Para que la usas |
|-------------|--------------|------------------|
| **Hermes (Telegram)** | tu chat del bot | Pedir cosas en lenguaje natural |
| **Hermes dashboard** | `http://<SERVER_IP>:9119` | Ver sesiones y actividad del orquestador |
| **Paperclip** | `http://<SERVER_IP>:3100` | Empresas, agentes, issues, plugins |
| **Outline (wiki)** | `https://<TAILSCALE_DOMAIN>` | Leer la documentacion curada; **revisar los Borradores semanales** |
| **Uptime Kuma** | `http://<SERVER_IP>:3001` | Estado de todos los servicios |
| **Status page** | `http://<SERVER_IP>:3001/status/general` | Tablero de monitores sin login |
| **Portainer** | `https://<SERVER_IP>:9443` | Gestion Docker |
| **NotebookLM** | notebooklm.google.com | Preguntarle al conocimiento en lenguaje natural |
| **Obsidian (Mac)** | carpeta Syncthing "knowledge" | Explorar el knowledge y las wikis EN VIVO |
| **Terminal (SSH/Claude Code)** | `ssh your-server` | Trabajo de ingenieria puntual |
| **Engram TUI** | `engram tui` (en la terminal) | Inspeccionar memorias compartidas entre agentes |

## Donde esta cada documento

| Quiero saber... | Documento |
|-----------------|-----------|
| Como funciona todo el sistema KM | `docs/KM_PLAN.md` |
| Como operar/mantener/recuperar | `docs/KM_RUNBOOK.md` |
| Por que se decidio X | `docs/DECISIONES_KM.md` |
| Estado de seguridad | `docs/SECURITY_STATUS.md` |
| Donde vive cada secret | `docs/SECRETS_INVENTORY.md` |
| Que servicios corren y donde | `docs/SERVICIOS.md` |
| Como crear una empresa/cliente | `docs/ONBOARDING_EMPRESA.md` + `scripts/live/onboard-company.sh` |
| Como crear/modificar un agente | `docs/ONBOARDING_AGENTE.md` + `scripts/live/deploy-agent-prompts.sh` |
| Operaciones de DB | `docs/DB_OPERATIONS.md` + `scripts/live/create-routine.sh` |
| Que modelos usa cada agente | `knowledge/shared/model-map.md` |
| La historia (planes viejos) | `archive/` |

> Clona este repo (`gh repo clone <GITHUB_USER>/<REPO_NAME>`) y tenes
> toda la documentacion local, siempre actualizada con `git pull`.

## Tu rutina (todo lo demas es automatico)

**Cuando llega un Telegram de alerta** (Kuma o ingest): leer y si hace falta ->
`KM_RUNBOOK.md` § "Si el ingest no llego" o TROUBLESHOOTING.

**Domingo/lunes (2 min):** llegaron los resumenes del ingest semanal por Telegram.

**Semanal (~15 min):** Outline -> colecciones `Borrador — *` -> aprobar/mover/descartar.

**Mensual (~10 min):** `nlm login` (si expiro) + `nlm-sync.sh <empresa> <cuaderno>`.

**Trimestral (~10 min):** auditoria de secrets (`SECRETS_INVENTORY.md`),
revisar fuentes de conocimiento, y `engram stats` + `engram doctor`.

**Cuando abris un cliente/empresa nuevo:** `bash ~/ai-lab/scripts/onboard-company.sh "Nombre"`

## Los tres caminos para pedir trabajo

1. **Hermes por Telegram** — orquestacion y tareas del lab. Hermes controla Paperclip
   via MCP (21 herramientas por empresa).
2. **Paperclip (UI o via Hermes)** — trabajo de negocio por empresa. Los agentes
   arrancan con su contexto via `promptTemplate` en DB. Modificar: editar templates
   en `~/ai-lab/knowledge/shared/templates/` y correr `deploy-agent-prompts.sh`.
   **Routines** (trabajo recurrente): routines activas crean issues automaticamente.
3. **Claude Code / OpenCode (terminal)** — ingenieria del lab. Sus sesiones se
   destilan solas al knowledge semanalmente. Comparten memoria de proyecto via
   **Engram** (MCP stdio).

## Como se mantiene actualizada esta documentacion

Despues de cambios de infraestructura:
```bash
cd ~/ai-lab/repos/<REPO_NAME> && bash scripts/sync-from-live.sh
git diff
git add -A && git commit -m "..."  && git push
```
El hook pre-commit bloquea secrets automaticamente.
