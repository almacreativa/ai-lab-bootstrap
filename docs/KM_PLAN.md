# Plan de Ejecucion — Knowledge Management AI Lab
**Version:** 3.2 (implementado)
**Fecha:** 2026-06-11
**Estado:** IMPLEMENTADO (2026-06-11) — las 8 fases operativas en produccion, multi-empresa real (EXAMPLE + Company B), smoke tests pasados. Pendientes menores listados al final de cada fase.
**Reemplaza a:** ambos documentos anteriores. Este es la unica fuente de verdad del plan.

---

## Vision

Construir un sistema donde cada agente del lab (Hermes, Paperclip, Claude Code, OpenCode) arranque cada sesion con contexto acumulado de trabajo previo, y donde los humanos puedan consultar inteligentemente el conocimiento generado por el lab sin leer archivos manualmente.

**El sintoma que resuelve:** hoy el lab quema tokens produciendo trabajo que el siguiente agente no puede leer. Cada sesion empieza desde cero.

---

## Decisiones de arquitectura (cerradas)

Estas decisiones ya fueron tomadas durante la revision del 2026-06-11 y NO se reabren:

| # | Decision | Resolucion |
|---|----------|------------|
| 1 | Roles | **Hermes es el administrador del lab.** Los demas agentes operan dentro de su empresa. Claude Code / OpenCode acceden a lab knowledge solo bajo demanda para tareas especificas. |
| 2 | Multi-empresa | **Si, desde el dia 1.** Aislamiento total por empresa; solo datos marcados como compartidos cruzan la frontera. Hoy: Example Corp (`<COMPANY_UUID_1>`). |
| 3 | Lab knowledge | **Privado de Hermes.** Vive en `~/.hermes/memories/` + `SOUL.md`, NO en `~/example/knowledge/` compartido. |
| 4 | Memoria episodica | **Mem0** (MIT, ~200MB, API REST, namespacing nativo por `user_id`). Hindsight descartado (solo Paperclip), Zep descartado (CE deprecado desde abril 2025, requiere Neo4j + OpenAI API key). |
| 5 | Embeddings | **Locales** — nomic-embed-text via Ollama (~300MB). Cero API keys externas. |
| 6 | Backend vectorial | **Qdrant embebido en Mem0** (no servicio separado — un contenedor menos que mantener; se migra a Qdrant standalone solo si el volumen lo exige). |
| 7 | Outline (Fase 7) | **Se implementa desde el inicio**, en paralelo. ~1.1GB de RAM con 11GB libres no es problema. Independiente de las demas fases. |
| 8 | Motor de destilacion | **opencode-zen** (`opencode/deepseek-v4-flash-free`, gratis) para destilacion rutinaria. `deepseek-v4-pro` (opencode-go, pago) solo para destilacion pesada puntual. |
| 9 | Pipeline | **Incremental con estado** (`.processed.yaml`). Nunca reprocesar todo. |
| 10 | Clasificacion de sesiones de Hermes | **Dual:** etiquetado en origen (`[company:<COMPANY_UUID_1>]`) + inferencia automatica en el ingest como fallback. |
| 11 | Backfill (primer run) | **Manual y supervisado**, ultimos 30 dias, con modelo gratis. |
| 12 | Manejo de fallos en cron | **Continuar siempre:** log del error + notificacion Telegram + seguir con el paso siguiente. Lock file contra ejecucion concurrente. Healthcheck de Hermes con reintento a 30 min. |
| 13 | Monitoreo | **Uptime Kuma** (~50MB) — monitorea servicios HTTP + dead-man's-switch de los cron jobs via push. Netdata queda como opcional futuro, no se instala ahora. |
| 14 | NotebookLM | Capa de consulta humana/agente, **sync mensual semi-manual** (cookies expiran ~14 dias). Un cuaderno por empresa + uno opcional privado del lab. Nunca en pipeline automatizado. |

### Verificaciones de entorno (2026-06-11, sobre el servidor real)

