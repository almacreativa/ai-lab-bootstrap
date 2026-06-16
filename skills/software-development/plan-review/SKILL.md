---
name: plan-review
description: "Review implementation plans section by section, write companion feedback docs, evaluate alternatives with matrices, and document architectural decisions."
version: 1.0.0
author: <YOUR_USER>
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [planning, review, architecture, decision-making, documentation, knowledge-management]
    related_skills: [writing-plans, plan, subagent-driven-development]
---

# Plan Review & Architectural Decision-Making

## Overview

Review an existing implementation plan (or proposal) section by section, producing a companion feedback document with structured analysis, alternative evaluation, and architectural decisions.

**Core principle:** Decisions are documented progressively as they're made, not just at the end. Each section of the feedback corresponds to one section of the original plan.

## When to Use

- User has an existing plan and wants it reviewed before implementation
- Need to evaluate competing approaches or tools (alternatives matrix)
- Architecture decisions need validation (Docker vs bare metal, DB shared vs separate, etc.)
- The plan makes assumptions about the environment that may be stale
- User wants to discuss tradeoffs before committing to an approach

**Don't skip when:**
- The plan was written by another agent or in a different session
- The plan hasn't been validated against the actual environment
- There are multiple viable approaches with different tradeoffs

## Review Document Structure

### Companion File Convention

Create a companion file alongside the original plan, named `<original-name>-feedback.md` in the same directory. This keeps the review tied to the plan without modifying it.

```markdown
# [Plan Name] — Analysis & Refinements

**Archivo compañero de:** `original-plan.md`
**Propósito:** Revisión sección por sección, observaciones, decisiones, y refinamientos.
```

### Section Template

Each section of the review follows this structure:

```markdown
## N. [Section Name] (vs. plan original líneas X-Y)

### Lo que está bien

- What the plan gets right
- Strengths of the approach

### Observaciones

- **Gaps:** what's missing or underspecified
- **Assumptions:** what the plan assumes that needs verification
- **Risks:** what could go wrong or block implementation
- **Environment mismatches:** commands/paths that don't match reality

### Decisiones tomadas

- What was decided and why
- What was descarted and why
```

### Alternatives Matrix

When evaluating competing tools or approaches, use a weighted comparison:

| Criterio | Peso | Option A | Option B | Option C |
|----------|:----:|:--------:|:--------:|:--------:|
| Criterion 1 with weight N% | N% | score 0-10 | score 0-10 | score 0-10 |
| Criterion 2 | N% | score 0-10 | score 0-10 | score 0-10 |
| **Puntaje ponderado** | **100%** | **result** | **result** | **result** |

Weight criteria by importance to the user's context (e.g., transversal support 25%, resource consumption 10%).

### Recommendations Section

End each decision point with a clear recommendation based on different priorities:

> **Si la prioridad es [X]:** [option A] (rationale).
> **Si la prioridad es [Y]:** [option B] (rationale).

## Review Process

### Step 1: Understand the Environment

Before reviewing the plan, verify key environment facts that the plan may assume incorrectly:

```bash
# Check actual deployment mode
docker ps  # vs bare metal processes
which hermes  # binary location
hermes --version  # actual version

# Check resource availability
free -h
df -h

# Check existing infrastructure
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

### Step 2: Read the Plan Section by Section

Process each section independently. For each:

1. **Identify assumptions** — what does this section assume about the environment, tools, or infrastructure?
2. **Validate against reality** — do the commands/paths/configs match what's actually deployed?
3. **Flag gaps** — what's missing or underspecified?
4. **Consider alternatives** — is the proposed approach the best option, or are there viable alternatives?

### Step 3: Write Each Section to the Feedback File

Write progressively as each section is reviewed. Don't wait until the end.

### Step 4: Add Architectural Decisions

When decisions are made during review, document:

| Decisión | Opción elegida | Alternativas consideradas | Razón |
|----------|---------------|--------------------------|-------|
| Hermes deployment | Bare metal | Docker (original) | Migrated post-deploy |
| Memory layer DB | Separate Postgres | Shared Paperclip DB | Isolation, independent deploys |
| Fase 7 (Outline) | Include from start | Postpone (original) | Full boilerplate from day 1, resources available |

**Include a resource map** when the decision adds new services to the infrastructure:

```markdown
### Servicios nuevos
| Servicio | RAM estimada | Safeguards |
|----------|:-----------:|:----------:|
| Service A | ~200 MB | `--memory=384m`, healthcheck |
| Service B | ~800 MB | `--memory=1g --memory-reservation=768m` |

