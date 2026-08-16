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
| Antigravity CLI | Cliente CLI para Google Antigravity (ex Gemini CLI) |
| Python venv + Hermes Agent | Gateway Telegram + dashboard de agentes |
| uv | Gestor Python rápido (Astral) |
| notebooklm-mcp-cli | Servidor MCP para Google NotebookLM |
| Chromium + Xvfb | Logins headless via CDP (sin pantalla física) |
| Claude Code | Agente de desarrollo AI en terminal |
| Opencode | IDE AI en terminal |
| Engram | Memoria persistente cross-session para agentes AI (MCP stdio) |
| MoolMesh | Observatorio de sesiones de agentes AI (dashboard + MCP) |
| Dagu v2.8.2 | Orquestador de tareas YAML — reemplaza crontab (UI, retry, logs, MCP) |
| Portainer | UI web para gestión Docker |
| Uptime Kuma | Monitoreo de servicios con alertas push |
| Glance | Centro de Comando — dashboard de estado del lab |
| Paperclip | Frontend AI con múltiples providers |
| SearXNG | Motor de búsqueda self-hosted — backend nativo de Hermes |
| Syncthing | Sincronización P2P de `~/ai-lab/knowledge/` con otros dispositivos |
| restic | Backup incremental encriptado a Backblaze B2 |
| age | Cifrado de secrets para transferencia segura entre labs |
| etckeeper | Control de versiones automático de `/etc/` |
| Red Docker `ai-lab` | Red aislada para todos los contenedores del lab |

---

## Requisitos

- Ubuntu Server 24.04 LTS (limpio) — o macOS (ver sección abajo)
- Usuario con acceso `sudo`
- Conexión a internet

---

## Uso

```bash
mkdir -p ~/ai-lab/repos
cd ~/ai-lab/repos
git clone https://github.com/almacreativa/ai-lab-bootstrap.git
cd ai-lab-bootstrap
bash bootstrap.sh

# Después del bootstrap: configurar la instancia
# Opción A: con bundle de secrets encriptado (ver ops/runbooks/secrets-management.md)
./setup-instance.sh --secrets ~/secrets.age

# Opción B: interactivo
./setup-instance.sh
```

`setup-instance.sh` configura secrets, inicializa backup (restic + B2), copia el framework operativo (`ops/`), genera `core-manifest.yaml`, instala DAGs operativos, genera `~/CLAUDE.md` e inicia servicios.

### Variables configurables

Se pueden exportar antes de correr el script o se usan los defaults:

```bash
export LAB_USER="miusuario"          # default: $USER
export LAB_DIR="/home/miusuario/ai-lab"  # default: ~/ai-lab
export INSTALL_PAPERCLIP=true        # default: true
export INSTALL_HERMES=true           # default: true
export INSTALL_NLM=true              # default: true
export LAB_BIND_ADDR="127.0.0.1"     # default: 127.0.0.1 (ver "Acceso a los paneles" abajo)

bash bootstrap.sh
```

#### Acceso a los paneles de administración (`LAB_BIND_ADDR`)

Por defecto los paneles de administración (Portainer `:9443`, Uptime Kuma `:3001`, Glance `:9000`, dashboard de Hermes `:9119`, Dagu `:8480`) bindean a **`127.0.0.1`** — es decir, **no quedan expuestos** a la LAN ni a internet. Esto es *secure-by-default*: **UFW no protege a los contenedores Docker** (bypass de la cadena FORWARD, ver `docs/SECURITY_GUIDE.md` §8), así que el bind es la única protección real de estos paneles.

Para acceder a ellos hay dos caminos:

```bash
# (a) Túnel SSH desde tu máquina (no expone nada en la red):
ssh -L 9443:127.0.0.1:9443 -L 3001:127.0.0.1:3001 usuario@host
#     luego abrir https://localhost:9443 en tu navegador

# (b) Exponerlos SOLO en tu tailnet (Tailscale) — setear la IP tailscale del host
#     ANTES del bootstrap:
export LAB_BIND_ADDR="100.x.y.z"   # tu IP tailscale (tailscale ip -4)
bash bootstrap.sh
```