| Hecho verificado | Implicacion |
|------------------|-------------|
| Hermes corre en **bare metal** (`~/.hermes-env/bin/hermes`, gateway + dashboard activos) | Todos los comandos `hermes ...` van directo en el host, sin `docker exec` |
| Docker activo: `paperclip-server-1`, `paperclip-db-1` (postgres:17-alpine), `searxng`, `portainer` | No existe contenedor de Hermes. El Postgres de Paperclip se llama `paperclip-db-1`, usuario `paperclip` |
| **pgvector NO instalado** en `paperclip-db-1` (la imagen alpine no lo trae) | El KB plugin de Paperclip lo necesita — ver F2.1 |
| Skills `hermes-history-ingest` y `wiki-ingest` **NO instalados** en `~/.hermes/skills/` | F0.4 los instala o los crea — pendiente D del feedback resuelta |
| Modelo gratis configurado: `opencode/deepseek-v4-flash-free` (provider opencode-zen) | Los comandos usan este modelo, no `big-pickle` |
| **Ollama NO instalado** en el host (solo provider `ollama-cloud` en Hermes) | F1 incluye deploy de Ollama local para embeddings |
| RAM: 15GB total, ~3.9GB en uso, **~11GB disponibles**, swap 4GB sin uso | Hay espacio de sobra para todo el stack nuevo (~1.7GB) |
| `~/example/knowledge/` existe pero esta **vacio** | Se crea la estructura por empresa directamente, sin migracion |

---

## Artefactos del plan (generados y probados el 2026-06-11)

Todo el codigo y la configuracion del plan ya existe en el servidor. Ninguna fase
requiere "escribir un script" — solo ejecutar, configurar secrets y validar.

| Artefacto | Ubicacion | Fase | Estado |
|-----------|-----------|:----:|--------|
| Skill destilacion sesiones Hermes | `~/.hermes/skills/knowledge/hermes-history-ingest/SKILL.md` | F3/F6 | Instalado |
| Skill destilacion deliverables | `~/.hermes/skills/knowledge/wiki-ingest/SKILL.md` | F3/F6 | Instalado |
| Modulo comun (estado, frontmatter, index) | `~/shared/demos/process_sessions/km_common.py` | F3/F4 | Probado |
| Extractor Claude Code | `~/shared/demos/process_sessions/claude_code_extract.py` | F3 | Probado con datos reales |
| Extractor OpenCode | `~/shared/demos/process_sessions/opencode_extract.py` | F4 | Probado con datos reales (incremental OK) |
| Stack Mem0 (wrapper FastAPI + Ollama + Qdrant embebido) | `~/ai-lab/stacks/mem0/` | F1 | Escrito — falta `.env` y deploy |
| Stack Outline (compose + auth resuelto) | `~/ai-lab/stacks/outline/` | F7 | Escrito — falta `.env`, Tailscale HTTPS y Google OAuth |
| Ingest semanal | `~/ai-lab/scripts/weekly-ingest.sh` | F6 | Escrito — falta `.env` (Telegram/Kuma) y cron |
| Sync a NotebookLM | `~/ai-lab/scripts/nlm-sync.sh` | F5 | Escrito — usa el CLI `nlm` |
| Cuaderno NLM de documentacion tecnica | NLM `<NLM_NOTEBOOK_ID>` ("AI Lab — Infraestructura KM") | ref | Creado con 8 fuentes (docs Mem0, Outline, Tailscale, Uptime Kuma) |

**Nota de diseno:** `process_sessions.py` NO se modifica — queda como herramienta de
reporting. El pipeline KM usa `claude_code_extract.py` (extractor liviano dedicado,
mismo modulo de estado que `opencode_extract.py`).

**Correccion al feedback:** las sesiones de Hermes son JSONL en `~/.hermes/sessions/`
(no SQLite). El skill `hermes-history-ingest` ya lo refleja.

### Que es humano y que es agentico

