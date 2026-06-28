# Guía post-bootstrap — Completar la configuración del lab

Después de correr `bootstrap.sh` y `setup-instance.sh`, el lab tiene
infraestructura base pero los servicios no están operativos.
Esta guía lleva al lab de "instalado" a "funcionando".

**Diseñada para ser leída por un agente AI o un operador humano.**
Cada fase tiene prerrequisitos, pasos y verificación.

---

## Arquitectura del lab

Un lab tiene 3 capas de servicios:

```
┌─────────────────────────────────────────────────────┐
│  AGENTES CORE (la razón de ser del lab)             │
│  Paperclip · Hermes · Odysseus                      │
├─────────────────────────────────────────────────────┤
│  INFRAESTRUCTURA (setup-instance.sh los genera)     │
│  Portainer · Uptime Kuma · SearXNG · Glance · Dagu │
├─────────────────────────────────────────────────────┤
│  BASE (bootstrap.sh los instala)                    │
│  Docker · Node · Python · Tailscale · restic        │
└─────────────────────────────────────────────────────┘
```

### Agentes core — qué hace cada uno

| Agente | Rol | Corre como | Dependencias |
|--------|-----|------------|-------------|
| **Hermes** | Agente conversacional vía Telegram. Orquesta tareas, consulta Paperclip via MCP, ejecuta skills. | systemd (Python nativo en venv) | Telegram bot token, API keys de LLM |
| **Paperclip** | Gestión de proyectos + orquestación de agentes de código. UI web para issues, boards, agentes. | Docker (3 containers: server, db, xai-proxy) | PostgreSQL (incluido), Hermes (para MCP) |
| **Odysseus** | AI workspace. Chat multi-modelo, RAG, búsqueda web, research. UI web. | Docker (2 containers: app, chromadb) | SearXNG (búsqueda), ChromaDB (incluido) |

### Orden de instalación

```
1. Hermes    ← primero porque Paperclip lo necesita como canal MCP
2. Paperclip ← segundo porque los agentes necesitan el board de trabajo
3. Odysseus  ← tercero, independiente de los otros dos
```

### Patrón de despliegue

Cada servicio Docker sigue esta estructura:
```
repos/<proyecto>/           ← código clonado de GitHub (intocable)
  └── Dockerfile            ← cómo construir la imagen

stacks/<proyecto>/          ← config de PRODUCCIÓN de esta instancia
  └── docker-compose.yml    ← puertos, IPs, volumes, limits de memoria
  └── .env                  ← secrets de producción (chmod 600)

data/core/<proyecto>/       ← datos persistentes (si usa bind mounts)
```

El compose de producción usa `build: ${HOME}/ai-lab/repos/<proyecto>`
para construir la imagen desde el código del repo.

## Orden de fases

```
Fase 0: Verificar base         ← confirmar que bootstrap completó bien
Fase 1: Secrets                 ← sin esto nada arranca
Fase 2: Autenticaciones         ← logins interactivos (requiere humano)
Fase 3: Servicios core          ← Hermes, Dagu, MoolMesh
Fase 4: Stack de agentes        ← Paperclip, Odysseus, Ollama, Mem0
Fase 5: Observabilidad          ← Uptime Kuma, Glance, guards
Fase 6: Colaboración            ← Outline, file sharing
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
cp ~/ai-lab/repos/ai-lab-bootstrap/templates/hermes.env.example ~/.hermes/.env
chmod 600 ~/.hermes/.env
# EDITAR: completar TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, API keys
```

**Keys requeridas mínimas:**
- `TELEGRAM_BOT_TOKEN` — crear bot con @BotFather
- `TELEGRAM_ALLOWED_USERS` — chat_id numérico (obtener de @userinfobot)
- Al menos una API key de LLM (OPENCODE_GO_API_KEY o equivalente)

### 1.2 Agents env

