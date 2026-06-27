# Guía post-bootstrap — Completar la configuración del lab

Después de correr `bootstrap.sh` y `setup-instance.sh`, el lab tiene
infraestructura base pero los servicios no están operativos.
Esta guía lleva al lab de "instalado" a "funcionando".

**Diseñada para ser leída por un agente AI o un operador humano.**
Cada fase tiene prerrequisitos, pasos y verificación.

---

## Orden de fases

```
Fase 0: Verificar base         ← confirmar que bootstrap completó bien
Fase 1: Secrets                 ← sin esto nada arranca
Fase 2: Autenticaciones         ← logins interactivos (requiere humano)
Fase 3: Servicios core          ← Hermes, Dagu, MoolMesh
Fase 4: Stack de agentes        ← Paperclip, Ollama, Mem0
Fase 5: Observabilidad          ← Uptime Kuma, Glance, guards
Fase 6: Colaboración            ← Outline, Syncthing
Fase 7: Verificación final      ← guards limpios, todo verde
```

---

## Fase 0 — Verificar base

**Prerrequisito:** `bootstrap.sh` y `setup-instance.sh` completados.

```bash
# Verificar estructura
ls ~/ai-lab/{ops,data,logs,scripts,repos,stacks,workspace,knowledge}

# Verificar binarios clave
for bin in docker git node uv claude dagu mool restic age; do
  command -v $bin && echo "OK: $bin" || echo "FALTA: $bin"
done

# Verificar ops framework
ls ~/ai-lab/ops/{guards,backup,runbooks,manifests}
cat ~/ai-lab/ops/core-manifest.yaml | head -5

# Verificar CLAUDE.md generado
head -20 ~/CLAUDE.md
```

**Resultado esperado:** todo existe, manifest generado, CLAUDE.md con hostname correcto.

---

## Fase 1 — Secrets

**Tipo:** automatizable parcialmente (copiar plantillas, el humano completa valores).

Los templates están en el repo: `templates/*.example`

### 1.1 Hermes

```bash
mkdir -p ~/.hermes
cp ~/ai-lab-bootstrap/templates/hermes.env.example ~/.hermes/.env
chmod 600 ~/.hermes/.env
# EDITAR: completar TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, API keys
```

**Keys requeridas mínimas:**
- `TELEGRAM_BOT_TOKEN` — crear bot con @BotFather
- `TELEGRAM_ALLOWED_USERS` — chat_id numérico (obtener de @userinfobot)
- Al menos una API key de LLM (OPENCODE_GO_API_KEY o equivalente)

### 1.2 Agents env

```bash
cp ~/ai-lab-bootstrap/templates/agents.env.example ~/.env_agents
chmod 600 ~/.env_agents
# EDITAR: completar ANTHROPIC_API_KEY y/o OPENAI_API_KEY
```

### 1.3 Scripts operativos (backup, notificaciones)

```bash
cp ~/ai-lab-bootstrap/templates/agents.env.example ~/ai-lab/scripts/.env 2>/dev/null
# O crear manualmente:
cat > ~/ai-lab/scripts/.env << 'EOF'
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
# Backup (completar cuando se configure — ver Fase 5)
RESTIC_REPOSITORY=
RESTIC_PASSWORD=
B2_ACCOUNT_ID=
B2_BACKUP_KEY=
EOF
chmod 600 ~/ai-lab/scripts/.env
```

### 1.4 Paperclip (si se va a desplegar)

```bash
cp ~/ai-lab-bootstrap/templates/paperclip.env.example ~/ai-lab/repos/paperclip/.env.paperclip
chmod 600 ~/ai-lab/repos/paperclip/.env.paperclip
# EDITAR: generar BETTER_AUTH_SECRET con: openssl rand -hex 32
# EDITAR: PAPERCLIP_PUBLIC_URL=http://<TAILSCALE_IP>:3100
```

**Verificación:**
```bash
for f in ~/.hermes/.env ~/.env_agents ~/ai-lab/scripts/.env; do
  [ -f "$f" ] && echo "OK: $f ($(stat -c %a $f))" || echo "FALTA: $f"
done
```

---

## Fase 2 — Autenticaciones interactivas

**Tipo:** requiere humano — cada paso necesita login manual.

### 2.1 Tailscale