> **Nunca** usar `LAB_BIND_ADDR=0.0.0.0` en redes no confiables: expone todos los paneles (varios sin autenticación, como el dashboard de Hermes que corre `--insecure`) a cualquiera que alcance el host.
>
> **Monitores en contenedor (caveat):** con el default `127.0.0.1`, monitores que corren *dentro* de un contenedor (Uptime Kuma → Hermes, Glance → Dagu) no alcanzan los servicios del host (el `localhost` del contenedor ≠ el del host). Si se quiere ese monitoreo funcionando, exponer con `LAB_BIND_ADDR=<ip-tailscale>` en lugar de loopback.

### Instalación selectiva y reanudable

> Solo para Linux (`bootstrap.sh`). El instalador de macOS (`bootstrap-macos.sh`) aún no tiene el mecanismo modular.

Sin flags, `bootstrap.sh` instala el set completo (comportamiento por defecto). Para instalaciones a medida:

```bash
bash bootstrap.sh --only hermes,engram,searxng   # solo esas unidades (+ sus deps)
bash bootstrap.sh --layer operator,explorer      # instala esas capas (+ base y deps)
bash bootstrap.sh --skip glance,portainer        # todo menos esas
bash bootstrap.sh --interactive                  # pregunta herramienta por herramienta (agrupado por capa)
bash bootstrap.sh --until 03                      # corta tras la etapa 03 (reanudable)
bash bootstrap.sh --resume                        # continúa lo que quedó pendiente
bash bootstrap.sh --list                          # muestra qué se instalaría, sin instalar
```

Las herramientas instalables se declaran en `lib/registry.sh` (única fuente de verdad). Las etapas (01–06) mapean a los módulos (`modules/0X-*.sh`); `--until NN` corta tras la etapa `NN`. El progreso se guarda en `~/.ai-lab/state/bootstrap.tsv`, lo que permite cortar y reanudar sin repetir. Los flags `INSTALL_HERMES/PAPERCLIP/NLM` siguen funcionando (retrocompatibles).

**Capas (`--layer`).** Agrupan las unidades por rol para elegir de a bloques:

- **`builder`** — la base (Docker, Node, uv, Claude Code, OpenCode). Docker/Node/uv son obligatorias: van siempre, en cualquier instalación.
- **`operator`** — el plano de control: Hermes, Engram, SearXNG.
- **`explorer`** — Odysseus + MCPs de contexto (Playwright, tmux-bridge).
- **`addons`** — automatización y observabilidad: Dagu, MoolMesh, Uptime Kuma, Glance, Portainer, Paperclip, etc.

`--layer` y `--only` se combinan por unión (`--skip` resta después). Una capa arrastra solo sus unidades activas por defecto; las que están `off` (ej. Odysseus) se piden explícitamente con `--only`. No confundir "capa" con "perfil" (forja/vitrina): son dimensiones distintas.

**Recetas por escenario.** Casos comunes de las distintas formas de instalar:

```bash
# Ver qué se instalaría, sin tocar nada (ideal antes de cualquier corrida):
bash bootstrap.sh --list

# Lab completo (comportamiento por defecto):
bash bootstrap.sh

# Solo el operador (Hermes + memoria + búsqueda), con su base mínima:
bash bootstrap.sh --layer operator

# Solo herramientas de código (base + Claude Code + OpenCode):
bash bootstrap.sh --layer builder

# Lab completo pero sin la observabilidad/UI:
bash bootstrap.sh --skip portainer,uptime-kuma,glance

# Equipo lento o instalación en varias tandas — cortar tras la etapa 03 y seguir después:
bash bootstrap.sh --until 03      # instala etapas 01–03 y para
bash bootstrap.sh --resume        # retoma desde donde quedó (04–06)

# Retomar tras un corte inesperado (Ctrl-C, corte de luz):
bash bootstrap.sh --resume

# Elegir herramienta por herramienta (agrupado por capa):
bash bootstrap.sh --interactive

# Agregar Odysseus (viene apagado por defecto), junto a lo que quieras:
bash bootstrap.sh --layer operator --only odysseus

# Base mínima endurecida (Docker + Tailscale + SSH hardening), sin extras del lab
# — cimiento para un host externo (p.ej. un server Dokploy):
bash bootstrap.sh --until 01 --skip syncthing,restic,etckeeper
```

> En un host de este tipo **no** correr `setup-instance.sh` (es configuración del lab de IA) ni instalar Portainer (choca con Dokploy; ya queda fuera con `--until 01`).

---

## macOS

