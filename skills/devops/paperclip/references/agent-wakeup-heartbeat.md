# Agent Wakeup & Heartbeat Configuration

Paperclip agents use heartbeats to periodically check for assigned work. The wakeup
mechanism triggers agent execution when an issue is assigned.

## runtime_config Structure

Agent heartbeat config lives in `runtime_config.heartbeat` (JSONB column):

```json
{
  "heartbeat": {
    "enabled": true,
    "intervalSec": 1200,
    "cooldownSec": 30,
    "wakeOnDemand": true,
    "maxConcurrentRuns": 20
  }
}
```

| Field | Meaning |
|---|---|
| `enabled` | Master switch. `false` = agent never auto-runs. |
| `intervalSec` | How often the timer-based heartbeat fires (default 1200 = 20 min). |
| `cooldownSec` | Min seconds between consecutive runs (default 30). |
| `wakeOnDemand` | When `true`, issue assignment triggers immediate wakeup via `agent_wakeup_requests`. |
| `maxConcurrentRuns` | Cap on simultaneous heartbeat runs (default 20). |

## Enable Heartbeat for an Agent

```sql
UPDATE agents
SET runtime_config = jsonb_set(
  runtime_config,
  '{heartbeat,enabled}',
  'true'
)
WHERE id = '<agent-uuid>';
```

To enable wake-on-demand in the same call:

```sql
UPDATE agents
SET runtime_config = jsonb_set(
  jsonb_set(runtime_config, '{heartbeat,enabled}', 'true'),
  '{heartbeat,wakeOnDemand}',
  'true'
)
WHERE id = '<agent-uuid>';
```

Check current config:

```sql
SELECT id, name, runtime_config->'heartbeat'
FROM agents
WHERE company_id = '<company-uuid>';
```

## agent_wakeup_requests Table

Insert a manual wakeup request to force an immediate agent run:

```sql
INSERT INTO agent_wakeup_requests
  (company_id, agent_id, source, reason, payload, status)
VALUES
  ('<company-uuid>', '<agent-uuid>', 'manual', 'Reason for wakeup', '{}', 'queued');
```

Key fields:
- `source` — `manual`, `assignment`, `timer`, or `system`
- `reason` — human-readable explanation
- `payload` — JSONB, typically `{"issueId": "<uuid>"}`
- `status` — `queued` → picked up by heartbeat runner → `claimed` → `finished`

## Invocation Sources

The `heartbeat_runs.invocation_source` column records how a run was triggered:

| Source | Trigger |
|---|---|
| `timer` | Periodic heartbeat interval expired |
| `assignment` | Issue was assigned to the agent (requires `wakeOnDemand: true`) |
| `manual` | Direct insert into `agent_wakeup_requests` |

## curl Best Practices with the API Token

The board API key (`pcp_board_...`) is a plain hex+underscore token (58 chars).
Three reliable patterns exist, ordered by flexibility:

### Pattern A: Inline token + file-based body (recommended for one-offs)

Write the JSON body to a temp file first, then use `-d @file.json`:

```bash
cat > /tmp/issue.json <<'EOF'
{"title":"Task","description":"Desc","status":"todo","priority":"high"}
EOF

curl -s -X POST \
  -H "Authorization: Bearer pcp_board_<full-token>" \
  -H "Content-Type: application/json" \
  -d @/tmp/issue.json \
  "http://<SERVER_IP>:3100/api/companies/<company-uuid>/issues"
```

**❌ Avoid: inline JSON body** — shell quoting edge cases with long descriptions
break the command, especially when the token appears in the same invocation.

### Pattern B: Token from file + shell script (recommended for multi-step workflows)

Store the token in `/tmp/pcp_token.txt` and read it at runtime in a script.
This avoids ever writing the full token in your command and works with inline
JSON bodies:

```bash
#!/bin/bash
TOK=$(cat /tmp/pcp_token.txt)

ISSUE_DATA='{"title":"Task","description":"Desc","status":"todo","priority":"high"}'
curl -sX POST \
  -H "Authorization: Bearer $TOK" \
  -H "Content-Type: application/json" \
  -d "$ISSUE_DATA" \
  "http://<SERVER_IP>:3100/api/companies/<company-uuid>/issues"
```

For multi-step workflows (create → assign → monitor), write the script to
`/tmp/<name>.sh`, then `bash /tmp/<name>.sh`.

### Pattern C: Combined flag GET

```bash
TOK=$(cat /tmp/pcp_token.txt) && curl -sH "Authorization: Bearer $TOK" \
  "http://<SERVER_IP>:3100/api/companies/<company-uuid>/agents" | jq length
```