```bash
cp ~/ai-lab/repos/ai-lab-bootstrap/templates/agents.env.example ~/.env_agents
chmod 600 ~/.env_agents
# EDITAR: completar ANTHROPIC_API_KEY y/o OPENAI_API_KEY
```

### 1.3 Scripts operativos (backup, notificaciones)

```bash
cp ~/ai-lab/repos/ai-lab-bootstrap/templates/agents.env.example ~/ai-lab/scripts/.env 2>/dev/null
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
cp ~/ai-lab/repos/ai-lab-bootstrap/templates/paperclip.env.example ~/ai-lab/repos/paperclip/.env.paperclip
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

### 2.2 GitHub CLI + Repo de instancia

```bash
gh auth login
# Verificar:
gh auth status

# Publicar el repo de instancia (creado por setup-instance.sh):
HOSTNAME=$(hostname -s)
cd ~/ai-lab/repos/${HOSTNAME}-lab
gh repo create <tu-usuario>/${HOSTNAME}-lab --private --source=. --push
```

El repo `<hostname>-lab` es privado y contiene la configuración,
changelog y decisiones específicas de esta instancia. Fue creado
automáticamente por `setup-instance.sh` con estructura base.

### 2.3 Claude Code

```bash
claude
# Seguir el flujo de login en el navegador
# Verificar:
claude --version
```

### 2.4 NotebookLM (nlm) — login headless via CDP

`nlm login` necesita un navegador con sesión de Google, pero en un servidor
headless no hay GUI. La solución: lanzar Chromium headless con remote debugging,
hacer el login desde tu Mac vía túnel SSH, y luego extraer las cookies.

> **Nota:** `nlm login --force` (el método integrado) no funciona con el
> Chromium de snap en Ubuntu Server porque falla la inicialización de la
> plataforma gráfica (Aura), incluso con Xvfb. Por eso se lanza Chromium
> manualmente con los flags correctos.

**Paso 1 — Lanzar Chromium headless en el servidor:**

```bash
# Necesita user-agent real; sin él Google bloquea el login
# con "no se pudo iniciar sesión, pruebe con otro navegador"
DISPLAY=:99 chromium \
  --headless=new \
  --no-sandbox \
  --disable-gpu \
  --remote-debugging-port=9222 \
  --remote-debugging-address=127.0.0.1 \
  --disable-blink-features=AutomationControlled \
  --user-agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36" \
  "https://accounts.google.com" &

# Verificar que el puerto está escuchando:
ss -tlnp | grep 9222
```

**Paso 2 — Túnel SSH desde tu Mac:**

```bash
ssh -L 9222:localhost:9222 <usuario>@<IP-servidor>
```

**Paso 3 — Login desde Chrome de tu Mac:**

1. Abrir `chrome://inspect`
2. Click en **Configure…** → agregar `localhost:9222`
3. Aparece un tab "Inicia sesión: Cuentas de Google" → click en **inspect**
4. En la ventana de DevTools se ve la página de Google renderizada
5. Completar el login (email, contraseña, 2FA)
6. Después del login, abrir NotebookLM en el Chromium remoto. Desde el
   servidor: `curl -s -X PUT "http://127.0.0.1:9222/json/new?https://notebooklm.google.com"`
7. Verificar en `chrome://inspect` que aparece un tab "NotebookLM" y que cargó

**Paso 4 — Extraer cookies y autenticar nlm:**