### Total proyectado
| Concepto | Valor |
|----------|:-----:|
| RAM usada hoy | ~N GB |
| RAM nueva | ~N GB |
| **Total** | **~N GB** |
| **Disponible restante** | **~N GB** |
+ SAFEGUARDS: memory limits, OOM kill, healthchecks, restart policy, log rotation
```

**Include safeguards** for every new container or service:
- Memory limit (`--memory=MAX`) and reservation (`--memory-reservation=RESERVE`)
- Healthcheck with retries
- Restart policy (`unless-stopped`)
- Log rotation (`max-size=10m max-file=3`)
- OOM kill enabled (`--oom-kill-disable=false`)
- Cron lock files (for scheduled jobs)

### Step 5: Identify Scope Limitations

A common pitfall: plans propose solutions that work for ONE tool/agent but the need is TRANSVERSAL.

**Detection pattern:**
- Does the plan say "this is for Paperclip" (or Hermes, or X tool) without considering others?
- Are there other agents/tools in the lab that need the same capability?
- If the proposed tool goes down, do all agents lose access?

**Response:**
- Flag the scope limitation explicitly in the feedback
- Propose a layered approach: tool-specific solution + transversal fallback
- Example: KB plugin for Paperclip + AGENTS.md for everyone else + MCP knowledge server for MCP-capable agents

### Step 6: Identify Architecture Decision Prerequisites

Some decisions MUST be made before implementation can proceed. They block architecture.

**Detection pattern:**
- The plan assumes a topology (single-tenant, single-company) that may not hold
- Environmental assertions that need validation (Docker vs bare metal, service names)
- Multi-company, multi-tenant, or multi-environment considerations

**Response:**
- Create a dedicated "Instancia de análisis y decisión" section in the feedback
- Define the scenarios with a clear comparison table
- Ask specific questions that resolve the ambiguity (see references/multi-company-decision.md)

### Step 7: Identify Mixed-Content Sources

Some agents (especially Hermes, the lab administrator) produce sessions that mix multiple contexts — lab administration AND company-specific work. These can't be destilled to a single location.

**Detection pattern:**
- An agent is described as "admin" or "orchestrator" — its sessions likely contain both infrastructure work and client work
- The plan proposes a single destillation output path for an agent that works across contexts

**Response:**
- Document the classification challenge explicitly
- Propose a three-way output split: `lab/insights.md` (admin private), `companies/<id>/sessions/hermes-insights.md` (per company), or `unclassified/` (manual review)
- Recommended approach: tag in origin (agent marks `[company:X]` in session metadata) + classify during ingest for unmarked content

```
Hermes sessions (mixed)
        ↓
  Classifier → Lab admin or company work?
        ↓                ↓
lab/insights.md    companies/X/sessions/
(Hermes private)   (visible to company X agents)
```

### Step 8: Verify Tool Viability Beyond Comparison Tables

When the review uses a comparison table (weighted matrix) to evaluate competing tools, the table itself can be stale — reflecting data that was accurate when the plan was written but may no longer hold.

**Detection pattern:**
- The comparison table has a "Self-hosted" / "RAM estimada" / "Licencia" column but the values come from marketing pages or earlier research
- The plan recommends a tool based on community perception that may have changed
- Open-source tools may have changed direction, been acquired, or pivoted to closed-source

**Verification steps for each candidate tool:**

```markdown
1. Check the GitHub repo:
   - `curl -s "https://api.github.com/repos/org/repo" | python3 -c "import sys,json; d=json.load(sys.stdin); print('Last push:', d.get('pushed_at')); print('Archived:', d.get('archived')); print('Stars:', d.get('stargazers_count')); print('Description:', d.get('description'))"`
   
2. Check the docker-compose.yml:
   - `curl -sL "https://raw.githubusercontent.com/org/repo/main/docker-compose.yml"` — look for actual services, not just what the README says
   - Count services, check dependencies (Neo4j? Redis? Separate DB?)

3. Check the latest release:
   - `curl -s "https://api.github.com/repos/org/repo/releases/latest"` — confirm recent activity

4. Check environment requirements:
   - Look for `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or other external API keys in the compose or env example. If the tool requires paid external APIs to function, flag this.

5. Check if the repo structure confirms active development:
   - Is the community edition in a `legacy/` directory?
   - Is the main README pointing to a cloud/SaaS version instead of self-hosted?
```

**Common patterns of tool deprecation:**
| Pattern | What it means |
|---------|---------------|
| CE/community edition moved to `legacy/` | Open-source version no longer maintained |
| docker-compose.yml requires N services with external API keys | The "lightweight" estimate was wrong |
| README redirects to cloud signup | Self-hosted is second-class or dead |
| No releases in 6+ months | Project may be abandoned |
| Fork exists (N1nEmAn/openzep etc.) | Community is keeping the open version alive |

**Response in the feedback document:**
- Update the comparison table with verified data
- Add a deprecation/maturity note to any tool whose status changed
- Recalculate weighted scores if the new data changes the ranking

