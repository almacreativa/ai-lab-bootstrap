# Docker Container Environment (your server)

> **Note:** This document describes the Paperclip Docker container setup on this server as of 2026-05-24.
> A previous session (2026-05-23) documented a Hermes-in-Docker setup — that was a pilot and is no longer active.
> The current Hermes instance runs directly on the host.

## Architecture

```
Host (your-server, Ubuntu 24.04)
├── Hermes Agent → runs directly on host (NOT in container)
│   ├── Workspace: $HOME/ai-lab/workspace/
│   ├── OpenCode: ~/.opencode/bin/opencode v1.15.5
│   └── Claude Code: ~/.local/bin/claude v2.1.150
├── Container: paperclip-server
│   ├── HOME: /paperclip (not /root!)
│   ├── Port: 3100 (API + UI)
│   ├── OpenCode binary: /usr/local/bin/opencode (pre-installed in image)
│   ├── Volumes:
│   │   ├── /paperclip (paperclip-data volume)
│   │   ├── /paperclip/workspace ← host:~/ai-lab/workspace
│   │   ├── /paperclip/.opencode ← host:~/.opencode (OpenCode binary + npm deps)
│   │   ├── /paperclip/.config/opencode ← host:~/.config/opencode (opencode.jsonc)
│   │   └── /paperclip/.local/share/opencode/auth.json ← host auth (Copilot OAuth)
│   └── DB: paperclip-db (postgres:17-alpine on ai-lab network)
├── Container: paperclip-db
│   └── Postgres 17, network ai-lab
└── Network: ai-lab (172.30.0.0/24, bridge)
```

## Key gotcha: HOME=/paperclip

The Paperclip container sets `HOME=/paperclip`. This means:
- OpenCode config must be at `/paperclip/.config/opencode/opencode.jsonc` — NOT `/root/.config/`
- OpenCode auth must be at `/paperclip/.local/share/opencode/auth.json` — NOT `/root/.local/share/`
- All volume mounts must target `/paperclip/` paths, not `/root/`

Always verify with: `docker exec paperclip-server bash -c 'echo $HOME'`

## Paperclip adapters using OpenCode

Paperclip agents (CEO, CTO, Coder) use the `opencode_local` adapter type. This adapter:
- Invokes OpenCode via `opencode run --format json`
- Model is specified in `adapter_config.model` (e.g., `github-copilot/claude-sonnet-4-6`)
- Config must be in OpenCode's native path (`$HOME/.config/opencode/opencode.jsonc`)
- Auth must be in OpenCode's native path (`$HOME/.local/share/opencode/auth.json`)

The adapter does NOT call Copilot directly — it calls OpenCode, which routes to Copilot if the model starts with `github-copilot/` and credentials exist.

## Docker compose file

Located at `~/ai-lab/repos/paperclip/docker-compose.yml`. The `paperclip-server` service uses `network_mode: bridge` on the `ai-lab` network.

Restart only `paperclip-server` (not the DB) when changing volumes:
```bash
cd ~/ai-lab/repos/paperclip
docker compose down paperclip-server
docker compose up -d paperclip-server
```

## Verification commands

```bash
# Health
curl http://localhost:3100/api/health

# OpenCode status inside container
docker exec paperclip-server opencode --version
docker exec paperclip-server opencode providers list
docker exec paperclip-server opencode models

# Container logs
docker logs paperclip-server --tail 50
```