```bash
# Extraer cookies del Chromium via CDP (requiere websockets)
python3 -m venv /tmp/ws-venv && /tmp/ws-venv/bin/pip install websockets -q

/tmp/ws-venv/bin/python3 << 'PYEOF'
import asyncio, json, websockets, http.client

async def export_cookies():
    conn = http.client.HTTPConnection("127.0.0.1", 9222)
    conn.request("GET", "/json")
    tabs = json.loads(conn.getresponse().read())
    ws_url = next(t["webSocketDebuggerUrl"] for t in tabs
                  if "notebooklm.google.com" in t.get("url", "")
                  and t.get("webSocketDebuggerUrl"))
    async with websockets.connect(ws_url) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Network.getCookies",
            "params": {"urls": ["https://notebooklm.google.com",
                                "https://google.com",
                                "https://accounts.google.com"]}}))
        resp = json.loads(await ws.recv())
        cookies = resp["result"]["cookies"]
        lines = ["# Netscape HTTP Cookie File"]
        for c in cookies:
            if "google" not in c["domain"]:
                continue
            d = c["domain"]
            lines.append(
                f"{'#HttpOnly_' if c.get('httpOnly') else ''}{d}\t"
                f"{'TRUE' if d.startswith('.') else 'FALSE'}\t"
                f"{c.get('path','/')}\t"
                f"{'TRUE' if c.get('secure') else 'FALSE'}\t"
                f"{int(c.get('expires',0))}\t{c['name']}\t{c['value']}")
        out = "/home/$USER/.nlm/cookies_fresh.txt".replace("$USER", __import__("os").environ["USER"])
        open(out, "w").write("\n".join(lines) + "\n")
        print(f"{len(lines)-1} cookies → {out}")

asyncio.run(export_cookies())
PYEOF

# Importar a nlm:
nlm login --manual --file ~/.nlm/cookies_fresh.txt --profile default --force

# Verificar:
nlm login --check
nlm list notebooks | head -5
```

**Paso 5 — Limpiar:**

```bash
pkill -f "chromium.*remote-debugging"
rm -rf /tmp/ws-venv
# Cerrar túnel SSH y chrome://inspect en el Mac
```

> **Frecuencia:** las cookies expiran ~cada 14 días. Repetir este proceso
> cuando `nlm login --check` falle o el gateway responda 503.

### 2.5 Antigravity CLI (opcional)

```bash
antigravity    # seguir flujo OAuth
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

Cada servicio Docker usa la convención `stacks/`: código en `repos/`,
compose de producción en `stacks/`, datos persistentes en `data/core/`.

### 4.1 Paperclip

```bash
# 1. Clonar el repo (si no existe)
cd ~/ai-lab/repos
git clone <url-del-repo-paperclip> paperclip

# 2. Crear compose de producción en stacks/
mkdir -p ~/ai-lab/stacks/paperclip
# Copiar template o crear docker-compose.yml con:
#   build.context: ${HOME}/ai-lab/repos/paperclip
#   ports, volumes, env según la instancia

# 3. Crear .env con secrets
cp ~/ai-lab/repos/ai-lab-bootstrap/templates/paperclip.env.example ~/ai-lab/stacks/paperclip/.env
chmod 600 ~/ai-lab/stacks/paperclip/.env
# EDITAR: POSTGRES_PASSWORD, BETTER_AUTH_SECRET, PAPERCLIP_PUBLIC_URL

# 4. Desplegar
cd ~/ai-lab/stacks/paperclip
docker compose up -d --build

# 5. Verificar
docker ps --filter name=paperclip
curl -s -o /dev/null -w "%{http_code}" http://<TAILSCALE_IP>:3100
```

### 4.2 Mem0 + Ollama

```bash
# Mem0 incluye Ollama como dependencia en su compose
cd ~/ai-lab/stacks/mem0
docker compose up -d

# Descargar modelo de embeddings:
docker exec ollama ollama pull nomic-embed-text

# Verificar:
curl -s http://localhost:8765/health
curl -s http://localhost:11434/api/tags | head -1
```

### 4.3 Odysseus

```bash
# 1. Clonar el repo (si no existe)
cd ~/ai-lab/repos
git clone <url-del-repo-odysseus> odysseus

# 2. Crear compose de producción en stacks/
mkdir -p ~/ai-lab/stacks/odysseus
# docker-compose.yml con:
#   build: ${HOME}/ai-lab/repos/odysseus
#   ports, env, chromadb según la instancia

# 3. Crear .env con secrets
# EDITAR: ODYSSEUS_ADMIN_USER, ODYSSEUS_ADMIN_PASSWORD, API keys