Hay una variante equivalente para correr el lab en macOS (Sonoma/Sequoia), pensada para desarrollo/testing — no como servidor productivo 24/7 salvo que el Mac quede siempre encendido.

```bash
mkdir -p ~/ai-lab/repos
cd ~/ai-lab/repos
git clone https://github.com/almacreativa/ai-lab-bootstrap.git
cd ai-lab-bootstrap
bash bootstrap-macos.sh
```

### Diferencias clave vs. Linux

| Aspecto | Linux (`bootstrap.sh`) | macOS (`bootstrap-macos.sh`) |
|---|---|---|
| Gestor de paquetes | apt | Homebrew |
| Docker | Docker CE (daemon nativo) | Docker Desktop (requiere abrirse 1 vez) |
| Servicio de Hermes | systemd (`hermes.service`) | launchd LaunchAgent (`com.almacreativa.hermes.plist`) |
| SSH hardening | sshd_config + `systemctl reload ssh` | sshd_config + `systemsetup -setremotelogin` + `launchctl kickstart` |
| Login de nlm (NotebookLM) | Headless via Xvfb + túnel CDP (sin pantalla) | Navegador real, sin Xvfb ni túnel — más simple |
| Chromium | `snap install chromium` | `brew install --cask chromium` |
| Cron `@reboot` | Dispara siempre al boot | Solo dispara en reinicio real, no al despertar de sleep |
| Shell rc para aliases | `.bashrc` | `.zshrc` (o `.bash_profile` si usas bash) |

### Variables configurables (iguales en ambas variantes)

```bash
export LAB_USER="miusuario"
export LAB_DIR="$HOME/ai-lab"
export INSTALL_PAPERCLIP=true
export INSTALL_HERMES=true
export INSTALL_NLM=true

bash bootstrap-macos.sh
```

---

## Windows 10/11

Variante **100% nativa** para **Windows 10 LTSC (22H2+)** — soporte principal — y **Windows 11 (22H2+)**. **Sin WSL2, sin Docker**: todo corre bare metal gestionado por **Servy** (service manager) e instalado con **Scoop** (package manager). Paperclip usa PostgreSQL embebido (zero-config) y SearXNG se consume remoto vía Tailscale.

> **Requisitos:** 8 GB+ RAM (16 GB recomendado), 20 GB libres en disco, cuenta Administrador.
> No requiere reinicio: todo se instala en una sola ejecución.

```powershell
# PowerShell como Administrador
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
mkdir -Force "$env:USERPROFILE\ai-lab\repos" | Out-Null
cd "$env:USERPROFILE\ai-lab\repos"
git clone https://github.com/almacreativa/ai-lab-bootstrap.git
cd ai-lab-bootstrap
.\bootstrap-windows.ps1
```

El script detecta el sistema (Windows 10/11, edición LTSC, RAM/CPU), muestra un resumen de la configuración y, tras confirmar, instala prerrequisitos (Scoop, uv, Node LTS, Python 3.12, Servy, Tailscale), servicios nativos, agentes AI y la plataforma. Si Git no está instalado, Scoop lo provee.

### Arquitectura

| Aspecto | Decisión |
|---|---|
| Package manager | **Scoop** (no WinGet — los App Execution Aliases no funcionan en LTSC sin Microsoft Store) |
| Service manager | **Servy** (`aelassas/servy`) — gestiona servicios de larga vida con auto-start |
| Docker | **Ninguno** — todo nativo Windows |
| Paperclip | **PostgreSQL embebido** (zero-config), no containers |
| Odysseus | Fork nativo para Windows (`amish-github/odysseus`) |
| SearXNG | **Remoto** vía Tailscale (sin soporte nativo Windows — configurar `SEARXNG_URL`) |
| Terminal multiplexer | **psmux** (equivalente nativo a tmux, en Rust) |
| Suspend | Si Windows entra en suspensión, los servicios Servy se detienen (no es servidor 24/7) |

### Variables configurables

