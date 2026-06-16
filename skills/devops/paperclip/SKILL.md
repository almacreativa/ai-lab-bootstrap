---
name: paperclip
description: Work with Paperclip — architecture, adapters, deployment, and debugging on an AI lab server.
tags: [paperclip, acp, adapters, docker, agent-protocol]
---

# Paperclip

Paperclip is a control plane for AI-agent companies. This skill covers a typical deployment,
adapter architecture, and integration patterns.

## Triggers

- User asks about Paperclip configuration, adapters, agents, or deployment
- User wants to add a new agent adapter to Paperclip
- User wants to create a new company or onboard a project into Paperclip → see `references/company-onboarding.md`
- Debugging Paperclip agent execution failures
- Understanding the ACP (Agent Client Protocol) integration layer

## MCP Integration (PREFERRED — use this instead of DB direct)

Hermes can have MCP servers configured for Paperclip — one per company:

| MCP Server | Company | Tools prefix |
|---|---|---|
| `paperclip_<company_a>` | <COMPANY_A> (`<UUID_A_SHORT>`) | `mcp_paperclip_<company_a>_*` |
| `paperclip_<company_b>` | <COMPANY_B> (`<UUID_B_SHORT>`) | `mcp_paperclip_<company_b>_*` |

**Available tools (21 per company):**

Issues: `list_issues`, `get_issue`, `create_issue`, `update_issue`, `checkout_issue`, `release_issue`, `comment_on_issue`, `delete_issue`
Agents: `list_agents`, `get_agent`, `invoke_agent_heartbeat`
Goals: `list_goals`, `create_goal`, `update_goal`
Approvals: `list_approvals`, `approve`, `reject`, `request_approval_revision`
Monitoring: `get_cost_summary`, `get_dashboard`, `list_activity`

**When to use MCP vs DB direct:**

| Use MCP for | Use DB direct for |
|---|---|
| Creating/updating issues | Onboarding new company (multi-table) |
| Listing agents and issues | Changing `adapter_config` (model, promptTemplate) |
| Triggering heartbeats (`invoke_agent_heartbeat`) | Fixing corrupted state |
| Adding comments | Deleting agents with FK constraints |
| Managing goals and approvals | Ad-hoc diagnostic queries |
| Monitoring costs and activity | |

**Key advantage:** MCP operations leave audit trail in Paperclip's activity log. DB direct operations do not.

**Heartbeat on-demand:** `invoke_agent_heartbeat` wakes an idle agent immediately — no need to wait for the timer. Endpoint: `POST /api/agents/{id}/heartbeat/invoke`. Returns a heartbeat_run with status `queued`.

## Routines (Scheduled Work)

Paperclip has a native routines system for recurring work. Each routine creates issues on a cron schedule.

**Current routines (examples):**

| Company | Routine | Agent | Cron | Timezone |
|---|---|---|---|---|
| <COMPANY> | Weekly activity report | CEO | `0 9 * * 1` (Mon 09:00) | America/Costa_Rica |
| <COMPANY> | Weekly metrics review | Analyst | `0 14 * * 5` (Fri 14:00) | America/Costa_Rica |

**DB tables:** `routines` → `routine_triggers` (cron schedule) → `routine_revisions` (versioned config) → `routine_runs` (execution log).

**Creating routines:** No API or MCP tool exists. Use DB INSERT.

**Routines vs host crons:** Routines create Paperclip issues (agent-level work). Host crons (`backup-deliverables.sh`, `sync-knowledge.sh`) operate at filesystem level. They are complementary.

## Deployment

Paperclip runs in Docker on the lab server:

```bash
# Check status
docker ps --filter name=paperclip

# Logs
docker logs paperclip-server-1 --tail 200

# DB access
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "SELECT id, name, adapter_type, adapter_config FROM agents;"

# Health
curl http://localhost:3100/api/health
```

