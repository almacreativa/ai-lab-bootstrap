# Knowledge Management para un lab de agentes — el patrón completo

Arquitectura probada en producción para que los agentes de un laboratorio de IA
(orquestador tipo Hermes, plataforma multi-agente tipo Paperclip, CLIs como
Claude Code/OpenCode) **acumulen conocimiento entre sesiones** en vez de arrancar
de cero cada vez. Multi-empresa desde el día uno.

## El problema

Un lab de agentes quema tokens produciendo trabajo que el siguiente agente no puede
leer. Cada sesión re-descubre el contexto. El conocimiento existe (sesiones, deliverables,
decisiones) pero está atrapado en formatos crudos (JSONL, SQLite, markdown disperso).

## Los tres niveles de trabajo (la clave del diseño)

```
NIVEL LAB — administrar el laboratorio
└── Orquestador (Hermes): conocimiento de infra PRIVADO (su memoria), acceso a todo.

NIVEL EMPRESA — el trabajo de negocio
└── Plataforma multi-agente (Paperclip): agentes AUTÓNOMOS en loops, sin humano presente,
    enjaulados en Docker, multi-tenant. Mayor PRODUCTOR de conocimiento del lab.
    Lectura empaquetada (mounts ro + plugin wiki) · salida controlada (espejos).

NIVEL TAREA — intervenciones puntuales con el humano presente
└── CLIs (Claude Code / OpenCode): lectores ricos (filesystem directo), sus sesiones
    son materia prima del pipeline.
```

La asimetría que importa: los entornos interactivos leen directo; la plataforma
autónoma necesita que el conocimiento le llegue empaquetado y que su producción
salga por canales controlados.

## Arquitectura (una sola dirección de escritura)

```
FUENTES CRUDAS                          DESTILACIÓN                    FUENTE DE VERDAD
sesiones CLI (JSONL/SQLite)  ──┐
sesiones del orquestador     ──┼──► pipeline semanal incremental ──► knowledge/
deliverables de la plataforma ─┘    (cron + LLM gratis + estado)      ├── shared/
                                    ÚNICO ESCRITOR                     └── companies/<id>/
                                                                           ├── AGENTS.md (curado)
                                                                           ├── patterns.md
                                                                           ├── sessions/ (+index)
                                                                           └── wiki/  ← rw agentes
CAPAS DE ACCESO (solo lectura del curado):
• Agentes plataforma → mount ro + plugin LLM Wiki (lectura viva) + wiki/ rw (su trabajo)
• Agentes CLI / orquestador → filesystem directo + AGENTS.md
• Memoria episódica → Mem0 self-hosted (namespace user_id="company_<id>")
• Humanos → wiki pública curada (Outline) · consulta natural (NotebookLM, sync manual)
            · Obsidian en vivo (Syncthing)
```

## Decisiones de diseño (con el porqué)

1. **Pipeline incremental con estado** (`.processed.yaml` con id+hash por fuente):
   nunca reprocesar todo; una corrida sin novedades termina en segundos.
2. **Memoria episódica ≠ conocimiento institucional.** Mem0 guarda hechos/decisiones
   atómicos con recall semántico; el knowledge guarda documentos estructurados. Son
   las dos mitades, no compiten.
3. **Mem0 self-hosted con wrapper FastAPI propio**: LLM de extracción vía cualquier
   API OpenAI-compatible + embeddings locales (Ollama + nomic-embed-text, 768d, CPU)
   + Qdrant embebido file-based. Cero API keys obligatorias. Namespace por empresa.
4. **Atribución de sesiones del host**: las sesiones de los CLIs no traen empresa.
   Default → empresa primaria del lab; etiqueta `[company:<id>]` enruta excepciones
   (clasificador LLM en el ingest del orquestador, que separa además lo "lab admin"
   hacia la memoria privada del orquestador).
5. **Multi-tenant en la plataforma de agentes**: los agentes comparten contenedor y
   tienen bash/file tools ⇒ cualquier enforcement de aplicación es blando. El único
   aislamiento duro sin sandboxes es **no montar lo que no corresponde** (mounts
   granulares por empresa). Upgrade path: sandbox providers cuando haya datos
   sensibles de clientes.
6. **Wiki de trabajo rw anidada dentro del knowledge ro**: el plugin de wiki de los
   agentes necesita escribir (standups, log, ideas). Sub-mount rw `companies/<id>/wiki/`
   dentro del mount ro del curado: colaboran sin poder tocar lo curado, y su wiki es
   una fuente más para la próxima destilación.
7. **Outline es espejo de solo lectura**: `sync-outline.sh` publica directamente a
   Outline con jerarquía completa (docs, knowledge por empresa, deliverables, shared).
   No hay borradores ni edición en Outline — la fuente de verdad es siempre el
   filesystem. Si algo está mal, se corrige en el archivo y se re-sincroniza.
   El ingest semanal incluye el sync automáticamente.
8. **Monitoreo mínimo que alcanza**: Uptime Kuma (50MB) con healthchecks + push
   monitor como dead-man's-switch del cron semanal + notificaciones Telegram.

## Componentes en este repo

| Pieza | Ruta |
|-------|------|
| Stack Mem0 (FastAPI + Ollama + Qdrant embebido) | `stacks/mem0/` |
| Stack Outline (Google como OIDC genérico + Tailscale serve) | `stacks/outline/` |
| Ingest semanal multi-empresa (lock, healthcheck, continuar-ante-fallo, Telegram, Kuma) | `scripts/weekly-ingest.sh` |
| Extractores incrementales de sesiones (Claude Code JSONL, OpenCode SQLite) | `knowledge-pipeline/` |
| Skills de destilación para el orquestador (clasificación lab/empresa, patrones de deliverables) | `skills/` |
| Espejo de deliverables por empresa | `scripts/backup-deliverables.sh` |
| Sync automático a Outline (espejo completo con jerarquía) | `scripts/sync-outline.sh` |
| Sync semi-manual a NotebookLM | `scripts/nlm-sync.sh` |
| Baseline de seguridad (UFW para bare metal — Docker se protege con binds) | `scripts/security-apply-sudo.sh` |

## Orden de implementación recomendado

1. Estructura de knowledge + extractores + primer backfill manual (30 días, LLM gratis)
2. Destilación → `AGENTS.md` + `insights.md` + `patterns.md` por empresa (revisar a mano: es la semilla)
3. Mem0 + integración con cada agente (buscar al arrancar / registrar al cerrar)
4. Plugin de wiki en la plataforma de agentes (mount ro + wiki rw)
5. Cron semanal + monitoreo
6. Capas humanas: Outline + NotebookLM + Obsidian

Ver `LESSONS.md` para los errores que ya cometimos por vos.
