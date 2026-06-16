# Knowledge Source & Integration Protocol

## What is a Knowledge Source

Any system or process that generates reusable information within the lab. Examples: Paperclip (deliverables), Claude Code (sessions), OpenCode (sessions), Hermes (memories, sessions).

## Lifecycle

1. **Discovery** — identify what the source produces and where it's stored
2. **Registration** — document: location, format, update frequency, estimated size
3. **Extractor** — script/pipe that transforms raw format to structured Markdown
4. **Ingest** — extractor feeds into `~/alma/knowledge/` via destilation
5. **Review** — evaluate whether the source is still valuable (suggested: quarterly)

## Source Registration Template

```yaml
fuente:
  nombre: string             # "Claude Code Sessions"
  ubicacion: path            # "~/.claude/projects/*/*.jsonl"
  formato_crudo: string      # "JSONL", "SQLite", "Deliverable markdown"
  extractor: path            # "~/shared/demos/process_sessions/process_sessions.py"
  frecuencia_actualizacion:  # continua | diaria | semanal | bajo demanda
  tamaño_estimado: string
  activa: true/false
  notas: string
```

## Current Sources Inventory

| Source | Location | Format | Extractor | Status |
|--------|----------|--------|-----------|--------|
| Paperclip deliverables | `~/alma/ops/deliverables/alma-deliverables/` | Markdown + metadata | Auto sync (rsync every 2h) | ✅ Active |
| Claude Code sessions | `~/.claude/projects/**/*.jsonl` | JSONL | `process_sessions.py` (at `~/shared/demos/process_sessions/`) | ⚠️ Manual |
| OpenCode sessions | `~/.local/share/opencode/opencode.db` | SQLite | `opencode_extract.py` (pending) | ❌ Pending |
| Hermes sessions | `~/.hermes/sessions/` | SQLite | `hermes-history-ingest` skill | ⚠️ Manual, mixed-content |
| Antigravity CLI sessions | `~/.antigravity/` (verify) | Unknown | Pending investigation | ❌ Unknown |

## Hermes Sessions Classification

Hermes sessions are **mixed-content**: they contain both lab administration conversations and company-specific work. They cannot be destilled to a single output path.

**Output split:**
- `~/alma/knowledge/lab/insights.md` — lab admin content (private to Hermes)
- `~/alma/knowledge/companies/<id>/sessions/hermes-insights.md` — per-company content (visible to that company's agents)

**Implementation:**
- Option A: classify during ingest (`hermes-history-ingest` skill separates content)
- Option B: tag in origin (Hermes marks `[company:X]` in session metadata)
- Recommended: B + A combined

## Tool Registration Protocol

### Step 1: Register the tool/source

Use the source template above. Document what it produces, where, and in what format.

### Step 2: Integration evaluation

- Does it need a new extractor?
- Is the format compatible with existing ones?
- Does it need a new provider/model in Hermes?
- Does it consume additional resources (RAM, disk, API)?

### Step 3: Documentation

- Add to source inventory
- Add to skills inventory if applicable
- Document config changes needed (`config.yaml`, `.env`)

### Step 4: Verification

- Basic connectivity test
- Sample extraction test
- Ingest test to the destilation pipeline

## Tool Registration Template

```yaml
herramienta:
  nombre: string
  tipo: agente | repositorio | api | servicio
  url_repo: string        # if applicable
  ubicacion_local: path   # if installed locally
  fuente_conocimiento:
    tipo: deliverables | sesiones | logs | datos
    formato: string
    ubicacion: path
    extractor: path
  requiere_config: true/false
  config_files:
    - path
  skills_asociadas:
    - nombre
  notas: string
```

## Skills Inventory

Skill registration template:

```yaml
skill:
  nombre: string
  ubicacion: path
  herramienta: string    # Hermes | Paperclip | OpenCode | etc
  version: string
  activa: true/false
  notas: string
```

Known skills:

| Skill | Location | Tool | Status |
|-------|----------|------|--------|
| hermes-history-ingest | `~/.hermes/skills/` | Hermes | ⚠️ Verify installed |
| wiki-ingest | `~/.hermes/skills/` | Hermes | ⚠️ Verify installed |
| opencode | `~/.hermes/skills/autonomous-ai-agents/opencode/` | Hermes | ✅ |
| plan / writing-plans | `~/.hermes/skills/software-development/` | Hermes | ✅ |
| native-mcp | `~/.hermes/skills/mcp/` | Hermes | ✅ |
| plan-review | `~/.hermes/skills/software-development/plan-review/` | Hermes | ✅ |
