# Operaciones de base de datos — qué está sistematizado y qué no

**Actualizado:** 2026-06-16

Paperclip no expone UI ni API para todas las operaciones. Algunas requieren DB directa.
Este documento registra qué tiene script, qué se hace manual, y los pitfalls de cada una.

---

## Inventario de scripts

| Operación | Script | Estado |
|---|---|---|
| Onboarding empresa completa | `onboard-company.sh "Nombre"` | Automatizado (+ pasos manuales A-H) |
| Deploy instrucciones (promptTemplate) | `deploy-agent-prompts.sh all\|empresa [agente]` | Automatizado |
| Crear routine con trigger y revision | `create-routine.sh PREFIX AGENT TITLE CRON [priority] [desc]` | Automatizado |
| Crear board API key | receta en SKILL.md | Manual con receta |
| Cambiar modelo de agente | SQL con `jsonb_set` | Manual con receta |
| Eliminar agente | SQL manual | Manual (FK constraints) |
| Fix estado corrupto | SQL ad-hoc | Manual |
| Fix issue_counter desincronizado | SQL manual | Manual con receta |

---

## Operaciones sistematizadas (con script)

### 1. Onboarding de empresa (`onboard-company.sh`)

```bash
bash ~/ai-lab/scripts/onboard-company.sh "Nombre de Empresa"
```

Automatiza: empresa en DB, proyecto LLM Wiki, agentes (CEO, CSO, Analyst, Wiki Maintainer), directorios knowledge, cron de ingest semanal, templates S2/S3 esqueleto.

Pasos manuales post-script (A-H): volumes en docker-compose, backup-deliverables, plugin LLM Wiki, completar templates, deploy promptTemplate.

**Pitfall:** NUNCA crear empresa por INSERT directo — faltan 10+ tablas y configuraciones. Ver `ONBOARDING_EMPRESA.md`.

### 2. Deploy de instrucciones (`deploy-agent-prompts.sh`)

```bash
bash ~/ai-lab/scripts/deploy-agent-prompts.sh all        # todas las empresas
bash ~/ai-lab/scripts/deploy-agent-prompts.sh <empresa>  # una empresa
bash ~/ai-lab/scripts/deploy-agent-prompts.sh <empresa> ceo  # un agente específico
```

Ensambla S1 + S2 + S3, escapa para JSONB, aplica UPDATE en `adapter_config.promptTemplate`.

**Pitfall:** Si existe AGENTS.md en el filesystem del contenedor, el agente puede priorizar AGENTS.md sobre promptTemplate. Todos los AGENTS.md están renombrados a `.bak`.

### 3. Crear routine (`create-routine.sh`)

```bash
bash ~/ai-lab/scripts/create-routine.sh <COMPANY_PREFIX> CEO "Informe semanal" "0 9 * * 1"
bash ~/ai-lab/scripts/create-routine.sh <COMPANY_PREFIX> CTO "Revisión técnica" "0 10 1 * *" medium "Descripción"
```

Crea routine + trigger (con `next_run_at` calculado) + revision inicial. Prefijos de empresa: personalizados por instalación (ej: `MIE`, `CLI`, `PRO`).

**Pitfall:** Si se crea el trigger sin `next_run_at`, el scheduler de Paperclip lo ignora (busca `next_run_at IS NOT NULL AND next_run_at <= now()`). El script calcula automáticamente.

---

## Operaciones con receta (manual pero documentada)

### 4. Crear board API key

```bash
# Generar token y hash
TOKEN="pcp_board_$(openssl rand -hex 24)"
HASH=$(echo -n "$TOKEN" | sha256sum | cut -d' ' -f1)

# Insertar en DB
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
INSERT INTO board_api_keys (user_id, name, key_hash, expires_at)
VALUES ('<USER_ID>', 'Nombre', '$HASH', NOW() + INTERVAL '365 days');
"

# Guardar token en .env (NUNCA en git)
echo "PCP_BOARD_KEY=$TOKEN" >> ~/.hermes/.env
```

