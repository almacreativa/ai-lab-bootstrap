# Container-aware diagnostics for AI coding CLIs

When an AI coding CLI (OpenCode, Claude Code, Codex) appears missing, run this checklist before concluding it's not installed.

## 1. Are you in a container?

```bash
ls /.dockerenv        # exists → inside Docker
cat /proc/1/cgroup    # alternative check
```

## 2. Is the CLI installed inside the container?

```bash
which opencode
npm list -g --depth=0 | grep opencode
find / -name 'opencode' -type f 2>/dev/null
```

## 3. Is it a provider, not a CLI?

Hermes may use OpenCode as a *model provider* (API endpoint), not as a CLI tool:

```bash
# Check if it's a Hermes provider plugin
ls /opt/hermes/plugins/model-providers/opencode-zen/
cat /opt/hermes/plugins/model-providers/opencode-zen/plugin.yaml
```

Provider plugins expose API endpoints (`https://opencode.ai/zen/v1`). They are NOT CLI tools.

## 4. Might it be on the host?

If you're in a container and the CLI is on the host:

```bash
# Check Docker socket access
docker ps 2>&1                    # fails → no socket mounted
docker exec hermes which opencode # alternative if socket works

# Check network access to host
ip route | grep default           # gateway = host
curl -s host.docker.internal:22   # SSH test
```

Options:
- Install inside container: `npm i -g opencode-ai`
- Bind-mount from host in `docker-compose.yml`
- Run via `docker exec` from host (needs Docker socket)

## 5. Network to sibling containers

Even without Docker socket, you may reach other containers on shared networks:

```bash
hostname -I                           # your IPs on Docker networks
curl -s -m 2 http://172.30.0.X:PORT/  # probe known ports
```

## 6. HOME path mismatch when bind-mounting config/auth (CRITICAL)

OpenCode resolves config and auth relative to `$HOME`:
- **Config:** `$HOME/.config/opencode/opencode.jsonc`
- **Auth:** `$HOME/.local/share/opencode/auth.json`
- **Binary install:** `$HOME/.opencode/bin/opencode`

**Common trap:** Mounting host paths to `/root/` assuming the container runs as root with `HOME=/root/`. Many Docker images set a custom `HOME` (e.g., Paperclip uses `HOME=/paperclip`, some Node images use `HOME=/home/node`).

**Diagnostic sequence:**

```bash
# 1. What is the container's HOME?
docker exec <container> bash -c 'echo $HOME'

# 2. Where does OpenCode actually look?
docker exec <container> bash -c 'echo "Config: ~/.config/opencode/"; echo "Auth: ~/.local/share/opencode/"'

# 3. Are the files at the right path?
docker exec <container> cat $HOME/.config/opencode/opencode.jsonc
docker exec <container> cat $HOME/.local/share/opencode/auth.json

# 4. Do providers show credentials?
docker exec <container> opencode providers list
```

**Fix:** Mount host paths into `$HOME` of the container, not `/root/`:

```yaml
# WRONG — assumes HOME=/root
volumes:
  - /home/user/.opencode:/root/.opencode:ro
  - /home/user/.config/opencode:/root/.config/opencode:ro

# CORRECT — uses actual container HOME
volumes:
  - /home/user/.opencode:/paperclip/.opencode:ro
  - /home/user/.config/opencode:/paperclip/.config/opencode:ro
  - /home/user/.local/share/opencode/auth.json:/paperclip/.local/share/opencode/auth.json:ro
```

When mounting only a single file (e.g., `auth.json`), mount just that file rather than the whole directory to avoid shadowing the container's own state (databases, logs, session data).

**Symptoms of this bug:**
- `opencode providers list` shows `0 credentials` despite auth being mounted
- `opencode models` shows only free models, not the provider-specific ones
- The config file exists at the mount path but OpenCode ignores it
