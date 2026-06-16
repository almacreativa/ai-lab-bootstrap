---
name: session-continuity
category: software-development
description: "Recover session context after a daily-schedule reset, DB wipe, or when the user asks 'where were we'. Sequence: memory-first, multi-strategy session search, filesystem artifact recovery, synthesis. Also covers storing reconstructable summaries so the next reset finds something useful."
---

# Session Continuity — Context Reconstruction After Reset

## When to use

- The user asks "que tenemos claro de la situacion" / "where were we" / "que estamos haciendo"
- The session DB appears empty or has only cron/CLI entries from today
- You have persistent memory but no ongoing-session context
- A daily schedule or cron job just reset your context

## Sequence

### 1. Read persistent memory first
Call `memory()` to read both `target='memory'` (environment facts) and `target='user'` (user profile). Memory is durability-guaranteed and survives all resets. It's the fastest source of truth.

### 2. Browse recent sessions
```python
session_search()  # no args = browse mode
```
This returns recent sessions with previews even when FTS5 querying returns nothing. Always try browse before query.

### 3. Multi-strategy FTS5 queries
If browse doesn't give enough context, search with several query strategies:
- **English project/tool names:** `"Paperclip pipeline"`, `"Hermes agent"`, `"kanban worker"`
- **Spanish domain terms:** `"agente"`, `"memoria"`, `"organizacion"`
- **Specific identifiers:** `"<company-id>"`, `"<hostname>"`, `"<provider>"`
- **Sort modes:** `sort='newest'` for recency, `sort='oldest'` for origin
- **Role filter:** `role_filter='user,assistant,tool'` when debugging tool behavior

**Pitfall:** FTS5 may not handle Spanish multi-word queries well -- retry with English terms or single Spanish keywords if a complex Spanish query returns nothing.

### 4. Filesystem artifact search
Session artifacts often live outside the DB:
```python
# Find recent workspace directories
search_files(pattern='noche-*', target='files', path='/home/user/ai-lab/workspace/')
# Find key planning/strategy documents
search_files(pattern='*plan*', target='files', path=project)
search_files(pattern='*knowledge*', target='files', path=project)
# Find infrastructure docs
search_files(pattern='*SERVIDOR*', target='files', path=project)
search_files(pattern='*PAPERCLIP_INFRA*', target='files', path=project)
```

### 5. Read high-value documents
Prioritize reading these first (they give the most context per line):
- **PLAN.md** or session plans in workspace directories
- **Roadmaps** and strategy docs (roadmap.md, evolution plans)
- **Infrastructure docs** (SERVIDOR.md, PAPERCLIP_INFRASTRUCTURE.md)
- **Knowledge management plans** (conocimiento/agent-memory docs)
- **Session logs** (session.log files in dated workspace dirs)

### 6. Rebuild current-state picture
Synthesize these layers when presenting to the user:

| Layer | Source | Example |
|---|---|---|
| Environment reality | Memory | your server bare metal, no GPU, Docker accessible |
| Key docs produced | Filesystem search | auditoria-seguridad, knowledge-management-plan, roadmap |
| Project status | Docs + memory | Que se planifico vs que se ejecuto |
| Decisions made | Docs + memory | NO GPU, opencode-zen for destilacion, Hindsight self-hosted |
| Next steps | Docs | Fase 0 del KM plan, hardening scripts sin ejecutar |
| Open questions | Memory + inference | Issues conocidos sin resolver (Paperclip mounts, ENOSPC) |

### 7. Store a durable footnote
After reconstruction, save a compact note to memory so the *next* reset finds an even faster path:
```python
memory(action='add', target='memory',
  content='STATUS 12-jun-2026: ...')
```
Keep it under 300 chars -- just enough to orient the next instance.

## Pitfalls

- **Session DB can reset silently** -- daily schedule and cron jobs wipe the context. Never assume past sessions are in the DB. Always start from memory + filesystem.
- **FTS5 language gap** -- FTS5 doesn't handle Spanish well. Try English terms (`"Paperclip agent"`, `"Hermes cron"`) as fallback when Spanish queries return nothing.
- **Memory is capped at 2,200 chars** -- compact, remove stale entries to stay under the limit. Don't save session-level detail to memory; save it as a session artifact on disk.
- **Cron sessions look like CLI sessions** -- `source: "cron"` sessions in browse results are autonomous runs, not user sessions. Filter mentally: user interactions are `source: "cli"` or `source: "telegram"`.
- **Browser sessions may not appear** -- if session_search returns nothing even in browse mode, a recent daily schedule may have truncated the DB entirely. Go straight to filesystem.

## Storing reconstructable summaries

To make future resets easier, after any substantial session (5+ tool calls, or a decision was made), save a **compact status line** to memory:

```
STATUS <date>: <2-3 sentence summary of current state, key open items, files produced>
```

Example:
```
STATUS 12-jun-2026: After June 7 session produced audit/hardening/roadmap. KM plan v2.0 (alma/strategy/) outlines 7-phase agent-memory system. Zero execution done. Paperclip mounts broken on rebuild (known). NO GPU decision stands.
```

This gives the next reset-instance an instant orientation without needing to re-do the full reconstruction dance.

## Relation to other skills

- **systematic-debugging** -- use when the *reason* for context loss needs diagnosis (e.g., session DB corruption, schedule misconfiguration). This skill assumes context is simply gone and helps you rebuild.
- **plan / writing-plans** -- use after reconstruction to formalize next steps into a plan document.