```powershell
$env:INSTALL_HERMES = "true"            # Hermes Agent (default: true)
$env:INSTALL_PAPERCLIP = "true"         # Paperclip (default: true)
$env:INSTALL_ODYSSEUS = "true"          # Odysseus (default: true)
$env:INSTALL_DAGU = "true"              # Dagu scheduler (default: true)
$env:INSTALL_UPTIME_KUMA = "true"       # Uptime Kuma (default: true)
$env:INSTALL_GLANCE = "true"            # Glance dashboard (default: true)
$env:INSTALL_NLM = "true"               # NotebookLM MCP (default: true)
$env:LAB_INSTALL_SSH_SERVER = "false"   # OpenSSH Server (default: false)
.\bootstrap-windows.ps1
```

**Guía detallada:** [`docs/WINDOWS-INSTALL.md`](docs/WINDOWS-INSTALL.md) — prerrequisitos, flujo paso a paso, qué hace cada módulo, pasos post-bootstrap, troubleshooting y mantenimiento.

---

## Estructura del repo

```
bootstrap.sh            ← script principal Linux (sourcea los módulos)
bootstrap-macos.sh      ← script principal macOS (sourcea modules/macos/)
bootstrap-windows.ps1   ← script principal Windows host (sourcea modules/windows-host/)
modules/
├── 01-system.sh        ← apt, Docker CE, Tailscale, GitHub CLI, SSH hardening,
│                          restic, age, etckeeper, sqlite3
├── 02-node.sh          ← NVM + Node 24 + Antigravity CLI
├── 03-python.sh        ← uv, Hermes venv, notebooklm-mcp-cli
├── 04-ai-tools.sh      ← Claude Code, Opencode, Engram, MoolMesh, aliases
├── 05-docker-stack.sh  ← red ai-lab, Portainer, Uptime Kuma, Glance, Dagu,
│                          repos, Hermes service, ops/ framework, data/ dirs
├── 06-post-install.sh  ← instrucciones de pasos manuales finales
├── macos/              ← equivalentes 01-06 para macOS (Homebrew, launchd, etc.)
└── windows-host/           ← variante nativa Windows (Scoop + Servy, sin WSL2/Docker)
    ├── 01-host-prereqs.ps1     ← long paths, Scoop, uv, Node LTS, Python 3.12, Servy,
    │                              Tailscale, VC++ Redistributable, Defender, power plan
    ├── 02-native-services.ps1  ← Dagu, Uptime Kuma, Glance (nativos, vía Servy)
    ├── 03-ai-agents.ps1        ← Claude Code, OpenCode, Engram, Hermes, MoolMesh,
    │                              Playwright MCP, NotebookLM MCP
    ├── 04-platform.ps1         ← Paperclip (PG embebido), Odysseus (fork nativo)
    ├── 05-connectivity.ps1     ← firewall Tailscale, templates .hermes/.env y .env_agents
    └── 06-post-install.ps1     ← instrucciones de pasos manuales finales
templates/
├── hermes.env.example      ← secrets de Hermes Agent
├── agents.env.example      ← API keys para agentes
└── paperclip.env.example   ← config de Paperclip
configs/
├── hermes.service              ← template systemd Linux ({{LAB_USER}} como variable)
├── hermes-start.sh             ← launcher de Hermes (Linux)
├── com.almacreativa.hermes.plist ← template launchd macOS ({{HOME}}, {{NODE_VERSION}})
├── hermes-start-macos.sh       ← launcher de Hermes (macOS)
├── hermes-config.yaml.example  ← config completo de Hermes con comentarios
├── hermes-mcp-servers.yaml.example ← servidores MCP (Paperclip, Dagu, NLM)
├── dagu.service                ← template systemd user para Dagu
├── dagu-config.yaml.example    ← config del servidor Dagu
├── dagu-base.yaml.example      ← config base heredada por todos los DAGs
├── dagu-dags/                  ← DAGs base + templates por empresa
└── crontab.example         ← referencia legacy (migrado a Dagu)
scripts/
├── onboard-company.sh      ← alta de empresa completa (DB + dirs + crons)
├── deploy-agent-prompts.sh ← deploy de promptTemplate (S1+S2+S3 → DB)
├── create-routine.sh       ← crear routines Paperclip con trigger y revision
├── paperclip-poll-done.sh  ← polling de issues completados (state tracking)
├── paperclip-notify-done.sh← formatear polling para notificaciones
├── paperclip-boot-cleanup.sh ← limpieza post-restart de Paperclip
├── paperclip-watchdog.sh   ← monitor de salud de contenedores
├── paperclip-mcp-company.sh.template ← template para instancias MCP por empresa
├── weekly-ingest.sh        ← pipeline semanal de destilación de sesiones
├── nlm-sync.sh             ← sync de knowledge a NotebookLM
├── security-apply-sudo.sh  ← baseline de seguridad UFW
├── telegram-notify.sh      ← envío de notificaciones via Telegram
├── cleanup-tmp.sh          ← limpieza de archivos temporales
├── dagu-mcp.sh             ← bridge stdio→HTTP para Dagu MCP (JWT + mcp-proxy)
└── lab-daily-briefing.sh   ← briefing diario de infra (no-agent → agent si alertas)
skills/                     ← skills de knowledge management (las demás skills
├── wiki-ingest/            ←   son personalización natural de cada instancia)
└── hermes-history-ingest/  ← ingest de historial de Hermes
ops/                        ← framework operativo (copiado a ~/ai-lab/ops/ por módulo 05)
├── guards/                 ← scripts de auditoría automática
│   ├── core-guard.sh       ← audita core contra core-manifest.yaml
│   ├── profile-guard.sh    ← audita perfil contra profile.yaml
│   ├── bootstrap-guard.sh  ← audita cobertura del bootstrap
│   ├── manifest-guard.sh   ← audita que el repo privado del operador este
│   │                          clasificado en perfil-manifest.yaml (modelo lab-seed)
│   └── guard-lib.sh        ← funciones compartidas (JSON output, Telegram)
├── backup/                 ← scripts de backup y disaster recovery
│   ├── lab-backup.sh       ← backup incremental restic (genérico)
│   ├── setup-backup.sh     ← wizard de configuración de backup
│   └── dr-restore.sh       ← procedimiento de disaster recovery
├── manifests/
│   └── generate-core-manifest.sh ← escanea el sistema y genera core-manifest.yaml
└── runbooks/               ← lecciones aprendidas codificadas
docs/                       ← documentación genérica del lab (ver tabla abajo)
knowledge-pipeline/         ← scripts Python del pipeline de destilación
stacks/                     ← docker-compose de servicios (Mem0, Glance, Odysseus, etc.)
```

