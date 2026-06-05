# AI Lab Bootstrap

Bootstrap script para levantar un **AI agent lab** completo en Ubuntu Server 24.04 desde cero.

Instala y configura el stack necesario para correr agentes de IA localmente, con inferencia delegada a APIs externas (sin GPU requerida).

---

## Stack que instala

| Herramienta | Propósito |
|---|---|
| Docker CE + Compose | Contenedores para agentes y servicios |
| Tailscale | VPN mesh — acceso seguro desde cualquier lugar |
| GitHub CLI | Autenticación y gestión de repos |
| Node.js 24 (via nvm) | Runtime para herramientas frontend |
| Gemini CLI | Cliente CLI para Google Gemini |
| Python venv + Hermes Agent | Gateway Telegram + dashboard de agentes |
| uv | Gestor Python rápido (Astral) |
| notebooklm-mcp-cli | Servidor MCP para Google NotebookLM |
| Chromium + Xvfb | Logins headless via CDP (sin pantalla física) |
| Opencode | IDE AI en terminal |
| Portainer | UI web para gestión Docker |
| Paperclip | Frontend AI con múltiples providers |
| SearXNG | Motor de búsqueda self-hosted — backend nativo de Hermes |
| Syncthing | Sincronización P2P de `~/ai-lab/knowledge/` con otros dispositivos |
| Red Docker `ai-lab` | Red aislada para todos los contenedores del lab |

---

## Requisitos

- Ubuntu Server 24.04 LTS (limpio)
- Usuario con acceso `sudo`
- Conexión a internet

---

## Uso

```bash
git clone https://github.com/almacreativa/ai-lab-bootstrap.git
cd ai-lab-bootstrap
bash bootstrap.sh
```

### Variables configurables

Se pueden exportar antes de correr el script o se usan los defaults:

```bash
export LAB_USER="miusuario"          # default: $USER
export LAB_DIR="/home/miusuario/ai-lab"  # default: ~/ai-lab
export INSTALL_PAPERCLIP=true        # default: true
export INSTALL_HERMES=true           # default: true
export INSTALL_NLM=true              # default: true

bash bootstrap.sh
```

---

## Estructura del repo

```
bootstrap.sh            ← script principal (sourcea los módulos)
modules/
├── 01-system.sh        ← apt, Docker CE, Tailscale, GitHub CLI, SSH hardening
├── 02-node.sh          ← NVM + Node 24 + Gemini CLI
├── 03-python.sh        ← uv, Hermes venv, notebooklm-mcp-cli
├── 04-ai-tools.sh      ← Chromium, Opencode, aliases .bashrc
├── 05-docker-stack.sh  ← red ai-lab, Portainer, repos, Hermes service
└── 06-post-install.sh  ← instrucciones de pasos manuales finales
templates/
├── hermes.env.example      ← secrets de Hermes Agent
├── agents.env.example      ← API keys para agentes
└── paperclip.env.example   ← config de Paperclip
configs/
├── hermes.service      ← template systemd ({{LAB_USER}} como variable)
└── hermes-start.sh     ← launcher de Hermes
```

---

## Pasos manuales post-bootstrap

El bootstrap instala el software pero hay pasos que requieren autenticación interactiva:

### 1. Secrets

Completar los archivos de configuración antes de iniciar los servicios.
Los templates están en `templates/`:

```bash
# Copiar y completar cada archivo
cp templates/hermes.env.example ~/.hermes/.env
cp templates/agents.env.example ~/.env_agents
cp templates/paperclip.env.example ~/ai-lab/repos/paperclip/.env.paperclip

# Permisos correctos
chmod 600 ~/.hermes/.env ~/.env_agents ~/ai-lab/repos/paperclip/.env.paperclip
```

Para `BETTER_AUTH_SECRET` en Paperclip:
```bash
openssl rand -hex 32
```

### 2. Tailscale

```bash
sudo tailscale up
```

### 3. GitHub CLI

```bash
gh auth login
```

### 4. Claude Code

```bash
npm install -g @anthropic-ai/claude-code
claude   # completar login
```

### 5. NotebookLM (`nlm`) — login headless via CDP

NotebookLM requiere un navegador real para el OAuth de Google.
El servidor no tiene pantalla física, así que usamos Xvfb + Chrome DevTools Protocol:

```bash
# En el servidor — terminal 1
Xvfb :99 -screen 0 1280x720x24 &
export DISPLAY=:99
nlm login --force
# → Abre Chromium y queda esperando (~300s)

# En el servidor — terminal 2
ss -tlnp | grep 9222   # verificar que Chromium expone puerto CDP
```

```bash
# Desde tu máquina local — tunnel SSH al puerto CDP
ssh -L 9222:localhost:9222 usuario@ip-del-servidor
```