**Compose file:** `~/ai-lab/repos/paperclip/docker/docker-compose.yml`
**Network:** `ai-lab` (172.30.0.0/24), container at 172.30.0.3
**Port:** 3100
**DB:** postgres:17-alpine, credentials paperclip/paperclip
**Workspace mount:** `$HOME/ai-lab/workspace:/paperclip/workspace`
**OpenCode config mounts (ro) — MUST be in docker-compose.yml under `server.volumes`:**
- `~/.opencode:/paperclip/.opencode:ro` — OpenCode binary + node_modules
- `~/.config/opencode:/paperclip/.config/opencode:ro` — opencode.jsonc model config
- `~/.local/share/opencode/auth.json:/paperclip/.local/share/opencode/auth.json:ro` — Copilot/GitHub OAuth credentials

⚠️ **CRITICAL: HOME=/paperclip, not /root.** The container's HOME is `/paperclip` (set by Paperclip's Dockerfile).
All host→container mounts for user-level config/auth MUST target `/paperclip/` paths, not `/root/`.
Mounting to `/root/` silently fails because OpenCode reads from `$HOME/.config/opencode/` and
`$HOME/.local/share/opencode/auth.json`. This is the #1 cause of "OpenCode works but can't see my providers/models."

Key directories inside container:
- `/paperclip/instances/default/` — instance root (config.json, .env, companies/, workspaces/)
- `/paperclip/instances/default/workspaces/<agent-uuid>/` — agent workspace (deliverables go here)
- `/paperclip/instances/default/data/backups/` — hourly DB backups