### Directorios creados en el host por el bootstrap

```
~/ai-lab/
├── data/                   ← datos persistentes (respaldados por restic)
│   ├── core/               ← datos del core (nunca se borran por perfiles)
│   └── profiles/           ← datos por perfil (aislados entre sí)
├── ops/                    ← framework operativo (copiado desde el bootstrap)
│   ├── guards/
│   ├── backup/
│   ├── runbooks/
│   └── manifests/
├── logs/guard/             ← reportes JSON de auditorías semanales
├── scripts/                ← scripts operativos del lab
├── repos/                  ← repositorios clonados (ai-lab-bootstrap, paperclip, hermes-agent)
├── stacks/                 ← docker-compose de servicios (glance, etc.)
├── knowledge/              ← base de conocimiento (sincronizada con Syncthing)
└── workspace/              ← workspaces de agentes
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
claude   # completar login (instalado por el bootstrap)
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

### 6. Antigravity CLI

```bash
antigravity   # sigue el flujo OAuth en el navegador
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

## Knowledge Management & memoria de agentes (nuevo)

El lab incluye un sistema completo para que los agentes **acumulen conocimiento
entre sesiones** — multi-empresa, incremental y con costo $0 de LLM:

| Componente | Qué hace | Dónde |
|---|---|---|
| Pipeline de destilación | sesiones crudas → knowledge estructurado por empresa (cron semanal, incremental) | `scripts/weekly-ingest.sh` + `knowledge-pipeline/` + `skills/` |
| Mem0 self-hosted | memoria episódica transversal (API REST, namespace por empresa, embeddings locales) | `stacks/mem0/` |
| Outline | (RETIRADO 2026-06-28 — compose se conserva como referencia) | `stacks/outline/` |
| Espejos de deliverables | workspaces y dirs compartidos → `knowledge/<empresa>/outputs/` | `scripts/sync-company.sh` |
| Baseline de seguridad | UFW para bare metal + regla de oro: contenedores se protegen con BINDS, no UFW | `scripts/security-apply-sudo.sh` |

**Documentación:**
- [`docs/KNOWLEDGE_MANAGEMENT.md`](docs/KNOWLEDGE_MANAGEMENT.md) — arquitectura y el porqué de cada decisión
- [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) — flujos de operación: instalación, semana típica, onboarding de empresa, mantenimiento
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — síntoma → causa → fix (20+ problemas reales resueltos)
- [`docs/LESSONS.md`](docs/LESSONS.md) — 16 lecciones de producción