### 5. Cambiar modelo de agente

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE agents
SET adapter_config = jsonb_set(adapter_config, '{model}', '\"<provider>/<model-name>\"')
WHERE id = '<AGENT_UUID>';
"
```

**Pitfall:** El CEO tiene `canCreateAgents: true` y puede revertir modelos de otros agentes durante heartbeat.

### 6. Fix issue_counter desincronizado

Ocurre cuando se crean issues por INSERT directo (sin API). El `issue_counter` de la empresa no se incrementa, y la API falla con unique constraint al intentar crear el siguiente issue.

```bash
# Ver el issue number más alto
docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA -c "
SELECT MAX(issue_number) FROM issues WHERE company_id='<COMPANY_UUID>';
"

# Actualizar el counter
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE companies SET issue_counter = <max+1> WHERE id = '<COMPANY_UUID>';
"
```

---

## Operaciones sin script (ad-hoc)

### 7. Eliminar agente

FK constraints complejas (`heartbeat_runs`, `issues`, `routine_triggers`, etc.). No hay script genérico porque cada caso puede tener dependencias distintas.

```bash
# Verificar dependencias
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
SELECT 'issues' as tabla, count(*) FROM issues WHERE assignee_agent_id='<AGENT_UUID>'
UNION ALL
SELECT 'heartbeat_runs', count(*) FROM heartbeat_runs WHERE agent_id='<AGENT_UUID>'
UNION ALL
SELECT 'routines', count(*) FROM routines WHERE assignee_agent_id='<AGENT_UUID>';
"
```

### 8. Fix estado corrupto

Sin receta genérica — depende del caso. Errores comunes:
- Heartbeat stuck en `running`: `UPDATE heartbeat_runs SET status='failed' WHERE status='running' AND agent_id='<AGENT_UUID>';`
- Environment lease stuck: `DELETE FROM environment_leases WHERE agent_id='<AGENT_UUID>';`
- Issue stuck en `in_progress`: `UPDATE issues SET status='todo' WHERE id='<AGENT_UUID>';`

Ver `references/zombie-cleanup.md` en el skill de Paperclip.

---

## Routines — cómo funcionan

### Mecánica interna

1. **Scheduler de Paperclip** (proceso interno del server): cada minuto evalúa `routine_triggers` donde `kind='schedule' AND enabled=true AND next_run_at <= now() AND routine.status='active'`
2. **Si hay match**: llama `dispatchRoutineRun()` que:
   - Crea un `routine_run` con status `received`
   - Crea un issue basado en el template de la routine
   - Asigna al agente configurado
   - Calcula el siguiente `next_run_at` y lo guarda en el trigger
   - Si `concurrency_policy='coalesce_if_active'`: si ya hay un issue abierto de esa routine, no crea otro

### Ejemplo de inventory de routines

| Empresa | Routine | Agente | Cron | Ejemplo |
|---|---|---|---|---|
| `<COMPANY_PREFIX>` | Actualización del Wiki LLM | Wiki Maintainer | `0 10 * * 3` (Mié) | semanal |
| `<COMPANY_PREFIX>` | Revisión semanal de métricas | Analyst | `0 14 * * 5` (Vie) | semanal |
| `<COMPANY_PREFIX>` | Producir siguiente módulo | Content Producer | `0 8 * * 1` (Lun) | semanal |
| `<COMPANY_PREFIX>` | Informe semanal de actividad | CEO | `0 9 * * 1` (Lun) | semanal |
| `<COMPANY_PREFIX>` | Revisión técnica mensual | CTO | `0 10 1 * *` (1°) | mensual |

### Routines vs crons del host

| | Routines (Paperclip) | Crons del host |
|---|---|---|
| **Qué hacen** | Crean issues → agente ejecuta | Operan filesystem/git |
| **Ejemplos** | "Producir contenido", "Informe semanal" | backup-deliverables, weekly-ingest |
| **Dónde viven** | DB `routines` + `routine_triggers` | `crontab -l` |
| **Quién las procesa** | Scheduler interno de Paperclip | cron del OS |
| **Complementarios** | Sí — uno no reemplaza al otro | |