| Paso | Quien | Detalle |
|------|-------|---------|
| Secrets (`.env` de mem0, outline, scripts) | HUMANO | `openssl rand` + API keys. Nunca delegar secrets a agentes. |
| Google OAuth (consola de Google Cloud) | HUMANO | ~10 min, pasos en `~/ai-lab/stacks/outline/README.md` |
| `tailscale serve` + HTTPS | HUMANO | 1 comando, requiere sudo |
| `nlm login` cuando expiren cookies (~14 dias) | HUMANO | Prerequisito de cada `nlm-sync.sh` |
| Activar plugins en UI de Paperclip (F2.2) | HUMANO | Settings — Plugins |
| Revision de calidad post-ingest (F3.6) y revision semanal de borradores (F7) | HUMANO | <15 min/semana |
| Deploy de stacks, primer backfill, cron, pruebas de humo | AGENTE | Comandos ya escritos en este plan y en los READMEs |
| Ingest semanal recurrente | AUTOMATICO | cron + `weekly-ingest.sh` (con lock, healthcheck y alertas) |

---

## Arquitectura en una pagina

```
ROLES
─────
┌──────────────────────────────────────────────────────────────┐
│ HERMES — administrador del lab (bare metal)                  │
│ • Lab knowledge: ~/.hermes/memories/ + SOUL.md (PRIVADO)     │
│ • Orquesta, delega a Paperclip / Claude Code / OpenCode      │
└──────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│ PAPERCLIP — workflow empresarial (Docker, multi-empresa)     │
│ • Empresa Example Corp (<COMPANY_UUID_1>) + futuras          │
│ • No ven datos de otras empresas                             │
└──────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│ CLAUDE CODE / OPENCODE / ANTIGRAVITY — tareas delegadas      │
│ • Contexto de empresa via AGENTS.md por empresa              │
│ • Lab knowledge solo bajo demanda                            │
└──────────────────────────────────────────────────────────────┘

FUENTES (lo que se genera)
──────────────────────────
Paperclip deliverables  →  ~/example/ops/deliverables/example-deliverables/  [rsync 2h]
Claude Code sessions    →  ~/.claude/projects/**/*.jsonl
OpenCode sessions       →  ~/.local/share/opencode/opencode.db (SQLite)
Hermes sessions         →  ~/.hermes/sessions/ (mixtas: lab + empresa → clasificador)
Sesiones nocturnas      →  ~/ai-lab/workspace/noche-*/

      ↓  DESTILACION incremental con estado (.processed.yaml)
      ↓  Motor: opencode-zen deepseek-v4-flash-free ($0)

~/example/knowledge/
├── shared/                    ← patrones y templates multi-empresa
└── companies/<COMPANY_UUID_1>/        ← AISLADO por empresa
    ├── AGENTS.md              ← contexto de la empresa (≤500 palabras)
    ├── sessions/              ← index.md + archivos cronologicos + insights.md
    ├── deliverables/
    └── patterns.md

Lab admin → ~/.hermes/memories/ (privado, NO al filesystem compartido)

      ↓  MEMORIA EPISODICA (transversal)

Mem0 (API REST) + Ollama nomic-embed-text + Qdrant embebido
Namespace: user_id="company_<COMPANY_UUID_1>"
→ Hermes, Paperclip, Claude Code, OpenCode: todos leen/escriben

      ↓  ACCESO

Agentes Paperclip → KB plugin (por empresa) + Mem0
Claude / OC / AG  → companies/<id>/AGENTS.md + Mem0
Hermes            → memories propias + Mem0 + acceso admin a todo
Humanos           → NotebookLM (1 cuaderno/empresa, sync mensual manual)
                  → Outline (wiki publica, colecciones por empresa)
                  → Obsidian en Mac (via Syncthing)
```

---

## Estructura de `~/example/knowledge/` (definitiva)

```
~/example/knowledge/
├── shared/                           ← conocimiento multi-empresa
│   ├── templates/                    ← estructuras reutilizables
│   └── patterns.md                   ← patrones transversales
└── companies/
    ├── <COMPANY_UUID_1>/             ← Example Corp
    │   ├── AGENTS.md                 ← contexto de la empresa
    │   ├── patterns.md               ← patrones de deliverables
    │   ├── deliverables/             ← assets destilados
    │   └── sessions/
    │       ├── .processed.yaml       ← estado del pipeline (incremental)
    │       ├── index.md              ← indice liviano (~2KB) consultable por agentes
    │       ├── claude-code-YYYY-MM-DD.md
    │       ├── opencode-YYYY-MM-DD.md
    │       ├── hermes-YYYY-MM-DD.md
    │       └── insights.md           ← acumulativo, solo lo mas relevante
    └── (futuras empresas)/
```