> Los IDs de empresa, rutas y hosts vienen con placeholders `changeme-*` /
> `<TAILSCALE_IP>` — configurarlos antes de usar. Ningún archivo de este repo
> contiene secrets: cada stack trae su `.env.example`.

## Documentación completa

### Operación y arquitectura

| Documento | Contenido |
|---|---|
| `docs/GUIA_OPERADOR.md` | Guía del operador — rutina diaria, puertas de entrada, flujos de trabajo |
| `docs/KNOWLEDGE_MANAGEMENT.md` | Arquitectura KM — pipeline, Mem0, decisiones |
| `docs/KNOWLEDGE_HUB.md` | Contrato genérico de carpetas del hub de conocimiento |
| `docs/NOTEBOOKLM_MCP.md` | Conexión NotebookLM (CLI, MCP, gateway, workflow research) |
| `docs/PAPERCLIP_MCP.md` | MCP genérico de Paperclip por empresa |
| `docs/KM_PLAN.md` | Plan de ejecución KM v3.2 — las 8 fases implementadas |
| `docs/KM_RUNBOOK.md` | Runbook de operaciones — mantenimiento, recuperación, troubleshooting |
| `docs/SERVICIOS.md` | Inventario de servicios — puertos, contenedores, estado |
| `docs/OBSERVABILIDAD.md` | Contrato de status JSON (ops-local/status/) — quién escribe cada archivo y su frescura esperada |
| `docs/ORQUESTACION_AGENTES.md` | Orquestación de agentes — tmux-gateway + tmux-bridge-mcp + clawhip, patrón de delegación (Horizonte 1) |
| `docs/WORKFLOWS.md` | Flujos de operación — instalación, semana típica, onboarding |
| `docs/DECISIONES_KM.md` | ADRs — decisiones de arquitectura con contexto y razones |
| `docs/ADR-ENGRAM.md` | ADR específico de Engram — memoria compartida entre agentes |

### Hermes y Paperclip

| Documento | Contenido |
|---|---|
| `docs/HERMES_CONFIG_GUIDE.md` | Configuración de providers, secciones del config.yaml, comandos |
| `docs/HERMES_RUNBOOK.md` | Operación de Hermes — deploy, monitoreo, recuperación |
| `docs/HERMES_BARE_METAL_MIGRATION.md` | Guía de migración a bare metal (no Docker) |
| `docs/HERMES_DEPLOY_HANDOFF.md` | Handoff de deploy — pasos para puesta en producción |
| `docs/PAPERCLIP_GUIDE.md` | Infraestructura Docker, providers, agentes, troubleshooting |
| `docs/DB_OPERATIONS.md` | Operaciones de DB — scripts, recetas, pitfalls de routines |
| `docs/DIRECTRICES_AUTOMATIZACIONES.md` | 8 reglas para crons/skills/integraciones |

### Onboarding y seguridad

| Documento | Contenido |
|---|---|
| `docs/ONBOARDING_EMPRESA.md` | Alta de empresa/cliente — script + pasos manuales |
| `docs/ONBOARDING_AGENTE.md` | Alta/modificación de agentes — promptTemplate, modelos |
| `docs/SECURITY_GUIDE.md` | Baseline de seguridad — UFW, secrets, contenedores |
| `docs/UPGRADE_SECURITY.md` | Actualización al modelo de seguridad multicapa (Tailscale → UFW per-port → fail2ban) para labs existentes |
| `docs/SECRETS_INVENTORY.md` | Inventario de secrets — ubicación, rotación, permisos |

### Referencia

| Documento | Contenido |
|---|---|
| `docs/POST-BOOTSTRAP.md` | Pasos post-instalación: auth de servicios, NLM headless via CDP, MCPs |
| `docs/PLAYWRIGHT_MCP.md` | Visual testing headless para agentes (Chromium + MCP) |
| `docs/DESTILACION_CONOCIMIENTO.md` | Patrón: doc masiva → motor RAG → batería de preguntas → knowledge curado |
| `docs/SYNC_ENTRADAS_OUTPUTS.md` | El sistema entradas/outputs por empresa (sync-company) |
| `docs/TROUBLESHOOTING.md` | Síntoma → causa → fix (20+ problemas reales resueltos) |
| `docs/LESSONS.md` | 16 lecciones de producción |
| `configs/hermes-config.yaml.example` | Template completo del config.yaml de Hermes |

