# Runbook — Knowledge Management & Multi-empresa
**Actualizado:** 2026-06-16 · **Sistema:** v3.2 implementado + Engram + MCP Paperclip (ver `KM_PLAN.md`)

Operacion, mantenimiento y recuperacion del sistema de conocimiento del lab.

---

## Mapa rapido

| Que | Donde |
|-----|-------|
| Knowledge multi-empresa (fuente de verdad) | `~/ai-lab/knowledge/companies/<id>/` (+ `shared/`) — sync a Mac/Obsidian |
| Empresas | EXAMPLE `<COMPANY_UUID_1>` (primaria) · Company B `<COMPANY_UUID_3>` |
| Espejos de deliverables | `~/ai-lab/ops/deliverables/` (EXC) · `deliverables-companyb/` (CPB) — cron c/2h |
| Estado incremental | `sessions/.processed.yaml` por empresa + `~/ai-lab/knowledge/.state/` |
| Mem0 (memoria episodica) | `http://127.0.0.1:8765` · datos en `~/ai-lab/stacks/mem0/data/` |
| Outline (wiki publica) | `https://<TAILSCALE_DOMAIN>` (tailscale serve → 127.0.0.1:3010) |
| NLM | Cuadernos: Example Corp `<NLM_NOTEBOOK_ID>` · Infra KM `<NLM_NOTEBOOK_ID>` (IDs tambien en memoria de Hermes) |
| Engram (memoria de proyecto) | `~/.engram/engram.db` (SQLite) — binario `~/.local/bin/engram`, MCP stdio, aislamiento por `project_name` |
| Monitoreo | Uptime Kuma `http://<SERVER_IP>:3001` — 6 monitores + Telegram |
| Hermes <-> Paperclip MCP | 3 instancias stdio (company_a/example/companyb), 21 tools c/u — wrappers en `~/ai-lab/scripts/paperclip-mcp-*.sh` |
| Routines Paperclip | 4 activas (EXAMPLE CEO lun, EXAMPLE Analyst vie, Company A Wiki mie, Company A Content lun) — tabla `routines` |
| Lab knowledge (privado Hermes) | `~/.hermes/memories/` (`memory.md`, `lab-insights.md`) — NUNCA al knowledge compartido |

## Cadencias automaticas

| Cuando | Que | Log |
|--------|-----|-----|
| c/15 min | `paperclip-watchdog.sh` (zombies) | `~/ai-lab/scripts/watchdog.log` |
| c/1 h | limpieza `/tmp/*.so` (bug ENOSPC OpenCode) | — |
| c/2 h | espejo de deliverables por empresa | `~/ai-lab/ops/backup.log` |
| Dom 1:30 | logrotate user-level | — |
| Dom 2:00 | `weekly-ingest.sh <COMPANY_UUID_1>` (sesiones + deliverables + insights + AGENTS.md) | `~/ai-lab/logs/ingest-<COMPANY_UUID_1>.log` |
| Dom 3:30 | `weekly-ingest.sh <COMPANY_UUID_3>` (solo deliverables — ver "atribucion") | `~/ai-lab/logs/ingest-<COMPANY_UUID_3>.log` |
| Mensual MANUAL | `nlm-sync.sh <company> <notebook>` (cookies ~14 dias: `nlm login` antes) | — |
| Semanal MANUAL | Revisar colecciones Borrador en Outline (<15 min) | — |

**Atribucion de sesiones:** las sesiones de Claude Code/OpenCode/Hermes son fuentes DEL HOST
→ se atribuyen a la empresa primaria (EXAMPLE) salvo etiqueta `[company:<id>]` en la sesion.

## Procedimientos

### Onboarding de una empresa nueva (checklist completo)

1. Crear empresa en Paperclip (UI). **Si se clona desde otra: VACIAR los workspaces
   de los agentes nuevos** (la portabilidad copia archivos de la empresa origen):
   `docker exec paperclip-server-1 find /paperclip/instances/default/workspaces/<agent_id> -mindepth 1 -delete`
2. `mkdir -p ~/ai-lab/knowledge/companies/<id8>/{deliverables,sessions,wiki}` (id8 = primeros 8 chars del UUID)
3. `backup-deliverables.sh`: agregar el prefijo de la empresa al `case` de routing
4. `weekly-ingest.sh`: agregar la empresa al `case` de `DELIVERABLES_DIR`
5. Cron: linea nueva escalonada (+30 min de la anterior)
6. Compose de Paperclip: mounts `companies/<id8>` (ro) + `companies/<id8>/wiki` (rw, anidado) + crear `/paperclip/<nombre>-deliverables` en el contenedor + bloque en backup script
7. Plugin LLM Wiki: configurar wiki root `/paperclip/knowledge/companies/<id8>/wiki` para esa empresa (Settings del plugin, panel de la empresa)
8. Mem0: solo convencion — `user_id="company_<id8>"`; actualizar `shared/templates/mem0-namespacing.md`
9. Outline: colecciones `<Empresa>` + `Borrador — <Empresa>` (API: `collections.create`)
10. Completar templates de promptTemplate (S2 empresa + S3 por agente) y desplegar con `deploy-agent-prompts.sh <slug>` (ver `ONBOARDING_AGENTE.md`)
11. NLM: cuaderno propio cuando tenga contenido (`nlm-sync.sh <id8> <notebook_id>`)
12. Kuma: push monitor para su cron cuando importe

