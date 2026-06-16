# Tool Verification: Beyond Comparison Tables

## Why

Comparison matrices (weighted scores) are the standard way to evaluate tools in architecture reviews. But they're time-sensitive — a tool that scored 8/10 six months ago may be deprecated, pivoted, or require infrastructure the table didn't capture.

This reference defines the verification workflow used to validate the *actual current state* of candidate tools before finalizing a recommendation.

## Verification Workflow

### 1. GitHub Repo Check

```bash
curl -s "https://api.github.com/repos/org/tool" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('Stars:', d.get('stargazers_count'))
print('Last push:', d.get('pushed_at'))
print('Archived:', d.get('archived'))
print('Description:', d.get('description'))
print('Topics:', d.get('topics'))
"
```

**Red flags:**
- `archived: true`
- Last push > 12 months ago
- Topics include `deprecated`, `legacy`, `unmaintained`

### 2. Docker-Compose Inspection

```bash
# Latest version
curl -sL "https://raw.githubusercontent.com/org/tool/main/docker-compose.yml"

# Or branch-specific
curl -sL "https://raw.githubusercontent.com/org/tool/main/legacy/docker-compose.ce.yaml"
```

**What to look for:**

| Signal | What it means |
|--------|---------------|
| 4+ services (app + DB + graph DB + ML service) | RAM estimate in comparison table is likely wrong |
| `OPENAI_API_KEY` in environment | Tool requires paid external API to function |
| `NEO4J` or similar graph DB dependency | Significant extra RAM (~500MB) |
| Community edition in `legacy/` directory | Open-source version is no longer the main focus |
| Image tags from latest release | Check if new releases exist |

### 3. Latest Release

```bash
curl -s "https://api.github.com/repos/org/tool/releases/latest" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('Tag:', d.get('tag_name'))
print('Date:', d.get('published_at'))
print('Body (preview):', d.get('body', '')[:300])
"
```

**Red flags:**
- No releases in 6+ months
- Latest release is a patch for a different product (e.g., "CrewAI compatibility" for a memory tool)
- Release notes only mention cloud/SaaS features, not self-hosted improvements

### 4. .env.example Inspection

```bash
curl -sL "https://raw.githubusercontent.com/org/tool/main/.env.example"
```

Look for required API keys. Tools that require `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` to function introduce external dependency and cost the comparison table may not capture.

### 5. Repo Structure Check

```bash
curl -s "https://api.github.com/repos/org/tool/contents/" | python3 -c "
import sys, json
for f in json.load(sys.stdin):
    print(f['name'], f['type'])
"
```

**Red flags:**
- `legacy/` directory at root with the actual self-hosted code
- Top-level README points to cloud signup
- No `docker-compose.yml` at root (only in `legacy/`)
- Main repo now contains only MCP server or SDK (cloud-only)

## Common Deprecation Patterns

| Pattern | Real example | What to do |
|---------|-------------|------------|
| CE moved to `legacy/` | `getzep/zep` (April 2025) | Look for community forks (e.g., N1nEmAn/openzep) or switch to active alternative |
| Cloud-only pivot with no clear self-hosted path | Various | Check if the last self-hosted version is still functional and what license it has |
| Community fork with different architecture | OpenZep (Zep-compatible, no Neo4j) | Evaluate the fork separately — don't assume it matches the original's characteristics |
| API key required for core function | Graphiti needing OpenAI | Consider whether the project is viable without that external service |

## Integration into the Comparison Matrix

When you find verified data that differs from the original comparison table:

1. Note the delta: "Original RAM: 300MB, Actual: 1.2GB (4 services)"
2. Note the dependency: "Requires OpenAI API key for embeddings"
3. Recalculate the weighted score if the new data changes rankings
4. Add a deprecation/maturity annotation to the table (⚠️)
5. If the tool is clearly dead/deprecated, move it to a "Descartado" section and note the replacement

## Example: Zep CE Verification

Result of applying this workflow to Zep Community Edition (April 2025):

| Check | Finding |
|-------|---------|
| GitHub repo | CE code in `legacy/` directory |
| Docker-compose | 4 services: Zep + pgvector + Graphiti + Neo4j |
| RAM estimate | ~1.2GB (not ~300MB from marketing materials) |
| API keys | `OPENAI_API_KEY` required for Graphiti |
| Latest release | CrewAI compat patch (not Zep CE improvements) |
| Community fork | N1nEmAn/openzep (compatible, no Neo4j) |
| Recommendation | Descarted. Mem0 chosen instead (MIT, active, 500MB, no API keys) |
