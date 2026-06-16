# Inventario de servicios — <HOSTNAME>
**Actualizado:** 2026-06-13 (post-hardening + KM completo + Engram)

## Servicios y binds (regla: NADA en 0.0.0.0 salvo SSH con UFW)

| Servicio | Runtime | Puerto / bind | RAM aprox | Acceso |
|----------|---------|---------------|-----------|--------|
| SSH | systemd | 0.0.0.0:22 — UFW: solo Tailscale + LAN | — | Mac/tailnet |
| Hermes gateway + dashboard | bare metal (`$HOME/.hermes-env/bin/hermes`) | 0.0.0.0:9119 — UFW: Tailscale + 172.16/12 (Kuma) | ~200MB | tailnet |
| Paperclip server | Docker | `<SERVER_IP>:3100` | ~1GB (limit 4g) | tailnet |
| Paperclip DB (pgvector/pg17, vol `paperclip_pgdata_v2`) | Docker | `127.0.0.1:5432` | ~170MB | local |
| Mem0 (wrapper FastAPI) | Docker | `127.0.0.1:8765` + red `paperclip_default` (`mem0:8765`) | ~380MB limit | local + contenedores |
| Ollama (nomic-embed-text) | Docker | `127.0.0.1:11434` | ~512MB limit | local + red mem0 |
| Outline | Docker | `127.0.0.1:3010` ← `tailscale serve` → `https://<HOSTNAME>.<TAILSCALE_DOMAIN>` | ~1GB limit | tailnet (HTTPS) |
| Outline Postgres 16 / Redis 7 | Docker | internos | 384/256MB limit | — |
| Uptime Kuma | Docker | `<SERVER_IP>:3001` + redes outline/mem0 | 128MB limit | tailnet |
| SearXNG | Docker | `127.0.0.1:8080` | ~150MB | local |
| Portainer | Docker | `<SERVER_IP>:9443` | ~80MB | tailnet |
| **NLM Gateway** | host (uvicorn, cron @reboot) | 0.0.0.0:8770 — UFW: solo 172.16/12 (contenedores) y local | ~80MB | contenedores Paperclip |
| **Engram** | host (binario Go, stdio MCP bajo demanda) | sin puerto (stdio) | ~5-15MB por sesión, 0 en reposo | Claude Code, OpenCode, Antigravity |
| Syncthing | systemd user | GUI `127.0.0.1:8384`; P2P 22000 — UFW: Tailscale + LAN | ~60MB | — |

**RAM total en uso:** verificar con `free -h`. Engram no suma RAM residente (stdio efímero).

## Carpetas Syncthing (↔ Mac)

| ID | Servidor | Contenido |
|----|----------|-----------|
| `ai-lab-knowledge` | `~/ai-lab/knowledge` | knowledge multi-empresa + wikis de agentes (Obsidian) |
| `ai-lab-ops` | `~/ai-lab/ops` | espejos de deliverables por empresa |
| `shared-demos` | `~/shared/demos` | intercambio de trabajo |

## Redes Docker relevantes

- `paperclip_default`: paperclip-server, paperclip-db, **mem0** (conectado para que los agentes lleguen a `mem0:8765`), **uptime-kuma**
- `mem0_default`: mem0, ollama, uptime-kuma
- `outline_default`: outline, outline-postgres, outline-redis, uptime-kuma

## UFW (baseline)

`deny incoming` por defecto. Permitidos: 22 (Tailscale `100.64.0.0/10` + LAN `192.168.0.0/24`),
9119 (Tailscale + `172.16.0.0/12` para el monitor de Kuma), 22000 (Tailscale + LAN).
**Importante:** UFW NO protege puertos publicados por Docker — la protección es el bind.
Script idempotente: `~/ai-lab/scripts/security-apply-sudo.sh`.