### Rebuild del plugin LLM Wiki (tras rebuild de imagen de Paperclip)

La imagen NO compila plugins. El `dist/` esta persistido via mount desde
`~/ai-lab/repos/paperclip/packages/plugins/plugin-llm-wiki/dist` — sobrevive recreates.
Si se pierde (rebuild de imagen + dist borrado del host):
```bash
docker exec -w /app/packages/plugins/plugin-llm-wiki paperclip-server-1 pnpm build
docker cp paperclip-server-1:/app/packages/plugins/plugin-llm-wiki/dist \
  ~/ai-lab/repos/paperclip/packages/plugins/plugin-llm-wiki/dist
# Si el plugin quedo en status=error:
docker exec paperclip-db-1 psql -U paperclip -d paperclip \
  -c "UPDATE plugins SET status='ready', last_error=NULL WHERE plugin_key='paperclipai.plugin-llm-wiki';"
docker compose -f ~/ai-lab/repos/paperclip/docker/docker-compose.yml restart server
# Verificar: docker logs paperclip-server-1 | grep "plugin activated successfully"
```

### Ingest manual / re-proceso

```bash
# Ingest completo de una empresa:
bash ~/ai-lab/scripts/weekly-ingest.sh <COMPANY_UUID>
# Re-procesar una fuente desde cero: borrar su entrada en el .processed.yaml
# correspondiente y re-correr.
```

### Si el ingest del domingo no llego por Telegram

1. Kuma deberia haber alertado
2. `tail -50 ~/ai-lab/logs/ingest-<id>.log` — buscar `ERROR:`
3. Lock huerfano: `ls /tmp/weekly-ingest-*.lock` → borrar si no hay proceso vivo
4. Hermes caido: el script auto-reprograma +30 min via systemd-run

### Backup y restore

- **Postgres Paperclip:** dumps en `~/backups/`.
  Volumen activo: `paperclip_pgdata_v2` (pgvector/pg17).
- **Mem0:** `~/ai-lab/stacks/mem0/data/` — incluir en backups.
- **Outline:** volumenes `outline-pg` y `outline-data`.
- **Knowledge:** esta en Syncthing + entra a repos git.

### Recuperacion de servicios

Todos los contenedores tienen `restart: unless-stopped` + healthchecks; Kuma alerta
por Telegram. Hermes corre bare metal (gateway + dashboard 9119).
Si Mem0 pierde la coleccion (cambio de modelo de embeddings): borrar
`stacks/mem0/data/qdrant` y re-poblar.

## Lecciones operativas (no repetir)

1. **Docker bypassea UFW** — la proteccion de contenedores es el BIND (127.0.0.1 o IP Tailscale), nunca reglas UFW.
2. **postgres alpine→debian** (musl→glibc) corrompe ordenamiento de indices de texto — siempre init limpio + restore, nunca reusar el volumen.
3. **La portabilidad de Paperclip clona workspaces CON contenido** — vaciar al crear empresa desde otra.
4. **`hermes` no esta en PATH** de shells no interactivos — usar `~/.hermes-env/bin/hermes`.
5. **El sandbox de Hermes resuelve `~` a `~/.hermes/home/`** — rutas absolutas en su memoria y prompts.
6. **El plugin de Google de Outline rechaza Gmail personal** — usar Google como OIDC generico.
7. **La imagen de Paperclip no compila plugins** — ver procedimiento de rebuild arriba.
8. **Contenedor→host bloqueado por UFW** aunque el servicio escuche en 0.0.0.0 — regla explicita para `172.16.0.0/12` al puerto que corresponda.
9. **La memoria REAL de Hermes es `MEMORY.md`** (MAYUSCULAS, con .lock, secciones) — `memory.md` (minusculas) NO se carga en contexto.
10. **El "always-inject" real de los agentes es `promptTemplate` en la DB** (campo JSONB en `adapter_config`).
11. **Los cron jobs de Hermes son consumidores invisibles** — viven en `~/.hermes/cron/jobs.json`, NO en el crontab del sistema. Al cambiar binds/endpoints/keys, revisarlos.
12. **Engram es memoria de PROYECTO, Mem0 es memoria de EMPRESA** — no confundirlos ni duplicar. Engram vive en `~/.engram/engram.db`.
