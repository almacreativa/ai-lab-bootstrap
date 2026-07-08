# El hub de conocimiento: contrato genérico de carpetas

`~/ai-lab/knowledge/` es la fuente de verdad del conocimiento del lab. Este
documento define su taxonomía y el contrato de acceso — genérico para
cualquier instancia, independiente de qué empresas o agentes existan.

## Principios

1. **Todo conocimiento durable termina aquí como markdown.** Los índices
   vectoriales son proyecciones descartables; la memoria operativa de cada
   app se queda en su app.
2. **Cada carpeta tiene UN dueño de escritura** (un pipeline, los agentes, o
   el operador). Dos escritores sobre el mismo archivo = conflicto de sync.
3. **Los agentes escriben aditivo**: archivos nuevos `AAAA-MM-DD_slug.md`,
   nunca edición in-place. El humano consolida. (El versioning staggered de
   90 días de Syncthing es la red de seguridad, no la política.)
4. **Los pipelines escriben atómico**: temp + rename — Syncthing propaga
   mientras se escribe.

## Taxonomía y matriz de acceso

| Carpeta | Contenido | Escribe | Agentes de escritorio (Odysseus) | Sync |
|---|---|---|---|---|
| `projects/` | Planes, diseños, decisiones del lab | Operador + agentes (aditivo) | **RW** | ✅ |
| `research/` | Investigaciones (NotebookLM imports, `odysseus/` cosechado) | Pipelines de cosecha + agentes | **RW** | ✅ |
| `daily/` | Reportes y briefings periódicos | Agentes/crons (aditivo) | **RW** | ✅ |
| `shared/` | Staging colaborativo + `templates/` (prompts S1/S2/S3) | Todos (aditivo) | **RW** | ✅ |
| `<empresa>/entradas/` | Inbox hacia los agentes ejecutores | Operador/Hermes | RO | ✅ |
| `<empresa>/outputs/` | Cosecha de workspaces, wiki y DB de la plataforma ejecutora | SOLO pipelines (sync-company, harvest) | RO | ✅ |
| `companies/<id8>/` | Wiki/sesiones/AGENTS.md por empresa (montados en la plataforma ejecutora) | SOLO esa plataforma y sus pipelines | RO | ✅ |
| `.state/` | Estados incrementales de pipelines | SOLO pipelines del host | RO (y excluido del RAG) | ❌ (`.stignore`) |

**Regla de los mounts** (implementación en compose): base `:ro` + override
`:rw` solo en las carpetas de la primera mitad de la tabla. Así, agregar una
empresa nueva jamás requiere tocar los mounts del escritorio.

## Exclusiones universales (RAG, ingest, o cualquier lector programático)

`.state/`, `.stfolder/`, `.stversions/`, `companies/` (se consume vía la
plataforma ejecutora), `*.sync-conflict-*`, y todo lo que no sea prosa
(`.md`/`.txt`).

## Criterio de admisión de herramientas nuevas

Antes de integrar cualquier herramienta al lab, declarar sus dos canales:
**consumo** (cómo lee el hub: mount, filesystem, sync, entradas/) y
**cosecha** (cómo llega su producción al hub: pipeline, escritura RW,
harvest). Una herramienta sin canal de cosecha es un silo; una sin canal de
consumo trabaja a ciegas. El guard del lab detecta `*.sync-conflict-*` como
señal de que alguien violó el contrato de escritura.