```bash
sudo tailscale up --ssh
# Verificar:
tailscale status
```

### 2.2 GitHub CLI

```bash
gh auth login
# Verificar:
gh auth status
```

### 2.3 Claude Code

```bash
claude
# Seguir el flujo de login en el navegador
# Verificar:
claude --version
```

### 2.4 NotebookLM (nlm) — login headless via CDP

```bash
# Terminal 1 en el servidor:
Xvfb :99 -screen 0 1280x720x24 &
export DISPLAY=:99
nlm login --force

# Terminal 2 en el servidor:
ss -tlnp | grep 9222    # verificar que Chromium expone CDP

# Desde Mac (terminal local):
ssh -L 9222:localhost:9222 <usuario>@<IP-servidor>

# En Chrome del Mac:
# chrome://inspect → Configure → localhost:9222
# Clic en 'inspect' en el tab de Google Sign-in
# Completar login de Google

# Verificar:
nlm notebook list
```

### 2.5 Gemini CLI (opcional)

```bash
gemini    # seguir flujo OAuth
```

### 2.6 Opencode (opcional)

```bash
opencode  # seleccionar provider y autenticar
```

---

## Fase 3 — Servicios core

**Prerrequisito:** Fase 1 completada (secrets existen con valores reales).

### 3.1 Dagu

```bash
systemctl --user start dagu
systemctl --user is-active dagu  # debe decir "active"

# Primer acceso web — crear credenciales admin:
# Abrir http://<TAILSCALE_IP>:8480
# Crear usuario y contraseña
# Guardar en ~/.hermes/.env:
#   DAGU_AUTH_USER=<usuario>
#   DAGU_AUTH_PASS=<contraseña>
```

### 3.2 MoolMesh

```bash
systemctl --user start moolmesh
systemctl --user is-active moolmesh  # debe decir "active"

# Verificar:
curl -s http://localhost:5200/api/health | head -1
```

### 3.3 Hermes

```bash
sudo systemctl start hermes
sudo systemctl is-active hermes  # debe decir "active"

# Verificar:
curl -s http://localhost:9119/health
# O enviar /start al bot de Telegram
```

**Verificación de fase:**
```bash
systemctl --user is-active dagu moolmesh
sudo systemctl is-active hermes
```

---

## Fase 4 — Stack de agentes

**Prerrequisito:** Fase 1.4 completada, Docker corriendo.

### 4.1 Paperclip

```bash
cd ~/ai-lab/repos/paperclip
docker compose -f docker/docker-compose.yml \
  --env-file .env.paperclip \
  --project-name paperclip \
  up -d --build

# Verificar:
docker ps --filter name=paperclip
curl -s http://localhost:3100/health || echo "Esperando arranque..."
```

### 4.2 Ollama

```bash
docker run -d \
  --name ollama \
  --restart unless-stopped \
  -p 127.0.0.1:11434:11434 \
  -v ollama_data:/root/.ollama \
  --memory=512m \
  ollama/ollama:latest

# Descargar modelo de embeddings:
docker exec ollama ollama pull nomic-embed-text

# Verificar:
curl -s http://localhost:11434/api/tags | head -1
```

### 4.3 Mem0

```bash
# Requiere stack en ~/ai-lab/stacks/mem0/
# Si existe docker-compose:
cd ~/ai-lab/stacks/mem0
docker compose up -d

# Verificar:
curl -s http://localhost:8765/health
```

### 4.4 Redes Docker (conectar servicios)

```bash
# Conectar Uptime Kuma a las redes de los stacks para monitoreo:
docker network connect paperclip_default uptime-kuma 2>/dev/null || true
docker network connect mem0_default uptime-kuma 2>/dev/null || true

# Conectar Mem0 a la red de Paperclip:
docker network connect paperclip_default mem0 2>/dev/null || true

# Conectar Ollama a la red de Mem0:
docker network connect mem0_default ollama 2>/dev/null || true
```

**Verificación de fase:**
```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | sort
```

---

## Fase 5 — Observabilidad

### 5.1 Uptime Kuma

```bash
# Ya desplegado por el bootstrap
# Abrir http://<TAILSCALE_IP>:3001
# Crear usuario admin
# Agregar monitores para cada servicio
```