### Critical checks before trusting a plan

| Check | Why it matters |
|-------|---------------|
| Hermes in Docker or bare metal? | Changes every command path |
| Services currently running? | Confirms what's actually deployed |
| RAM/disk available? | Validates resource estimates |
| pgvector extension active? | Required for semantic search |
| NLM MCP configured? | Required for NotebookLM access. Verify: `grep -A5 "notebooklm" ~/.hermes/config.yaml`, then `ps aux \| grep notebooklm-mcp`, then `hermes chat -q "listá los notebooks" --max-turns 2` |
| Actual container names? | May differ from plan assumptions. Always run `docker ps` to verify. |
| Hermes sessions mixed? | Check if Hermes works across lab admin + company tasks — if so, sessions need classification, not single-path destillation |
| Actual DB credentials? | `POSTGRES_USER` may not be `postgres` — check `docker inspect <container> \| grep POSTGRES_USER` |

### Common environment mismatches

- **Commands that assume Docker:** `docker exec hermes /opt/hermes/.venv/bin/hermes` → `hermes` when bare metal
- **Paths that assume volumes:** `/opt/data/` → `~/.hermes/` when bare metal
- **Container names:** `paperclip-postgres` may differ from actual `paperclip-db-1`
- **DB users:** `postgres` user may not exist (actual: `paperclip`, `paperclip`)

## Reference Files

This skill includes reference files for common review scenarios:

- `references/multi-company-decision.md` — decision framework for single vs multi-tenant architecture
- `references/knowledge-source-protocol.md` — templates for registering knowledge sources, tools, and skills
- `references/tool-verification.md` — workflow for verifying open-source tool current state (GitHub, docker-compose, releases, API key requirements) before relying on comparison tables

Check these when a review involves multi-company, multi-agent, knowledge management, or tool-selection concerns.

## User Preferences for This Lab

- **Format:** present each section clearly for review ("preséntamela claro para que la pueda revisar y analizar con calma"). Tables, bullet lists, labeled info.
- **Pace:** review section by section, don't dump everything at once. Let the user process each part before moving on.
- **Decisions:** validate architecture decisions before implementing. Don't assume the plan is correct.
- **Alternatives:** always offer 2-3 options with a comparison matrix before choosing.
- **Documentation:** write findings to a companion file, not just in the chat. This creates a durable record.
- **Lab context:** Hermes runs bare metal (not Docker). Paperclip uses `paperclip-db-1` (Postgres 17). Always verify container/service names against `docker ps` before using them.
- **Postponement policy:** Don't suggest postponing infrastructure when resources are available. The user prefers full setup from the start ("dejar todo establecido, el boilerplate completo funcionando con la infraestructura que voy a escalar luego"). If RAM and storage are sufficient (check with `free -h`), propose including the service now with safeguards, not deferring it.
- **Resource-awareness:** Always include a projected resource map when adding new services. The user wants explicit numbers for RAM usage, available headroom, and safeguard mechanisms (memory limits, healthchecks, OOM protection, log rotation).

## Pitfalls

### Assuming the plan is accurate

Plans written by other agents or in earlier sessions may reference infrastructure that has changed. Always validate: Docker vs bare metal, container names, paths, available tools.

### Stale comparison data

Comparison matrices (weighted tables) are time-sensitive. A tool that scored 8/10 six months ago may have been deprecated, pivoted to cloud-only, or acquired. Before recommending based on a comparison table, verify each candidate's actual current state:
- Check GitHub: latest release date, repo structure (is CE in `legacy/`?), docker-compose dependencies
- Check API key requirements: does the tool require OpenAI/Anthropic keys to function?
- Check actual RAM: the docker-compose.yml reveals real service count, not marketing estimates
- Update the matrix scores if the data changed — stale matrices produce wrong recommendations

### Reviewing everything verbally

The companion document is the durable record. Write to it progressively — don't keep all analysis only in chat. The user will read the file later on their Mac via Syncthing.

### Skipping the alternatives step

When the user asks "what are the options?" — build a comparison matrix with weighted criteria. Don't just list pros and cons. Weighting clarifies tradeoffs and makes the recommendation transparent.

### Not flagging environment-dependent assumptions

Commands like `docker exec paperclip-postgres psql -U postgres` assume specific container names and users that may not match reality. Always verify.

## Verification

After each review section, the companion file should be:
- Coherent (each section is self-contained)
- Actionable (every observation suggests a fix or decision)
- Progressive (written as you go, not batched at the end)
- Synced (saved to a directory visible to Syncthing, typically `~/shared/demos/`)

## Related Skills

- `writing-plans` — use this to write the implementation plan itself (the forward-looking document)
- `plan` — plan mode (no execution, save to `.hermes/plans/`)
- `subagent-driven-development` — execute approved plans via delegate_task