**Convencion de formato:** todo archivo destilado lleva frontmatter YAML:

```yaml
---
source: opencode | claude_code | hermes | paperclip
company_id: <COMPANY_UUID_1>
date: 2026-06-11
model: deepseek-v4-flash-free
topics: [tema1, tema2]
---
```

> **Other Project es un proyecto aparte**, no una empresa del lab. Su conocimiento vive en `~/ai-lab/repos/other-project/` y no entra a este pipeline.

---

## Tabla de empresas

| Empresa | ID | Prefijo | Descripcion | Estado |
|---------|-----|---------|-------------|--------|
| Example Corp | `<COMPANY_UUID_1>` | EXC | **Empresa primaria del lab.** Las fuentes del host (sesiones CC/OC/Hermes) se le atribuyen por defecto. | Activa |
| Company B | `<COMPANY_UUID_3>` | CPB | Empresa operativa real (creada 2026-06-11). Conocimiento solo desde sus deliverables de Paperclip; sesiones del host solo si van etiquetadas `[company:<COMPANY_UUID_3>]`. Workspaces limpiados post-clonado. | Activa |

> **Reestructura 2026-06-11:** el knowledge y ops multi-empresa viven en `~/ai-lab/knowledge/`
> y `~/ai-lab/ops/` (canonicos, neutrales — `~/ai-lab/knowledge` se sincroniza al Mac/Obsidian
> via Syncthing). `~/example/knowledge` y `~/example/ops` quedaron como symlinks de compatibilidad;
> `~/example/` es solo negocio de EXAMPLE. Deliverables por empresa: `ops/deliverables/` (EXC) y
> `ops/deliverables-companyb/` (CPB), enrutados por `issue_prefix` en `backup-deliverables.sh`.
> **Leccion registrada:** la portabilidad de Paperclip clona workspaces CON contenido —
> al crear una empresa desde otra, vaciar los workspaces de los agentes nuevos antes de operar.

---

## Fases de implementacion

```
Fase 0: Fundamentos
    ├── Fase 1: Mem0 (memoria episodica transversal)
    ├── Fase 2: Contexto institucional (KB plugin + AGENTS.md por empresa)
    └── Fase 3: Motor de destilacion (incremental, por empresa)
              ├── Fase 4: Extractor OpenCode (+ Antigravity)
              ├── Fase 5: NotebookLM por empresa
              └── Fase 6: Automatizacion semanal + Uptime Kuma

Fase 7: Outline ──── INDEPENDIENTE, arranca en paralelo desde el dia 1
```

Las Fases 1, 2 y 3 son independientes entre si. La Fase 7 no depende de ninguna.

**Prioridad recomendada:** F0 → F2 (maximo impacto inmediato: contexto institucional) → F3 → F1 → F4 → F5/F6. F7 en paralelo cuando convenga.

> El contexto institucional (F2) es mas urgente que la memoria episodica (F1). Un agente que no entiende el lab arranca en blanco cada vez; la memoria episodica es valiosa pero no critica.

---

### Fase 0 — Fundamentos y verificacion de prerequisitos
**Esfuerzo estimado:** 2-3 horas
**Prerequisito de:** Fases 1-6

- [x] **F0.1** Estructura de directorios por empresa — **RESUELTO:**
  creados `~/ai-lab/knowledge/shared/templates/`, `~/ai-lab/knowledge/companies/<COMPANY_UUID_1>/{deliverables,sessions}/`

- [x] **F0.2** opencode-zen verificado — **RESUELTO:**
  `~/.hermes-env/bin/hermes chat --provider opencode-zen`.
  **Nota:** usar siempre la ruta completa `~/.hermes-env/bin/hermes` — no esta en
  el PATH de shells no interactivos (cron, agentes).