**Monitores sugeridos:**
| Servicio | Tipo | URL/comando |
|----------|------|-------------|
| Hermes | HTTP | `http://localhost:9119/health` |
| Paperclip | HTTP | `http://localhost:3100/health` |
| Dagu | HTTP | `http://localhost:8480` |
| Ollama | HTTP | `http://localhost:11434/api/tags` |
| Mem0 | HTTP | `http://localhost:8765/health` |

### 5.2 Backup (cuando aplique)

```bash
bash ~/ai-lab/ops/backup/setup-backup.sh
# Seguir el wizard: B2 creds → restic password → Uptime Kuma push URL
# Verificar:
bash ~/ai-lab/ops/backup/lab-backup.sh
```

### 5.3 Portainer

```bash
# Ya desplegado por el bootstrap
# Abrir https://<TAILSCALE_IP>:9443
# Crear usuario admin (debe hacerse dentro de los primeros 5 minutos)
```

### 5.4 Guards

```bash
# Regenerar manifest con estado actual:
bash ~/ai-lab/ops/manifests/generate-core-manifest.sh

# Correr guards para verificar:
bash ~/ai-lab/ops/guards/core-guard.sh
bash ~/ai-lab/ops/guards/bootstrap-guard.sh
```

**Resultado esperado:** 0 GAPs, 0 DRIFTs (salvo backup si no se configuró).

---

## Fase 6 — Colaboración (opcional)

### 6.1 Outline (wiki)

```bash
# Requiere stack en ~/ai-lab/stacks/outline/
# con .env configurado (SECRET_KEY, UTILS_SECRET, OIDC Google)
cd ~/ai-lab/stacks/outline
docker compose up -d

# Exponer via Tailscale:
sudo tailscale serve --bg --https=443 http://localhost:3010
```

### 6.2 Syncthing

```bash
# Obtener Device ID:
syncthing --device-id

# Acceder a GUI via tunnel SSH (nunca exponer 8384):
# Desde Mac: ssh -L 8384:localhost:8384 <usuario>@<IP>
# Abrir http://localhost:8384

# Configurar:
# - Usuario y contraseña en Settings → GUI
# - Desactivar: Global Discovery, Enable Relays, NAT Traversal
# - Agregar carpeta: knowledge → ~/ai-lab/knowledge
# - File Versioning: Staggered, 90 días
```

### 6.3 NLM Gateway (para agentes Paperclip)

```bash
# Requiere stack en ~/ai-lab/stacks/nlm-gateway/
# con .env configurado (GATEWAY_API_KEY)
# Verificar:
curl -s http://localhost:8770/health
```

---

## Fase 7 — Verificación final

```bash
# 1. Regenerar manifest con todo corriendo
bash ~/ai-lab/ops/manifests/generate-core-manifest.sh

# 2. Correr todos los guards
bash ~/ai-lab/ops/guards/core-guard.sh
bash ~/ai-lab/ops/guards/bootstrap-guard.sh

# 3. Verificar CLAUDE.md refleja los servicios activos
head -50 ~/CLAUDE.md

# 4. Verificar DAGs visibles en Dagu
# Abrir http://<TAILSCALE_IP>:8480 → deben verse todos los workflows

# 5. Regenerar CLAUDE.md si se agregaron servicios
cd ~/ai-lab-bootstrap && ./setup-instance.sh --skip-backup --skip-services
# (solo regenera CLAUDE.md y manifest si ops/ ya existe)
```

**Lab operativo cuando:**
- [ ] Guards reportan 0 GAPs, 0 DRIFTs
- [ ] Hermes responde en Telegram
- [ ] Dagu muestra DAGs con schedule activo
- [ ] Uptime Kuma monitorea todos los servicios
- [ ] Glance muestra dashboard verde
- [ ] CLAUDE.md refleja el estado real

---

## Notas para agentes AI

- Esta guía es la referencia canónica post-bootstrap. Si el operador pide
  "terminar de configurar el lab", seguir estas fases en orden.
- Las fases 1 y 2 requieren intervención humana (secrets y logins).
  Guiar al operador paso a paso, no intentar ejecutar por él.
- Después de cada fase, correr la verificación antes de avanzar.
- Si un servicio no aplica al lab (ej: Paperclip, Outline), saltar su sección.
- Al terminar, regenerar manifest y correr guards para confirmar estado limpio.
