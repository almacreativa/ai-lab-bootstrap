# Flujo: alta de un agente nuevo en Paperclip
**Actualizado:** 2026-06-16 · Script: `~/ai-lab/scripts/deploy-agent-prompts.sh`

Cómo crear un agente (CMO, Coder, Analyst...) en una empresa existente, de modo
que nazca conociendo las reglas y herramientas del entorno.

## Cómo funciona por debajo (el mecanismo)

Las instrucciones de cada agente se entregan via `promptTemplate` en
`adapter_config` (tabla `agents` en la DB de Paperclip). El server inyecta este
campo en cada heartbeat — tanto por timer como por assignment — sin depender del
filesystem. Esto reemplaza el mecanismo anterior de AGENTS.md, que fallaba en
heartbeats por timer (bug #1495: `resolveWorkspaceForRun` ignora `adapterConfig.cwd`).

El promptTemplate se ensambla de 3 secciones:

| Sección | Qué contiene | Quién la mantiene |
|---------|-------------|-------------------|
| **S1** | Contrato de ejecución de Paperclip (dispositions, child issues, interactions) | Universal — no tocar |
| **S2** | Identidad de empresa, reglas de output, convenciones | Una por empresa |
| **S3** | Rol, misión, destinos de output adicionales, instrucciones operativas | Una por agente |

Templates canónicos en `~/ai-lab/knowledge/shared/templates/`:
```
prompt-section1-execution-contract.md          # S1 (universal)
prompt-section2-<empresa-slug>.md              # S2 por empresa
prompt-section2-template.md                   # S2 esqueleto para empresas nuevas
prompt-section3/<empresa>-analyst.md           # S3 por agente
prompt-section3/<empresa>-ceo.md
...etc
```

El script `deploy-agent-prompts.sh` concatena S1+S2+S3, escapa para JSONB,
y aplica UPDATE a la DB. Modos: `all`, `<empresa>`, `<empresa> <agente>`.

## El alta, paso a paso

1. **Crear el agente en la UI de Paperclip** (en la empresa que corresponda):
   - **Rol y descripción**: qué hace, qué NO hace, a quién reporta
   - **Modelo**: seleccionar según la complejidad del rol (razonamiento para agentes core,
     modelos más ligeros para tareas simples como wiki o análisis ligero)
   - **Presupuesto mensual**: ponerlo SIEMPRE (control de costos por agente)
2. **Si el agente fue clonado/portado**: vaciar su workspace (hereda archivos del
   origen — lección conocida):
   `docker exec paperclip-server-1 find /paperclip/instances/default/workspaces/<AGENT_UUID> -mindepth 1 -delete`
3. **Crear la Sección 3** del agente:
   ```bash
   # Crear el archivo de instrucciones del agente
   vi ~/ai-lab/knowledge/shared/templates/prompt-section3/<empresa>-<agente>.md
   ```
   Contenido mínimo:
   ```markdown
   Your role: <Nombre del rol>

   Mission: <Qué hace este agente, en 1-2 líneas>

   Additional output destinations (besides workspace):
   - <Dónde más deja entregables, ej: knowledge/contenidos/, wiki, etc.>

   Operational instructions:
   - <Reglas operativas específicas del rol>
   ```
4. **Desplegar el promptTemplate**:
   ```bash
   bash ~/ai-lab/scripts/deploy-agent-prompts.sh <empresa> <agente-slug>
   # Ejemplo: bash deploy-agent-prompts.sh mi-empresa analyst
   ```
   El slug del agente es el nombre en minúsculas con espacios reemplazados por guiones
   (ej: "Content Producer" → "content-producer").
5. **Verificar** que se aplicó:
   ```sql
   docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA \
     -c "SELECT LENGTH(adapter_config->>'promptTemplate') FROM agents WHERE name='<Agente>';"
   # Debe dar ~4000-5000 caracteres
   ```
6. **Smoke test** — asignarle una tarea:
   > Resumí la empresa en 3 líneas. Creá un archivo en tu workspace con el resumen.
   > Registrá una memoria en Mem0 con tu rol.

   Verificar:
   - Respuesta correcta (→ conoce la empresa por el promptTemplate)
   - Archivo en su workspace (regla universal de output)
   - Archivo sincronizado en `deliverables-<slug>/` tras correr `backup-deliverables.sh`
   - Memoria en el namespace de SU empresa

## Modificar instrucciones de un agente existente

1. Editar el template S3: `~/ai-lab/knowledge/shared/templates/prompt-section3/<empresa>-<agente>.md`
2. Re-desplegar: `bash ~/ai-lab/scripts/deploy-agent-prompts.sh <empresa> <agente>`
3. El próximo heartbeat ya usa las nuevas instrucciones — no hay cache que invalidar.

Para cambiar reglas a nivel empresa (S2), editar `prompt-section2-<empresa>.md` y
re-desplegar con `deploy-agent-prompts.sh <empresa>` (sin agente = todos los de esa empresa).

## Notas

- **AGENTS.md del filesystem ya no se usa** — fueron renombrados a `.bak`. Si
  necesitás referencia del contenido original, están en el contenedor como
  `AGENTS.md.bak` en la ruta de instrucciones de cada agente.
- La Sección 1 (contrato de ejecución) viene del código fuente de Paperclip
  (`DEFAULT_PAPERCLIP_AGENT_PROMPT_TEMPLATE` en `server-utils.ts`). Si Paperclip
  se actualiza, verificar que el contrato no cambió y actualizar S1 si es necesario.
- Empresa nueva desde cero: ver `ONBOARDING_EMPRESA.md` — `onboard-company.sh`
  crea los esqueletos S2 y S3 automáticamente.
