# Handoff: Deploy Hermes Agent en Ubuntu Server (your-server)

**Destinatario:** Agente implementador
**Autor:** OpenCode (sesion de arquitectura — 2026-05-22)
**Estado del entorno:** Servidor Ubuntu listo, Docker corriendo, Paperclip ya desplegado
**Objetivo:** Desplegar Hermes Agent con dashboard web accesible via Tailscale y primer test interactivo

---

## LO PRIMERO: pedirle al operador su OPENCODE_GO_API_KEY

Antes de ejecutar cualquier paso, preguntarle al operador:

> "Cual es tu OPENCODE_GO_API_KEY?"

Sin ese valor no se puede configurar el `.env` de Hermes (Paso 2).

---

## Contexto del servidor

| Item | Valor |
|---|---|
| OS | Ubuntu 24.04.4 LTS |
| Usuario | `<YOUR_USER>` (UID=1000, GID=1000) |
| IP Tailscale | `<SERVER_IP>` (hostname: `your-server`) |
| IP LAN | `<LAN_IP>` |
| Docker | 29.5.1 (usuario en grupo `docker`, sin sudo) |
| Docker Compose | v5.1.3 |
| Red Docker del lab | `ai-lab` ya existe (bridge, `172.30.0.0/24`) |
| Directorio base del lab | `$HOME/ai-lab/` |
| Paperclip | Ya desplegado en puerto `3100` |

---

## Arquitectura del deploy

```
┌──────────────────────────────────────────────────────┐
│             Red: host (network_mode: host)            │
│                                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │              hermes (container)                │  │
│  │                                                │  │
│  │  • hermes CLI (exec interactivo)               │  │
│  │  • dashboard en puerto 9119 (background)       │  │
│  └────────────────────┬───────────────────────────┘  │
│                        │ volumen                      │
└────────────────────────┼─────────────────────────────┘
                          │
          ┌───────────────┴─────────────────┐
          │  ~/.hermes/  (host bind mount)  │
          │  ├── .env        ← API key      │
          │  ├── config.yaml ← modelo/prov  │
          │  ├── workspace/  ← output lab   │
          │  ├── memories/   ← persistencia │
          │  └── skills/     ← habilidades  │
          └─────────────────────────────────┘
```

**Dashboard UI:** `http://<SERVER_IP>:9119` (via Tailscale)
**CLI interactivo:** `docker exec -it hermes hermes`

---

## Paso 1 — Clonar el repositorio

```bash
cd ~/ai-lab/repos
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
```

---

## Paso 2 — Crear directorio de datos y archivo .env

```bash
mkdir -p ~/.hermes
```

```bash
cat > ~/.hermes/.env << 'ENVEOF'
# Hermes Agent — API Keys del lab
# NO commitear — permisos 600

OPENCODE_GO_API_KEY=TU_KEY_AQUI

TERMINAL_TIMEOUT=120
TERMINAL_LIFETIME_SECONDS=300

WEB_TOOLS_DEBUG=false
VISION_TOOLS_DEBUG=false
IMAGE_TOOLS_DEBUG=false
ENVEOF
chmod 600 ~/.hermes/.env
```

---

## Paso 3 — Crear config.yaml

```bash
cat > ~/.hermes/config.yaml << 'YAMLEOF'
# Hermes Agent — Configuracion del lab
# Provider: OpenCode Go (modelos open-source)

model:
  provider: "opencode_go"
  default: "deepseek-v4-pro"

terminal:
  backend: "local"
  cwd: "/opt/data/workspace"
  timeout: 180
  lifetime_seconds: 300
  container_persistent: true

memory:
  memory_enabled: true
  user_profile_enabled: true

agent:
  max_turns: 60
  verbose: false
  reasoning_effort: "medium"

display:
  compact: false
  tool_progress: "all"

compression:
  enabled: true
  threshold: 0.50

skills:
  creation_nudge_interval: 15
YAMLEOF
chmod 600 ~/.hermes/config.yaml
```

---

## Paso 4 — Crear docker-compose.yml adaptado

```bash
cat > ~/ai-lab/repos/hermes-agent/docker-compose.yml << 'COMPOSEEOF'
# Hermes Agent — docker-compose for lab
# Dashboard accesible en http://<SERVER_IP>:9119

services:
  hermes:
    build: .
    image: hermes-agent
    container_name: hermes
    restart: unless-stopped
    network_mode: host
    volumes:
      - $HOME/.hermes:/opt/data
      - $HOME/ai-lab/workspace:/opt/data/workspace
    environment:
      - HERMES_UID=1000
      - HERMES_GID=1000
      - HERMES_DASHBOARD=1
      - HERMES_DASHBOARD_HOST=0.0.0.0
      - HERMES_DASHBOARD_PORT=9119
    command: ["sleep", "infinity"]
COMPOSEEOF
```

---

## Paso 5 — Build y arranque

```bash
cd ~/ai-lab/repos/hermes-agent
HERMES_UID=1000 HERMES_GID=1000 docker compose up -d --build
docker compose logs -f hermes
```

---

## Paso 6 — Verificar dashboard

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:9119
```

---

## Paso 7 — Verificar modelo y API key

```bash
docker exec hermes /opt/hermes/.venv/bin/hermes --version
docker exec -it hermes /opt/hermes/.venv/bin/hermes chat -q "responde solo con la palabra: ok"
```

---

## Paso 8 — Test de escritura en workspace

```bash
docker exec -it hermes /opt/hermes/.venv/bin/hermes chat -q "Create a file called hermes-test.txt in /opt/data/workspace with the content: Hermes is working"
```

```bash
cat ~/ai-lab/workspace/hermes-test.txt
```

---

## Paso 9 — Firewall UFW

```bash
sudo ufw allow ssh
sudo ufw allow in on tailscale0 to any port 9119
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

---

## Verificacion Final

```bash
docker compose ps
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:9119
docker exec hermes /opt/hermes/.venv/bin/hermes --version
cat ~/ai-lab/workspace/hermes-test.txt
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
ls -la ~/.hermes/
```

---

## Mantenimiento

```bash
cd ~/ai-lab/repos/hermes-agent && docker compose down
docker compose restart hermes
docker compose logs -f hermes
docker exec -it hermes /opt/hermes/.venv/bin/hermes
git pull && docker compose up -d --build
```

---

## Troubleshooting

Standard troubleshooting for port conflicts, API key issues, permission errors, model not found.

---

*No contiene API keys reales.*
