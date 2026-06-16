# Multi-Company Decision Framework

Use this framework when reviewing plans that assume a single-tenant or single-company architecture, but the lab may need to serve multiple companies/clients in the future.

## The Two Dimensions

| Dimensión | Pregunta | Impacta |
|-----------|----------|---------|
| **Multi-company** | ¿El lab va a tener una sola empresa o varias (Paperclip)? | Aislamiento de datos, estructura de `~/alma/knowledge/`, config de memoria |
| **Knowledge scope** | ¿El conocimiento es del lab (infraestructura) o de una empresa específica (proyectos, clientes)? | Qué se comparte entre agentes vs qué se aísla |

## Three Possible Scenarios

### Escenario A: Single scope (one lab, no companies)
```
~/alma/knowledge/
├── AGENTS.md
├── architecture/
├── runbooks/
└── sessions/
```
- **When to use:** One team, one lab, no external clients
- **Pros:** Simplest, zero isolation overhead
- **Cons:** Cannot add second company without restructuring

### Escenario B: Hermes-admin + Companies (refined for labs with clients)
```
~/alma/knowledge/
├── shared/                       ← cross-company patterns, templates
│   ├── templates/
│   └── patterns.md
└── companies/                    ← ISOLATED PER COMPANY
    ├── <company-id>/
    │   ├── AGENTS.md
    │   ├── deliverables/
    │   ├── sessions/
    │   └── patterns.md
    └── (future companies here)
```

> **Key difference from classic B:** There is NO shared `lab/` directory. Lab infrastructure knowledge (IPs, stack, providers, runbooks) is **administration-level, kept in Hermes memory** (`~/.hermes/memories/`), not on the shared filesystem. Only Hermes has access by default. Other agents (Claude Code, OpenCode) can access on-demand when Hermes delegates a specific task.

- **When to use:** Lab serves multiple clients, Hermes is the administrator, company data must be isolated
- **Pros:** Lab knowledge stays admin-privileged, company knowledge is cleanly separated, no risk of infrastructure info leaking between companies
- **Cons:** Other agents can't self-serve lab knowledge (they must ask Hermes), requires Hermes to be running

### Escenario C: Full silos
```
~/alma/knowledge/
└── companies/
    ├── <company-id>/
    │   ├── AGENTS.md
    │   └── (everything scoped here)
    └── ...
```
- **When to use:** Complete isolation required, no shared lab context
- **Pros:** Maximum data separation
- **Cons:** No shared knowledge, duplicate infrastructure docs per company

## Decision Questions

Ask these when the user hasn't defined multi-company requirements:

1. **¿El lab va a operar proyectos de clientes externos?** If yes, data isolation is needed.
2. **¿Los agentes de Paperclip de una empresa deberían poder ver datos de otra?** If no, isolation is mandatory.
3. **¿Hermes es un agente del lab o puede trabajar para empresas específicas?** Defines whether Hermes needs per-company context switching.
4. **¿El conocimiento del lab (IPs, providers, stack) es compartible entre empresas?** Usually yes — infrastructure knowledge is not client-sensitive.
5. **¿Hay planes concretos de agregar una segunda empresa en Paperclip?** If "no in 6 months", start with A but structure for B.

## Recommendations by Priority

> **If priority is speed:** start with Escenario A, but structure directories so migration to B is straightforward.
> **If priority is future-proofing:** start with Escenario B (Hermes-admin + Companies) from day 1, even with one company.
> **If priority is maximum isolation:** start with Escenario C (full silos).

## Impact on Architecture

| Aspect | A (single) | B (Hermes-admin + Companies) | C (silos) |
|--------|-----------|------------------------------|-----------|
| `~/alma/knowledge/` structure | Flat | `shared/` + `companies/<id>/` only. Lab knowledge in Hermes memory, not filesystem. | `companies/<id>/` only |
| AGENTS.md | One for everything | One per company. No lab-level AGENTS.md (lab context is in Hermes memory). | One per company |
| Hermes memory | Lab context only | Lab context always + active company context on demand | Active company only |
| Paperclip KB plugin | One KB for all | Per-company KB (on-demand). No lab-level KB injected. | Per-company KB |
| Hindsight/Zep/etc | Single memory bank | Namespace per company | Namespace per company |
| Extractors (F3-4) | Single pipeline | Pipeline per company or tagged with company_id | Pipeline per company |