- [x] **F0.3** Skills de ingest — **RESUELTO:**
  `~/.hermes/skills/knowledge/{hermes-history-ingest,wiki-ingest}/SKILL.md`

- [x] **F0.4** Conectividad NLM verificada — **RESUELTO:** `nlm notebook list`
  responde OK (cookies frescas). El MCP esta declarado en `~/.hermes/config.yaml`.

- [ ] **F0.5** Test integrado
  Crear un archivo de prueba en el knowledge de la empresa y verificar que Hermes puede leerlo.

**Validacion:** todos los checkboxes sin errores.

---

### Fase 1 — Memoria episodica transversal (Mem0)
**Esfuerzo estimado:** 4-8 horas
**Prerequisito:** Fase 0

- [x] **F1.1** Stack Mem0 + Ollama — endpoint verificado, stack arriba con safeguards y binds 127.0.0.1.

- [x] **F1.2** Smoke test — add → extraccion OK; search en namespace correcto → resultado; otro namespace → 0 (aislamiento OK); sin API key → 401 (auth OK).

- [x] **F1.3** Namespacing documentado — convencion completa en `shared/templates/mem0-namespacing.md`.

- [x] **F1.4** Integracion con Hermes — `MEM0_API_KEY` en `~/.hermes/.env` (600).

- [x] **F1.5** Integracion con Paperclip (networking) — `mem0` conectado a la red `paperclip_default`; verificado `http://mem0:8765/health` desde dentro de `paperclip-server-1`.

- [x] **F1.6** Prueba de humo — recall entre llamadas, aislamiento entre namespaces y auth verificados.

---

### Fase 2 — Contexto institucional (KB plugin + AGENTS.md por empresa)
**Esfuerzo estimado:** 4-6 horas
**Prerequisito:** Fase 0 (Fase 1 NO es prerequisito)

- [x] **F2.1** pgvector — migracion a `pgvector/pgvector:pg17` con init limpio + restore.

- [x] **F2.2-F2.4** Contexto en Paperclip — **RESUELTO con LLM Wiki**
  Plugin instalado y activo. Configurado POR EMPRESA.

- [ ] **F2.5** AGENTS.md por empresa para los CLIs

- [ ] **F2.6** Consolidar lab knowledge en la memoria de Hermes

- [x] **F2.7** Prueba de humo — agentes reales de Paperclip leyeron el AGENTS.md curado.

---

### Fase 3 — Motor de destilacion (incremental, por empresa)
**Esfuerzo estimado:** 6-9 horas
**Prerequisito:** Fase 0

**Requisito de diseno — pipeline con estado:**

```
Cada corrida:
  1. Lee .processed.yaml → que sesiones ya se procesaron (id + hash)
  2. Procesa SOLO lo nuevo o modificado
  3. Los insights nuevos se AGREGAN (nunca sobrescribir insights.md)
  4. Actualiza index.md y .processed.yaml
```

- [x] **F3.1** Extractor de Claude Code — creado y probado.
- [x] **F3.2** Ingest de deliverables — ejecutado.
- [x] **F3.3** Ingest de sesiones de Hermes — ejecutado.
- [x] **F3.4** Primer ingest de Claude Code + OpenCode — ejecutado.
- [ ] **F3.5** Generar AGENTS.md de la empresa
- [ ] **F3.6** Revision humana de calidad

---

### Fase 4 — Extractor de OpenCode (+ Antigravity)
**Esfuerzo estimado:** 3-5 horas
**Prerequisito:** Fase 3

- [ ] **F4.1** Explorar esquemas
- [x] **F4.2** `opencode_extract.py` — creado y probado.
- [ ] **F4.3** Integrar al pipeline de ingest
- [x] **F4.4** Antigravity — verificado: sin datos locales. Placeholder.

---

### Fase 5 — NotebookLM por empresa
**Esfuerzo estimado:** 2-4 horas
**Prerequisito:** Fase 3

