# Hermes Integration with Self-Hosted SearXNG

## Config Snippet

Add to `~/.hermes/config.yaml`:

```yaml
# Use SearXNG as web search backend
web_search:
  provider: searxng
  base_url: "http://localhost:8080"
  # SearXNG default is POST; adjust if your instance uses GET
  method: POST
```

Or use the interactive tool picker:

```bash
hermes tools
# → Navigate to 'web' or 'search' toolset
# → Configure search backend → Custom SearXNG → set URL
```

## Environment Variables

Set in `~/.hermes/.env` or config.yaml:

```bash
# If SearXNG requires no auth (default local setup):
SEARXNG_BASE_URL=http://localhost:8080
SEARXNG_METHOD=POST
```

## Verification

After configuring, test from a Hermes session:

```
/search what is the capital of France
```

Or programmatically:

```bash
hermes chat -q "Search the web for: latest AI news" -Q
```

## Security Notes

- `localhost:8080` is only accessible from the host — fine for local use
- If exposing SearXNG externally, set `server.secret_key` and enable `server.limiter`
- For multi-user Hermes gateway, consider keeping SearXNG on `127.0.0.1` only