**Agent instructions:** Delivered via `promptTemplate` in `adapter_config` (DB), NOT filesystem AGENTS.md (bug #1495). To modify: edit templates in `~/ai-lab/knowledge/shared/templates/` and run `deploy-agent-prompts.sh`.

## Adapter Architecture

Paperclip agents use **adapters** to execute AI coding tools. Each adapter type spawns a CLI
subprocess and parses its output.

### Built-in Adapter Packages

Located at `packages/adapters/` in the repo:

| Package | Adapter Type | Command Spawned |
|---|---|---|
| `claude-local` | `claude_local` | `claude` CLI |
| `codex-local` | `codex_local` | `codex` CLI |
| `opencode-local` | `opencode_local` | `opencode run --format json` |
| `acpx-local` | `acpx_local` | Claude/Codex via ACP (uses `acpx` library) |
| `cursor-local` | `cursor_local` | Cursor CLI |
| `cursor-cloud` | `cursor_cloud` | Cursor Cloud API |
| `gemini-local` | `gemini_local` | Gemini CLI |
| `grok-local` | `grok_local` | Grok CLI |
| `pi-local` | `pi_local` | Pi CLI |
| `openclaw-gateway` | `openclaw_gateway` | HTTP gateway |

### opencode_local Adapter Detail

Key file: `packages/adapters/opencode-local/src/index.ts`

- Executes `opencode run --format json` with model in `provider/model` format
- Models: `openai/gpt-5.2-codex`, `openai/gpt-5.4`, `openai/gpt-5.1-codex-max`, etc.
- Session resume via `--session` flag
- Sets `OPENCODE_DISABLE_PROJECT_CONFIG=true` to prevent config file writes
- Permission bypass: injects runtime config with `permission.external_directory=allow`

### acpx_local Adapter Detail

Key files: `packages/adapters/acpx-local/src/index.ts`, `.../server/execute.ts`

- Uses `acpx` library (`createAgentRegistry`, `createAcpRuntime`) to manage ACP sessions
- Built-in agents: `claude` (→ `claude-agent-acp` binary), `codex` (→ `codex-acp` binary)
- Custom agent: set `agent=custom` + `agentCommand=<path>` for arbitrary ACP servers
- Dependencies: `@agentclientprotocol/claude-agent-acp`, `@zed-industries/codex-acp`, `acpx`
- Agent command resolution in `resolveBuiltInAgentCommand()` — maps agent name to binary in `node_modules/.bin/`
- Creates wrapper shell scripts in `stateDir/wrappers/` that source env and exec the agent binary
- Skill materialization: for Claude, copies skills to `.claude/skills/`; for Codex, manages `CODEX_HOME/skills/`

### Agent Configuration (DB)

Agent records in the `agents` table:
- `adapter_type` — one of the type strings above
- `adapter_config` — JSONB with model, cwd, instructionsFilePath, etc.
- `runtime_config` — heartbeat settings, concurrency
- `permissions` — canCreateAgents, etc.

Example agents (company `<UUID>`, <COMPANY>): CEO, CTO, Coder — all using `opencode_local`.

| Agent | Role | Model | Strategy |
|---|---|---|---|
| CEO | ceo | `github-copilot/claude-sonnet-4.6` | Strategic direction, delegation |
| CTO | cto | `github-copilot/claude-sonnet-4.6` | Technical architecture, code review |
| Coder | engineer | `github-copilot/gpt-5.4` | Code implementation, fast iterations |

**Updating agent models via DB:** Use `jsonb_set` to change only the model field without touching other config:

```sql
UPDATE agents
SET adapter_config = jsonb_set(adapter_config, '{model}', '"github-copilot/gpt-5.4"')
WHERE id = '<agent-uuid>';
```

**Creating board API keys (no UI available):** Paperclip doesn't expose a UI for board API keys. Generate directly in DB:

```bash
# 1. Generate token and hash
docker exec paperclip-server node -e "
const crypto = require('crypto');
const token = 'pcp_board_' + crypto.randomBytes(24).toString('hex');
const hash = crypto.createHash('sha256').update(token).digest('hex');
console.log(JSON.stringify({ token, hash }));
"

# 2. Insert into DB (token expires in 30 days by convention)
docker exec paperclip-db psql -U paperclip -d paperclip -c "
INSERT INTO board_api_keys (user_id, name, key_hash, expires_at)
VALUES ('<user-id>', 'My Key', '<hash>', NOW() + INTERVAL '30 days');
"

# 3. Use: Authorization: Bearer <token>
```

Key format: `pcp_board_<48 hex chars>`. Hashing: SHA256. No salt.

## Monitoring (via Board API Key)

With a board API key, Paperclip can be queried programmatically:

```bash
TOKEN="pcp_board_..."
COMPANY="<COMPANY_UUID>"
BASE="http://localhost:3100/api"

# List agents and their models
curl -sH "Authorization: Bearer $TOKEN" "$BASE/companies/$COMPANY/agents" | jq '.[] | {name, adapterConfig: .adapterConfig.model, status}'

# Recent heartbeat runs
curl -sH "Authorization: Bearer $TOKEN" "$BASE/companies/$COMPANY/heartbeat-runs?limit=5" | jq '.[] | {id, agentId, status}'

# Issues
curl -sH "Authorization: Bearer $TOKEN" "$BASE/companies/$COMPANY/issues?limit=5" | jq '.[] | {key: .displayId, title, status}'

# Activity feed
curl -sH "Authorization: Bearer $TOKEN" "$BASE/companies/$COMPANY/activity?limit=10"
```

From Hermes, set up a cron job to poll and report:
```
cronjob create --schedule "0 * * * *" --prompt "Check Paperclip agents status and report any issues or recent activity."
```

## ACP (Agent Client Protocol)

ACP is a JSON-RPC 2.0 protocol over stdio that standardizes communication between code
editors and coding agents (ref: `@agentclientprotocol/sdk` npm package).

Tools that support ACP:
- **Claude Code:** `claude --acp --stdio` (via `@agentclientprotocol/claude-agent-acp`)
- **Codex CLI:** `codex --acp --stdio` (via `@zed-industries/codex-acp`)
- **GitHub Copilot CLI:** `copilot --acp --stdio` (v1.0.52+, `@github/copilot`)
- **OpenCode CLI:** `opencode acp` subcommand

### ACP Flow (from Hermes reference implementation)

```
initialize (protocolVersion, clientCapabilities)
  → session/new (cwd, mcpServers)
    → session/prompt (sessionId, prompt)
      → session/update events (agent_message_chunk, agent_thought_chunk)
```

Server-initiated requests during a session:
- `session/request_permission` — respond with outcome (cancelled or approved)
- `fs/read_text_file` — respond with file content
- `fs/write_text_file` — write and respond

## Adding a Copilot Adapter

See `references/copilot-adapter-gap.md` for the full diagnostic on the mount-path issue
(the real fix) and the native ACP adapter architecture (alternative approach).

## Board API Keys

See `references/board-api-key.md` for the recipe to create board API keys directly in the
database (no UI available).

## Infrastructure Documentation

The canonical infrastructure reference for your lab should be at `~/ai-lab/PAPERCLIP_INFRASTRUCTURE.md`. It should cover:
- Volume mount configuration (with the /paperclip/ HOME correction)
- Board API key generation recipe
- Agent model configuration commands
- Container recreation procedure
- Troubleshooting checklist

When maintaining or replicating the Paperclip deployment, consult this doc first.

## Model Profiles (Budget Lanes)

The `opencode_local` adapter defines `modelProfiles` in `packages/adapters/opencode-local/src/index.ts`.
These are budget-lane models used for auxiliary tasks (summaries, context compression, etc.).

The adapter also has a static `models` array for the UI model picker. Both must be updated together
when switching providers.

⚠️ See `references/opencode-providers-models.md` for the provider and model inventory.

### Example model profile configuration

```typescript
export const models: Array<{ id: string; label: string }> = [
  { id: DEFAULT_OPENCODE_LOCAL_MODEL, label: DEFAULT_OPENCODE_LOCAL_MODEL },
  // OpenCode GO (free)
  { id: "opencode/big-pickle", label: "opencode/big-pickle (free)" },
  { id: "opencode/deepseek-v4-flash-free", label: "opencode/deepseek-v4-flash-free (free)" },
  // Copilot via OpenCode
  { id: "github-copilot/claude-sonnet-4.6", label: "github-copilot/claude-sonnet-4.6" },
  { id: "github-copilot/gpt-5.4", label: "github-copilot/gpt-5.4" },
];

export const modelProfiles: AdapterModelProfileDefinition[] = [
  {
    key: "cheap",  // ← the ONLY allowed key (TypeScript union type constraint)
    label: "Cheap",
    description: "Budget model for auxiliary tasks",
    adapterConfig: {
      model: "github-copilot/gpt-5-mini",
      variant: "low",
    },
    source: "adapter_default",
  },
];
```

⚠️ **PITFALL — model profile key is type-constrained:** `AdapterModelProfileDefinition.key` is a
TypeScript union type that ONLY allows `"cheap"`. You can't add a `"free"` key — the build will fail
with `Type '"free"' is not assignable to type '"cheap"'`. To add a budget lane, change the existing
`cheap` profile's model or leave it alone.

⚠️ **PITFALL — unavailable profile model causes silent failures:** When the profile model doesn't
exist through the configured provider (Copilot has no `openai/*` models), auxiliary/budget-lane runs
fail with `"Configured OpenCode model is unavailable: openai/gpt-5.1-codex-mini"`. Primary runs
succeed, so the error is easy to miss. Check `heartbeat_runs.error` for the telltale message.

### Rebuilding After Adapter Source Changes

Changing `packages/adapters/opencode-local/src/index.ts` requires rebuilding the Docker image:

```bash
cd ~/ai-lab/repos/paperclip/docker       # ← compose file lives in docker/ subdirectory
docker compose build paperclip-server     # ≈5 min
docker compose down paperclip-server      # only server, DB stays up
docker compose up -d paperclip-server
```

The DB and named volumes survive — only the server image is rebuilt. After deploy, verify:
```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
SELECT name, adapter_config->>'model' FROM agents;
"
# Models should be intact. Re-set Coder model if CEO reverted it during the broken period.
```

## Triggering Agent Work

Agents with `runtime_config.heartbeat.wakeOnDemand: true` wake up when an issue is
assigned to them — the `invocation_source` shows `"assignment"` in `heartbeat_runs`.
Agents with heartbeat disabled but `wakeOnDemand: true` will NOT auto-wake; enable
heartbeat via DB (see `references/agent-wakeup-heartbeat.md`).

⚠️ **PITFALL — `heartbeat.enabled` is the master switch.** An agent may have
`wakeOnDemand: true` in its `runtime_config` but if `heartbeat.enabled: false`,
it will NOT wake on assignment. Always check both fields:
```sql
SELECT name, runtime_config->'heartbeat' FROM agents WHERE company_id = '<uuid>';
```

For multi-agent cascade workflows (e.g. CSO → Analyst → CEO), see
`references/agent-wakeup-heartbeat.md#multi-agent-cascade-workflow`.

**To trigger the pipeline:**

Write the JSON body to a temp file first to avoid shell quoting issues with the
board API key token (the `pcp_board_...` token can cause `unexpected EOF` errors
when mixed with inline JSON in curl):

```bash
# 1. Create an issue (file-based body — most reliable pattern)
cat > /tmp/create_issue.json <<'EOF'
{
  "title": "Task title",
  "description": "Task description...",
  "status": "todo",
  "priority": "high"
}
EOF

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/create_issue.json \
  "$BASE/companies/$COMPANY/issues"

# 2. Assign to agent + move to in_progress (use UUID, not short ID like PREFIX-4)
cat > /tmp/assign_issue.json <<'EOF'
{"status":"in_progress","assigneeAgentId":"<agent-uuid>"}
EOF

curl -s -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/assign_issue.json \
  "$BASE/issues/<issue-uuid>"
```

The assignment triggers the wakeup automatically (via `agent_wakeup_requests` table) —
no separate "wake" endpoint needed.

Monitor progress via `heartbeat_runs` table:
```sql
SELECT a.name, hr.status, hr.created_at
FROM heartbeat_runs hr JOIN agents a ON hr.agent_id = a.id
WHERE hr.created_at > NOW() - INTERVAL '15 minutes'
ORDER BY hr.created_at DESC;
```

## Prior Knowledge Integration

When migrating Paperclip to a new installation or re-deploying, prior agent memory
(PARA structure from `/paperclip/workspace/<session-uuid>/memory/para/`) should be
*filtered strategically*, not dumped wholesale. See `references/knowledge-integration.md`
for the analysis methodology, filtering rules, and injection format.

## Linked References

- `references/copilot-adapter-gap.md` — full diagnostic on Copilot adapter gap + mount fix
- `references/board-api-key.md` — board API key generation recipe (no UI available)
- `references/knowledge-integration.md` — methodology for filtering + injecting prior session knowledge
- `references/opencode-providers-models.md` — provider+model inventory; migration path Copilot→API
- `references/hermes-best-practices-paperclip.md` — smart routing, credential pools, fallback providers, skills management
- `references/zombie-cleanup.md` — procedure for cleaning stuck heartbeat runs and stale environment leases
- `references/agent-wakeup-heartbeat.md` — agent runtime_config heartbeat structure, wakeup mechanism, agent_wakeup_requests table, and curl best practices for the board API key

## Monitoring Cron

Canonical cron job pattern (runs from Hermes, uses board API key):
```
cronjob create --schedule "0 */4 * * *" \
  --name "Paperclip Monitor" \
  --enabled-toolsets terminal,web \
  --prompt "..."
```

The monitor queries: health, agents (with models), recent heartbeat runs,
active issues, and budget. Delivers a concise summary to the current chat.

## NotebookLM MCP (Research & Knowledge)

NotebookLM MCP (`nlm` CLI) can query research notebooks about Hermes Agent
best practices, architecture patterns, and operational guidance — directly
applicable to Paperclip's multi-agent setup.

**Auth recovery when Chrome isn't available:**
```bash
# If nlm login fails (no GUI, Chrome missing/broken):
# 1. Get fresh cookies from browser (Cookie-Editor extension → Export as Netscape)
# 2. Save to ~/.nlm/cookies.txt
# 3. Load manually:
nlm login --manual --file $HOME/.nlm/cookies.txt
# Then refresh MCP:
# mcp_notebooklm_mcp_refresh_auth()
```
Credentials expire quickly (hours). Re-export fresh cookies when auth goes stale.

## Pitfalls

- **CONTAINER HOME IS /paperclip, NOT /root.** This is the #1 cause of "config/auth works on host but not in container." Always verify: `docker exec paperclip-server-1 bash -c 'echo $HOME'`. Mounts to `/root/` are silently ignored by OpenCode.
- **DOCKER COMPOSE DOES NOT INCLUDE OPENCODE MOUNTS.** The docker-compose.yml at `docker/docker-compose.yml` only defines the `paperclip-data` volume. The OpenCode config mounts (`~/.opencode`, `~/.config/opencode`, `auth.json`) are NOT in the compose file. They must be added manually to `server.volumes`. After every `docker compose down && up`, these mounts are lost unless they're in the compose file. Always verify mounts: `docker inspect paperclip-server-1 --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} {{println}}{{end}}'`.
- **Rebuild resets adapter source code.** `docker compose build` builds from the repo source at `packages/adapters/opencode-local/src/index.ts`. Any previous modifications to the `models` array or `modelProfiles` are lost. The container will run whatever is currently committed in the repo. The DB agents may reference models that no longer exist in the adapter, causing a mismatch.
- **Empty auth.json → JSON Parse Error (not file-not-found).** When the `auth.json` mount is missing or the file is empty (0 bytes), OpenCode crashes with `SyntaxError: JSON Parse error: Unexpected EOF` — a misleading error that suggests a malformed file rather than a missing mount. Check with `docker exec paperclip-server-1 wc -c /paperclip/.local/share/opencode/auth.json`. If 0 bytes, the mount is broken.
- **Missing auth.json mount = Copilot invisible.** OpenCode stores provider credentials at `~/.local/share/opencode/auth.json`. Without mounting this file, Copilot/GitHub OAuth tokens are absent and `opencode models` only shows free-tier models. The `opencode.jsonc` config says "use copilot" but there's no token to authenticate.
- **OpenCode ≠ Copilot proxy.** `opencode run` calls OpenCode's own API. Adding `copilot` as a model name won't work unless OpenCode has Copilot as a configured provider (which requires the auth.json mount above).
- **acpx-local's `custom` agent is for ACP servers.** It won't work for non-ACP CLI tools. Must verify Copilot's ACP implementation is compatible with `acpx` library expectations.
- **Container has no `copilot` binary.** Any adapter that spawns `copilot` needs it installed in the container image or via volume mount.
- **Paperclip API requires auth.** Most endpoints return 401/403 without board session or API key. Use DB direct for inspection when no API key is available.
- **Adapter plugins** (`adapter-plugins.json`) are an optional external adapter loading mechanism, separate from built-in adapters.
- **Board API keys must be created in DB.** The Paperclip UI doesn't expose a key generation page. Use the SHA256(token) → `board_api_keys` table method above.
- **Inline JSON + board API key → shell quoting errors.** Writing the JSON body directly in the curl command with `-d '{"key":"value"}'` causes `unexpected EOF` errors on POST/PATCH requests when the `pcp_board_...` token is present in the same command. Always write the body to a file (`/tmp/body.json`) and use `-d @/tmp/body.json` instead. GET requests work fine with inline headers.
- **Model profiles reference unavailable models.** The `opencode_local` adapter's `modelProfiles` hardcodes a budget-lane model. When using Copilot (which only exposes `github-copilot/*` models), auxiliary/budget-lane runs fail with `"Configured OpenCode model is unavailable: openai/gpt-5.1-codex-mini"`. Primary runs succeed, so the error is easy to miss. Check `heartbeat_runs.error` for the telltale message. Fix: change profile model in `packages/adapters/opencode-local/src/index.ts` to one available through the current provider (e.g., `github-copilot/gpt-5-mini`), update the `models` array, rebuild the Docker image.
- **TypeScript constrains modelProfile keys.** `AdapterModelProfileDefinition.key` only accepts `"cheap"`. Adding a new key like `"free"` fails the Docker build. Work around it by changing the existing `cheap` profile.
- **CEO agent may revert agent models.** The CEO has `canCreateAgents: true`. During heartbeat runs, if it detects model issues it may change other agents' models to a "safe" fallback. After fixing adapter-level issues, re-check: `SELECT name, adapter_config->>'model' FROM agents;`.