- [x] **F5.1** Cuaderno creado
- [x] **F5.2** Primera carga — 4 fuentes subidas via MCP
- [x] **F5.3** Calidad verificada
- [x] **F5.4** `nlm-sync.sh` — escrito. Uso: `bash nlm-sync.sh <company_id> <notebook_id>`
- [ ] **F5.5** Documentar cadencia

---

### Fase 6 — Automatizacion semanal + monitoreo
**Esfuerzo estimado:** 4-6 horas
**Prerequisito:** Fases 3 y 4 validadas

- [x] **F6.1** `weekly-ingest.sh` — escrito con lock, healthcheck, Telegram, Kuma push.
- [x] **F6.2** Cron — instalado: domingo 2am para la empresa primaria.
- [x] **F6.3** Logrotate — user-level.
- [x] **F6.4** Uptime Kuma — deployado en `http://<SERVER_IP>:3001`.
- [ ] **F6.5** Notificacion Telegram con resumen por empresa
- [ ] **F6.6** Primera ejecucion automatica supervisada

---

### Fase 7 — Outline como wiki publica (EN PARALELO desde el dia 1)
**Esfuerzo estimado:** 8-12 horas

- [x] **F7.1** Deploy — stack arriba, `tailscale serve` activo → `https://<TAILSCALE_DOMAIN>` (tailnet only). OAuth de Google configurado.
- [x] **F7.2** Colecciones — creadas via API.
- [x] **F7.3** Integracion con agentes — via API REST.
- [x] **F7.4** Flujo de aprobacion — documentado.
- [x] **F7.5** Migracion — 6 documentos publicados.

---

## Safeguards obligatorios (todo contenedor nuevo)

| Mecanismo | Implementacion |
|-----------|---------------|
| Memory limit | `--memory=MAX --memory-reservation=RESERVE` |
| OOM kill | habilitado (mata el contenedor, no congela el sistema) |
| Healthcheck | `--health-cmd`, `--health-interval`, `--health-retries` |
| Restart policy | `--restart=unless-stopped` |
| Log rotation | `--log-opt max-size=10m --log-opt max-file=3` |
| Cron locking | `/tmp/weekly-ingest-<company>.lock` con trap EXIT |
| Timeout por paso | cada paso del ingest con timeout individual |
| Error → continuar | log + Telegram + seguir con el paso siguiente |

> **Regla:** ningun contenedor se deploya sin los 5 primeros parametros.

> **Regla de red:** ningun contenedor publica puertos en `0.0.0.0`. Siempre `127.0.0.1:` (consumo local) o IP de Tailscale (acceso desde la red privada). Docker bypassea UFW — el bind es la proteccion real.

---

## Mapa de recursos proyectado

| Servicio | RAM | Estado |
|----------|:---:|--------|
| Paperclip server + DB | ~1.2 GB | Existente |
| SearXNG + Portainer | ~230 MB | Existente |
| Hermes (bare metal) | ~200 MB | Existente |
| **Mem0 API** | ~200 MB | Nuevo (F1) |
| **Ollama (nomic-embed-text)** | ~300 MB | Nuevo (F1) |
| **Outline + Postgres + Redis** | ~1.1 GB | Nuevo (F7) |
| **Uptime Kuma** | ~50 MB | Nuevo (F6) |
| **Total proyectado** | **~5.4 GB de 16 GB (~33%)** | ~10.6 GB libres |

---

## Restricciones y que NO hacer

- **No Hindsight** — solo funciona dentro de Paperclip; la memoria debe ser transversal. Mem0 lo reemplaza.
- **No Zep** — CE deprecado (legacy desde abril 2025), requiere Neo4j + OpenAI API key.
- **No Khoj** — no agregar 5GB de RAM para busqueda vectorial que Mem0/Qdrant ya cubren.
- **No API keys externas para embeddings** — todo local (Ollama + nomic-embed-text).
- **No NLM en pipeline automatizado** — cookies expiran ~14 dias. Solo sync mensual semi-manual.
- **No modelos pagos para ingest rutinario** — motor gratis. Modelo pago solo para destilacion pesada puntual y con supervision de costo.
- **No reprocesar todo en cada ingest** — el pipeline es incremental con `.processed.yaml`, siempre.
- **No publicar lab knowledge** — infraestructura, IPs y stack son administracion privada de Hermes. No van al knowledge compartido, ni al KB de empresas, ni a Outline.
- **No mezclar datos entre empresas** — aislamiento por namespace (Mem0), por directorio (knowledge), por coleccion (Outline), por configuracion (KB plugin).
- **No bloquear con aprobaciones manuales** — revision asincrona en batch semanal; el 80% se auto-aprueba.
- **No usar modelos remotos esporadicos como motor del pipeline** — el motor es un modelo local/gratuito estable.
- **No hardcodear UUIDs de cuadernos NLM en documentos** — viven en la memoria del orquestador.

