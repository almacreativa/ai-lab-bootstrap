# Flujo: crear una empresa nueva (cliente) en el lab
**Actualizado:** 2026-06-16 · Script: `~/ai-lab/scripts/onboard-company.sh`

El objetivo de este flujo es que la información nazca y se mantenga **saludable**:
cada empresa aislada en todas las capas, con su conocimiento acumulándose solo,
sin contaminación cruzada. Probado con el onboarding real de la segunda empresa.

## Visión: qué se crea para cada empresa

| Capa | Artefacto | Aislamiento |
|------|-----------|-------------|
| Paperclip | empresa + agentes + `issue_prefix` | nativo (DB multi-tenant) |
| Knowledge | `~/ai-lab/knowledge/companies/<id8>/{deliverables,sessions,wiki}` | carpeta propia; el contenedor solo monta la suya |
| promptTemplate | `adapter_config.promptTemplate` en DB (S1+S2+S3) | templates en `knowledge/shared/templates/` |
| Espejos | `~/ai-lab/ops/deliverables-<slug>/` | routing por `issue_prefix` |
| Ingest | entrada en el `case` de `weekly-ingest.sh` + cron escalonado | estado incremental propio |
| Mem0 | namespace `user_id="company_<id8>"` | convención + verificado por búsqueda |
| Outline | colección `<Empresa>` (espejo automático via `sync-outline.sh`) | colección propia + UUID en `.outline-collections.env` |
| Plugin LLM Wiki | wiki root `/paperclip/knowledge/companies/<id8>/wiki` (rw) | configuración por empresa |
| NLM | cuaderno propio (cuando hay contenido) | cuaderno por empresa |

## Paso 0 — Crear la empresa en Paperclip (UI)

Settings → Companies → crear. **Si se usa la portabilidad/clonado desde otra
empresa: los workspaces de los agentes nuevos nacen con LOS ARCHIVOS de la empresa
origen** (lección aprendida con datos reales). El script lo detecta y ofrece vaciarlos.

## Paso 1 — Correr el script

```bash
bash ~/ai-lab/scripts/onboard-company.sh "Mi Empresa"
```

Automatiza: detección de UUID/prefijo, limpieza opcional de workspaces clonados,
carpetas de knowledge, routing de espejos, mapa del ingest, cron escalonado,
colecciones de Outline, doc de namespace Mem0, AGENTS.md esqueleto,
plantilla S2 de empresa y esqueletos S3 por agente (promptTemplate). Todo idempotente.

## Pasos manuales (el script los imprime con valores ya resueltos)

### A) Mounts en el compose de Paperclip
Dos líneas en `volumes:` del server — **el curado (ro) antes del wiki (rw)**:
```yaml
- ${HOME}/ai-lab/knowledge/companies/<id8>:/paperclip/knowledge/companies/<id8>:ro
- ${HOME}/ai-lab/knowledge/companies/<id8>/wiki:/paperclip/knowledge/companies/<id8>/wiki
```
`docker compose up -d server` + crear el dir compartido de deliverables en el contenedor.
**Por qué importa:** los agentes comparten contenedor con bash/file tools — lo que no
está montado es lo único que de verdad no pueden leer (ver ADR #11 en `DECISIONES_KM.md`).

### B) Bloque de sync del dir compartido en `backup-deliverables.sh`
Copiar el bloque `if docker exec ... test -d /paperclip/<slug>-deliverables` existente.

### C) Plugin LLM Wiki (UI, panel de la empresa)
`Local wiki folder = /paperclip/knowledge/companies/<id8>/wiki` → Health check 3× Yes.
El plugin crea su esqueleto (raw/, wiki/, AGENTS.md propio de trabajo, log, index).

### D) Instrucciones de los agentes — promptTemplate en DB

> **Cambio junio 2026:** las instrucciones ya NO van en AGENTS.md del filesystem
> (falla en heartbeats por timer — bug #1495). Van en `promptTemplate` dentro de
> `adapter_config` en la DB, inyectado por el server en cada heartbeat sin excepción.

El script `onboard-company.sh` (pasos 9.5 y 9.6) crea automáticamente:
- **Sección 2** (empresa): `~/ai-lab/knowledge/shared/templates/prompt-section2-<slug>.md`
  — identidad de la empresa, reglas de output, convenciones generales.
- **Secciones 3** (agentes): `~/ai-lab/knowledge/shared/templates/prompt-section3/<slug>-<agente>.md`
  — rol, misión, destinos de output adicionales, instrucciones operativas.

Ambos nacen como esqueletos — **completarlos antes de desplegar**.

La **Sección 1** (contrato de ejecución de Paperclip) es universal y ya existe:
`prompt-section1-execution-contract.md`. No se toca.

### E) Completar templates y desplegar promptTemplate

1. Editar `prompt-section2-<slug>.md` — descripción de la empresa (3 líneas)
2. Editar cada `prompt-section3/<slug>-<agente>.md` — rol, misión, destinos de output
3. Desplegar:
```bash
bash ~/ai-lab/scripts/deploy-agent-prompts.sh <slug>
```
El script ensambla S1+S2+S3, escapa para JSONB, y aplica UPDATE a la DB.
Detalle del mecanismo: `ONBOARDING_AGENTE.md`.

### F) Smoke test (cierra el onboarding)
Tarea a un agente de la empresa:
> (1) Resumí la empresa en 3 líneas (debe conocerla por el promptTemplate).
> (2) Creá un archivo en tu workspace con el resumen.
> (3) wiki_write_page con el resumen. (4) Guardá una memoria en Mem0.

Validar:
- El agente conoce la empresa (→ promptTemplate llegó)
- Archivo en su workspace (`/paperclip/instances/default/workspaces/<AGENT_UUID>/`)
- Archivo sincronizado en `deliverables-<slug>/` después de correr `backup-deliverables.sh`
- Página visible en `companies/<id8>/wiki/` (y en Obsidian)
- Memoria en su namespace y NO en el de otras empresas:
```bash
cd ~/ai-lab/stacks/mem0 && source .env
curl -s -X POST http://127.0.0.1:8765/search -H "Content-Type: application/json" \
  -H "X-API-Key: $MEM0_API_KEY" -d '{"query":"<algo de la prueba>","user_id":"company_<OTRA_EMPRESA>"}'
# → debe dar 0 resultados
```

### G) Diferidos hasta que haya contenido
- Cuaderno NLM propio (`nlm-sync.sh <id8> <notebook_id>`, mensual manual)
- Push monitor en Kuma para su cron
- Si va a manejar datos sensibles de clientes → evaluar sandbox provider (ADR #11)

## Recordatorios de salud de la información

- **Las sesiones del host (Claude Code/OpenCode/Hermes) se atribuyen a la empresa
  primaria** — el trabajo para otra empresa se etiqueta `[company:<id8>]` en la sesión.
- El conocimiento de una empresa nueva crece desde **sus deliverables** (domingo a
  domingo, automático) y su wiki de agentes.
- Nada se comparte entre empresas salvo `knowledge/shared/` (explícito).
- El primer `patterns.md`/`insights.md` destilado: revisión humana de 15 min.