⚠️ **PITFALL — inline JSON + PATCH fails with shell EOF errors.** Even with
file-based bodies, PATCH requests can trigger `unexpected EOF` when the token
is written inline. Pattern B (script file) is the most reliable for PATCH.

## Consuming Agent Output for External Demos

After agents complete their work, the output lives in three places:

| Location | What | When to use |
|---|---|---|
| `issue_work_products` table | `type = 'artifact'`, `status = 'ready_for_review'`, `is_primary = true` | Programmatic access to artifact metadata |
| `issue_comments` table | `author_agent_id = <agent-uuid>` — agent's summary of what was produced | Quick overview without reading the full file |
| `/paperclip/<company>-deliverables/<PREFIX>-<N>-<slug>.md` | Full markdown deliverable on the container filesystem | Reading the actual content for reuse |

### Retrieving and Repurposing Agent Output

1. **Check the comment first** — the agent leaves a structured note with the artifact path:
   ```sql
   SELECT body FROM issue_comments
   WHERE issue_id = '<issue-uuid>' ORDER BY created_at DESC LIMIT 1;
   ```

2. **Read the markdown file** from the container:
   ```bash
   docker exec paperclip-server-1 cat /paperclip/<company>-deliverables/<PREFIX>-<N>-<slug>.md
   ```

3. **Build a client-facing presentation** from the structured data:
   - The CSO produces: profile, narrative, structure (the "what" and "why")
   - The Analyst produces: numbers, projections, break-even (the "how much")
   - Combine both into a single HTML/PDF deliverable

### OpenCode for Web Demo Scaffolding

When you need a quick client-facing web page from agent output:

```bash
# 1. Let OpenCode generate a scaffold
opencode run --format json --model opencode/big-pickle \
  "Create a single HTML file at /path/to/index.html — a stunning dark-mode microsite..."

# 2. OpenCode generates visually impressive HTML but with PLACEHOLDER data.
#    It doesn't know the real numbers from Paperclip. Rewrite the content
#    section with actual data from the agent deliverables.
```

⚠️ **PITFALL — OpenCode generates visually polished but content-generic HTML.** It will produce working tabs, animations, and styling, but the numbers, feature lists, and value propositions will be fabricated or generic. Always replace the data payload section with actual Paperclip agent output.

## Multi-Agent Cascade Workflow

When you need a sequence of agents working on related issues (e.g., strategy
→ analysis → review), use a cascade pattern:

1. **Check which agents can wake** — query `runtime_config->'heartbeat'`
   for `enabled` and `wakeOnDemand` status:
   ```sql
   SELECT id, name, runtime_config->'heartbeat' FROM agents
   WHERE company_id = '<company-uuid>';
   ```

2. **Enable heartbeat + wakeOnDemand for agents that need it**:
   ```sql
   UPDATE agents SET runtime_config = jsonb_set(
     jsonb_set(runtime_config, '{heartbeat,enabled}', 'true'),
     '{heartbeat,wakeOnDemand}', 'true'
   ) WHERE id = '<agent-uuid>';
   ```

3. **Create and assign stage N**, then poll `heartbeat_runs` until `succeeded`:
   ```sql
   SELECT id, status, started_at, finished_at, error
   FROM heartbeat_runs
   WHERE agent_id = '<agent-uuid>'
   ORDER BY created_at DESC LIMIT 1;
   ```

4. **Insert a manual wakeup request** to accelerate if the agent's `intervalSec`
   is long (1200s = 20 min):
   ```sql
   INSERT INTO agent_wakeup_requests
     (company_id, agent_id, source, reason, payload, status)
   VALUES
     ('<company-uuid>', '<agent-uuid>', 'manual',
      'New issue <PREFIX>-N assigned: <reason>',
      '{"issueId": "<issue-uuid>"}', 'queued');
   ```

5. **Create stage N+1 issue** referencing the previous stage's output, assign it,
   and repeat until the cascade completes.

### Example cascade (3 agents):

| Order | Agent | Produces | Typical duration |
|---|---|---|---|
| 1 | CSO | Strategic analysis, cost structure, pricing framework | ~2-3 min |
| 2 | Analyst | Detailed budget, projections, break-even | ~3-5 min |
| 3 | CEO | Consolidation, review, final deliverable | ~2-4 min |

Each subsequent issue should reference the previous issue by ID so the agent has context. Check `issue_work_products` and `issue_comments` after each stage completes to find the output artifacts.