```
# En Chrome de tu máquina local:
1. Abrir chrome://inspect
2. "Configure..." → agregar localhost:9222 → Done
3. Aparece un tab de Google Sign-in → clic en "inspect"
4. Completar login de Google en la ventana DevTools
```

```bash
# Verificar que funcionó
nlm notebook list
```

> **Seguridad:** las cookies de NotebookLM incluyen tokens de sesión Google con acceso amplio.
> Guardar con `chmod 600 ~/.notebooklm-mcp-cli/` y revocar la sesión desde
> [Google Account](https://myaccount.google.com/security) cuando no se use activamente.
> Las cookies expiran cada 2-4 semanas — repetir este proceso para renovarlas.

### 6. Gemini CLI

```bash
gemini   # sigue el flujo OAuth en el navegador
```

### 7. OpenCode

```bash
opencode   # seleccionar provider y autenticar
```

### 8. Iniciar servicios

```bash
# Hermes (después de completar ~/.hermes/.env)
sudo systemctl start hermes
journalctl -u hermes -f   # verificar logs

# Paperclip
cd ~/ai-lab/repos/paperclip
docker compose -f docker/docker-compose.yml \
  --env-file .env.paperclip \
  --project-name paperclip \
  up -d --build
```

### 9. Portainer

Abrir `https://<IP-del-servidor>:9443` y crear el usuario admin en el primer acceso.

---

## SearXNG — búsqueda web self-hosted

El bootstrap levanta SearXNG como contenedor Docker accesible solo desde `localhost:8080`. Hermes lo detecta automáticamente cuando `SEARXNG_URL` está en `~/.env_agents`.

```bash
# Activar en Hermes — agregar a ~/.env_agents:
SEARXNG_URL=http://localhost:8080

# Verificar que responde:
curl http://localhost:8080/search?q=test&format=json | head -c 100
```

Sin API key, sin telemetría, sin costos. Consulta más de 70 motores de búsqueda en paralelo.

---

## Syncthing — carpeta knowledge/ sincronizada

El bootstrap instala Syncthing y crea `~/ai-lab/knowledge/` con tres subcarpetas (`projects/`, `research/`, `daily/`). Esta carpeta es donde Hermes guarda notas, investigaciones y contexto de proyectos — sincronizada automáticamente con otros dispositivos via P2P.

### Configuración post-bootstrap (manual)

**En el servidor** — acceder a la GUI via tunnel SSH:
```bash
# Desde tu máquina local:
ssh -L 8384:localhost:8384 usuario@ip-del-servidor
# Abrir: http://localhost:8384
```

**Settings → Connections:**
- Global Discovery → OFF
- Enable Relays → OFF
- NAT Traversal → OFF
- Listen Addresses → dejar en `default` (NO fijar a una IP específica)

> Con Tailscale activo el tráfico viaja dentro del túnel WireGuard. Fijar la dirección a una IP Tailscale IPv4 específica hace que Syncthing rechace conexiones por la dirección IPv6 que Tailscale también asigna al dispositivo.

**Agregar carpeta:**
- Folder Path: `~/ai-lab/knowledge`
- Folder ID: `ai-lab-knowledge` (debe ser igual en todos los dispositivos)
- File Versioning: Staggered, 90 días

### Conectar dispositivos adicionales

```bash
# Ver Device ID del servidor:
syncthing --device-id

# Estado del servicio:
systemctl status syncthing@$USER
```

**En Mac (Homebrew):**
```bash
brew install syncthing
brew services start syncthing
# Abrir: http://localhost:8384
# Agregar el servidor como dispositivo con su Device ID
```

---

## Template docker-compose para agentes

```yaml
services:
  mi-agente:
    build: .
    container_name: poc_mi-agente
    env_file:
      - /home/$LAB_USER/.env_agents
    volumes:
      - /home/$LAB_USER/ai-lab/workspace:/app/workspace
    networks:
      - ai-lab
    restart: unless-stopped

networks:
  ai-lab:
    external: true
```

---

## Decisiones de diseño

| Decisión | Motivo |
|---|---|
| Sin modelos locales (Ollama) | Sin GPU requerida — inferencia delegada a APIs externas |
| Hermes bare metal (no Docker) | Acceso nativo a herramientas del host (claude, opencode, gh) |
| Docker para agentes PoC | Aislamiento — un agente que falle no rompe el host |
| Red `ai-lab` dedicada | Los contenedores se ven entre sí, aislados del exterior |
| `nvm` para Node.js | Flexibilidad de versiones sin conflictos de sistema |
| `uv` para Python tools globales | Más rápido que pip, aislamiento automático |
| `~/.env_agents` centralizado | Una sola fuente de verdad para todas las API keys |
| Xvfb + CDP para OAuth headless | Permite autenticar servicios que requieren browser sin GUI física |
