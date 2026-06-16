---
name: searxng
description: "Debug, configure, and integrate SearXNG as a Hermes web-search backend."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [searxng, search, self-hosted, web-search, debugging]
---

# SearXNG — Self-Hosted Search for Hermes

SearXNG is a privacy-respecting metasearch engine. When running locally (Docker),
it can serve as Hermes's web-search backend — free, private, no API keys needed.

## Quick Health Check

```bash
# Is it running?
docker ps | grep searxng
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
# Expect: 200
```

## The #1 Pitfall: 403 Forbidden on JSON API

**Symptom:** SearXNG responds to `curl http://localhost:8080/search?q=test&format=json`
with `403 Forbidden`, but the HTML UI works fine at `http://localhost:8080/`.

**Root cause:** `settings.yml` only allows `html` format. The relevant section:

```yaml
search:
  formats:
    - html          # ← JSON is not listed!
```

**Fix:** Add `json` to the formats list:

```yaml
search:
  formats:
    - html
    - json
```

After changing, restart the container:

```bash
docker restart searxng
```

Then verify:

```bash
curl -s "http://localhost:8080/search?q=test&format=json" | python3 -m json.tool | head -20
```

## Finding SearXNG Settings (Docker)

SearXNG stores its config at `/etc/searxng/settings.yml` inside the container.
If you don't know the volume mount:

```bash
# Option A: Read directly from container
docker exec searxng cat /etc/searxng/settings.yml

# Option B: Find volume path, then read with sudo
docker inspect searxng --format '{{json .Mounts}}'
# Look for Destination: "/etc/searxng" → read Source path
```

To edit, either:
- `docker exec -it searxng vi /etc/searxng/settings.yml` (if vi is installed)
- `docker cp searxng:/etc/searxng/settings.yml /tmp/ && edit && docker cp /tmp/settings.yml searxng:/etc/searxng/`

## Other Common Pitfalls

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| 403 on everything | `formats` missing the requested format | Add to `search.formats` list |
| Empty results | All engines disabled | Check `engines:` section — many are `disabled: true` by default; enable at least `brave`, `duckduckgo`, or `startpage` |
| Timeout > 3s | `outgoing.request_timeout` too low | Bump to 5.0–10.0 for slower engines |
| POST-only | `server.method: "POST"` | Use `curl -X POST -d "q=..."` instead of GET |

## Integrating with Hermes

Once SearXNG serves JSON, configure Hermes to use it as a web-search backend.
See `references/hermes-integration.md` for the config snippet.