# 4. Desplegar
cd ~/ai-lab/stacks/odysseus
docker compose up -d --build

# 5. Verificar
curl -s -o /dev/null -w "%{http_code}" http://<TAILSCALE_IP>:7000
```

**Verificación de fase:**
```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | sort
```

---

## Fase 5 — Observabilidad

### 5.1 Desplegar stacks de infraestructura

`setup-instance.sh` genera los compose en `stacks/` desde templates.
Solo falta levantar los containers:

```bash
# Levantar infraestructura
for stack in portainer searxng uptime-kuma; do
  cd ~/ai-lab/stacks/$stack && docker compose up -d
done

# Portainer: abrir https://<TAILSCALE_IP>:9443
# Crear usuario admin (dentro de los primeros 5 minutos)

# Uptime Kuma: abrir http://<TAILSCALE_IP>:3001
# Crear usuario admin, agregar monitores
```

**Monitores sugeridos en Uptime Kuma:**
| Servicio | Tipo | URL |
|----------|------|-----|
| Hermes | HTTP | `http://localhost:9119/health` |
| Paperclip | HTTP | `http://<container_name>:3100` |
| Mem0 | HTTP | `http://mem0:8765/health` |
| Ollama | HTTP | `http://ollama:11434` |
| Outline | HTTP | `http://outline:3000` |

Para monitorear por nombre de container, Uptime Kuma debe estar en la
red Docker del servicio. Su compose ya declara las redes más comunes.

### 5.2 Backup

```bash
bash ~/ai-lab/ops/backup/setup-backup.sh
# Seguir el wizard: B2 creds → restic password → Uptime Kuma push URL
# Verificar:
bash ~/ai-lab/ops/backup/lab-backup.sh
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

## Fase 6 — Colaboración y file sharing (opcional)

### 6.1 Outline (wiki)

```bash
# Requiere stack en ~/ai-lab/stacks/outline/
# con .env configurado (SECRET_KEY, UTILS_SECRET, OIDC Google)
cd ~/ai-lab/stacks/outline
docker compose up -d

# Exponer via Tailscale:
sudo tailscale serve --bg --https=443 http://localhost:3010
```

### 6.2 File sharing entre instancias

Para sincronizar archivos entre labs (ej: knowledge base, configs compartidos),
hay dos opciones según el caso de uso:

**Opción A: Syncthing** — sincronización continua bidireccional.
Ideal para carpetas que cambian frecuentemente (knowledge, wikis de trabajo).

```bash
# Obtener Device ID:
syncthing --device-id

# Acceder a GUI via tunnel SSH (nunca exponer 8384):
# Desde Mac: ssh -L 8384:localhost:8384 <usuario>@<IP>
# Abrir http://localhost:8384

# Seguridad:
# - Desactivar: Global Discovery, Enable Relays, NAT Traversal
# - Solo peers vía Tailscale (IPs 100.x.x.x)
# - File Versioning: Staggered, 90 días

# Carpetas sugeridas para compartir:
#   ~/ai-lab/knowledge/shared/    ← knowledge base curada
#   ~/ai-lab/knowledge/companies/ ← por empresa (selectivo)
```

**Opción B: Tailscale file copy** — transferencia puntual.
Ideal para mover archivos específicos entre labs sin sincronización continua.

```bash
# Enviar archivo a otro lab:
tailscale file cp ~/ai-lab/knowledge/shared/doc.md <hostname>:

# Recibir archivos pendientes:
tailscale file get ~/ai-lab/inbox/
```

**Convención de carpetas compartidas:**
```
~/ai-lab/knowledge/
  shared/            ← material curado, disponible para todos los agentes
  companies/<id>/    ← material por empresa/proyecto
    wiki/            ← workspace de trabajo de agentes (rw)
    entradas/        ← inbox de material nuevo
    outputs/         ← resultados de agentes
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
cd ~/ai-lab/repos/ai-lab-bootstrap && ./setup-instance.sh --skip-backup --skip-services
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