---

## Anexo A — Inventario de fuentes de conocimiento

**Protocolo para nuevas fuentes:** descubrimiento → registro (template abajo) → extractor → ingest → revision trimestral.

| Fuente | Ubicacion | Formato | Extractor | Estado |
|--------|-----------|---------|-----------|--------|
| Paperclip deliverables | `~/ai-lab/ops/deliverables/example-deliverables/` | Markdown | rsync c/2h + wiki-ingest | Activa |
| Claude Code sessions | `~/.claude/projects/**/*.jsonl` | JSONL | `process_sessions.py` | Manual (F3) |
| OpenCode sessions | `~/.local/share/opencode/opencode.db` | SQLite | `opencode_extract.py` | Pendiente (F4) |
| Hermes sessions | `~/.hermes/sessions/` | SQLite | `hermes-history-ingest` | Skill pendiente (F0.3) |
| Antigravity CLI | a verificar | a verificar | — | Placeholder (F4.4) |

```yaml
fuente:
  nombre: string
  ubicacion: path
  formato_crudo: string        # JSONL | SQLite | Markdown
  extractor: path
  frecuencia_actualizacion: continua | diaria | semanal | bajo demanda
  company_id: string           # o "lab" si es administrativo
  activa: true/false
```

---

## Anexo B — Validacion automatica y flujo de revision (KB / Outline)

**Auto-aprobacion** si cumple TODO:

| Criterio | Verificacion |
|---|---|
| Contenido aditivo | No modifica articulos `[locked]` |
| Fuente trazable | Incluye `session_id`, `run_id` o timestamp |
| Sin credenciales | Regex: `sk-`, `ghp_`, `[A-Za-z0-9+/]{40,}=`, `password`, `token:` |
| Categoria existente | No propone categorias nuevas |
| Longitud | < 2000 palabras |
| Sin contradiccion | Similarity < 0.85 contra articulos `[critical]` |

**Cola de revision** (no bloquea, queda en borrador, NO se inyecta a agentes) si: modifica `[always inject]`, propone categoria nueva, el agente marco `[requires_review: true]`, posible contradiccion, o URLs fuera de lista blanca.

**Flujo humano:** digest semanal por Telegram (lunes 9am, por empresa) → revision en batch (<15 min) → escalacion inmediata solo si se toca un articulo `[critical]` o se detectan credenciales. Rollback: historial de versiones de Outline.

**Checklist de auto-validacion para agentes** (vive en el KB como `Conventions / Agent Write-back`):
- Agrega valor nuevo vs. lo existente?
- Fuente trazable (session_id, fecha, agente)?
- Libre de credenciales?
- Titulo con convencion `Categoria / Subcategoria / Titulo`?
- Si es decision: incluye el "por que"?
- Si contradice algo: marco `[requires_review]`?

---

## Impacto acumulado por fase

- Tras **F2**: todos los agentes arrancan con contexto institucional (la ganancia mas grande, mas temprano)
- Tras **F3**: el conocimiento de la empresa existe destilado y consultable
- Tras **F1**: memoria episodica compartida entre todos los agentes
- Tras **F5**: consulta en lenguaje natural para humanos
- Tras **F6**: el sistema se mantiene solo, con alertas si algo falla
- Tras **F7**: capa publica con revision no-bloqueante

---

*Documento unificado. Reemplaza documentos anteriores y consolida todas las decisiones.*