---

## Hermes ↔ Paperclip MCP

Hermes controla Paperclip via MCP (Model Context Protocol) con una instancia stdio
por empresa. Cada instancia expone 21 herramientas aisladas a su empresa.

```bash
# Template para crear una instancia MCP por empresa
# Ver: scripts/paperclip-mcp-company.sh.template
cp scripts/paperclip-mcp-company.sh.template scripts/mcp-company-a.sh
# Editar placeholders: {{PAPERCLIP_HOST}}, {{COMPANY_ID}}
chmod +x scripts/mcp-company-a.sh
```

Configurar en `~/.hermes/mcp-servers.yaml`:
```yaml
paperclip_company_a:
  command: ~/ai-lab/scripts/mcp-company-a.sh
  transport: stdio
```

### Routines (trabajo recurrente)

Paperclip tiene un scheduler interno que crea issues automáticamente por cron.
Crear routines con el script (no por INSERT directo — requiere `next_run_at`):

```bash
bash scripts/create-routine.sh PREFIJO AGENTE "Título" "0 9 * * 1"
# Ejemplo: crear informe semanal del CEO, lunes 09:00
```

### Polling de issues completados

```bash
# Ejecutar manualmente o via cron de Hermes
bash scripts/paperclip-poll-done.sh          # JSON con issues recién completados
bash scripts/paperclip-notify-done.sh        # formato legible para Telegram
```

---

## Dagu — orquestador de tareas (reemplaza crontab)

Dagu v2.8.2 gestiona todas las tareas recurrentes del lab como DAGs declarativos en YAML.
Web UI con logs, historial, retry automático y notificaciones a Telegram.

### Tres capas de automatización

| Capa | Qué ejecuta | Gestión |
|------|-------------|---------|
| **Dagu** | Scripts bash recurrentes (sync, health, backup, ingest) | `~/.config/dagu/dags/*.yaml` + UI |
| **Hermes crons** | Tareas con LLM o scripts que necesitan contexto Hermes | `hermes cron list/add` |
| **systemd** | Procesos persistentes y boot (dagu, nlm-gateway, hermes) | `systemctl` |

### Crear un DAG nuevo

```bash
# 1. Crear YAML (usar templates de configs/dagu-dags/ como referencia)
vi ~/.config/dagu/dags/mi-tarea.yaml

# 2. Validar
dagu validate ~/.config/dagu/dags/mi-tarea.yaml

# 3. Probar
dagu start ~/.config/dagu/dags/mi-tarea.yaml

# 4. Verificar en UI: http://<TAILSCALE_IP>:8480
```

### Hermes ↔ Dagu MCP

Hermes se conecta a Dagu via MCP para tener visibilidad de la infraestructura:

```
Hermes → dagu-mcp.sh (JWT fresco) → mcp-proxy (stdio→HTTP) → Dagu /mcp
```

Tools disponibles: `mcp_dagu_read`, `mcp_dagu_execute`, `mcp_dagu_change`.
El `lab-daily-briefing.sh` corre diario como cron de Hermes (no-agent) y dispara
análisis inteligente si detecta anomalías.

---

## Decisiones de diseño

| Decisión | Motivo |
|---|---|
| Dagu en lugar de crontab | UI con logs/retry/dependencias, MCP nativo para Hermes, YAML declarativo |
| Sin modelos locales (Ollama) | Sin GPU requerida — inferencia delegada a APIs externas |
| Hermes bare metal (no Docker) | Acceso nativo a herramientas del host (claude, opencode, gh) |
| Docker para agentes PoC | Aislamiento — un agente que falle no rompe el host |
| Red `ai-lab` dedicada | Los contenedores se ven entre sí, aislados del exterior |
| `nvm` para Node.js | Flexibilidad de versiones sin conflictos de sistema |
| `uv` para Python tools globales | Más rápido que pip, aislamiento automático |
| `~/.env_agents` centralizado | Una sola fuente de verdad para todas las API keys |
| Xvfb + CDP para OAuth headless | Permite autenticar servicios que requieren browser sin GUI física |
