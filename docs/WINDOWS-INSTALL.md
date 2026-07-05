# Instalacion en Windows -- Guia completa

Guia paso a paso para instalar el AI Agent Lab **100% nativo** en Windows 10/11.
Sin WSL2, sin Docker. Todo corre bare metal con **Servy** como service manager.

---

## Requisitos previos

### Sistema operativo

- **Windows 10 LTSC** (22H2+) -- soporte principal
- **Windows 11** (22H2+) -- compatible

### Hardware

- Minimo **8 GB de RAM** (recomendado 16 GB+)
- **20 GB de espacio libre** en disco
- Conexion a internet

### Software y permisos

- Cuenta con permisos de **Administrador** (el script configura Defender, firewall, servicios)
- **Git** instalado (si no lo tenes, el script lo instala via Scoop)

### Politica de ejecucion de PowerShell

Windows bloquea la ejecucion de scripts por defecto. Habilitar antes de correr el bootstrap:

```powershell
# PowerShell como Administrador
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## Arquitectura

Todo corre nativo en Windows. No hay virtualizacion, no hay Docker.

```
+---------------------------------------------------------+
|  AGENTES AI (modulo 03)                                 |
|  Claude Code, OpenCode, Hermes, MoolMesh, Engram,       |
|  Playwright MCP, NotebookLM MCP                         |
+---------------------------------------------------------+
|  PLATAFORMA (modulo 04)                                 |
|  Paperclip (PG embebido), Odysseus                      |
+---------------------------------------------------------+
|  SERVICIOS NATIVOS (modulo 02)                          |
|  Dagu, Uptime Kuma, Glance                              |
+---------------------------------------------------------+
|  PRERREQUISITOS (modulo 01)                             |
|  Scoop, uv, Node LTS, Git, Python 3.12, Servy,         |
|  Tailscale, VC++ Redistributable, psmux                 |
+---------------------------------------------------------+
```

### Gestor de paquetes: Scoop (no WinGet)

En Windows 10 LTSC, WinGet no funciona (App Execution Aliases son
reparse points que requieren Microsoft Store). El bootstrap usa
**Scoop** como unico package manager, compatible con todas las ediciones.

### Service manager: Servy

Todos los servicios de larga vida (Hermes, MoolMesh, Dagu, Uptime Kuma,
Glance, Paperclip, Odysseus) se registran en **Servy** (`aelassas/servy`),
un service manager ligero para Windows instalado via Scoop.

### SearXNG: remoto

SearXNG no tiene soporte nativo para Windows. Se consume via Tailscale
apuntando a una instancia remota (configurar `SEARXNG_URL` en `~/.env_agents`).

---

## Instalacion

### Paso 1: Clonar el repositorio

```powershell
# Abrir PowerShell como Administrador
mkdir -Force "$env:USERPROFILE\ai-lab\repos" | Out-Null
cd "$env:USERPROFILE\ai-lab\repos"
git clone https://github.com/almacreativa/ai-lab-bootstrap.git
cd ai-lab-bootstrap
```

Si Git no esta instalado, descargarlo de https://git-scm.com/download/win
y repetir el paso.

### Paso 2: Configurar variables (opcional)

```powershell
# Valores por defecto: todo en "true" salvo SSH
$env:INSTALL_HERMES = "true"
$env:INSTALL_PAPERCLIP = "true"
$env:INSTALL_ODYSSEUS = "true"
$env:INSTALL_DAGU = "true"
$env:INSTALL_UPTIME_KUMA = "true"
$env:INSTALL_GLANCE = "true"
$env:INSTALL_NLM = "true"
$env:LAB_INSTALL_SSH_SERVER = "false"
```

Para desactivar un servicio: `$env:INSTALL_HERMES = "false"`.

### Paso 3: Ejecutar el bootstrap

```powershell
.\bootstrap-windows.ps1
```

El script muestra un resumen del sistema detectado y la configuracion.
Confirmar con `S` para continuar.

No requiere reinicio. Todo se instala en una sola ejecucion.

---

## Que hace cada modulo

### Modulo 01 -- Prerrequisitos (`01-host-prereqs.ps1`)

| Accion | Detalle |
|---|---|
| Long paths | Registro + `git config --system core.longpaths true` |
| Scoop | Package manager + bucket `extras` |
| Git | Via Scoop |
| Node.js LTS | Via Scoop |
| uv | Instalador oficial de Astral (Python toolchain) |
| Python 3.12 | Via `uv python install 3.12` (fijado, no latest) |
| GitHub CLI | Via Scoop |
| psmux | Terminal multiplexer nativo (Rust), via Scoop |
| VC++ Redistributable | Descarga directa de Microsoft (runtime para PG embebido de Paperclip) |
| VC++ Build Tools | Deteccion (no instala, solo informa si faltan) |
| Servy | Service manager, via Scoop (`innounp` + `servy`) |
| Tailscale | Descarga directa (no esta en Scoop) |
| OpenSSH Server | Solo si `LAB_INSTALL_SSH_SERVER=true` |
| Defender | Exclusiones para `~/ai-lab` y `~/.local/bin` |
| Plan de energia | High Performance |

### Modulo 02 -- Servicios nativos (`02-native-services.ps1`)

| Servicio | Instalacion | Puerto | Servy |
|---|---|---|---|
| Dagu | GitHub releases (`dagucloud/dagu`) | :8480 | Si |
| Uptime Kuma | `git clone` + `npm run setup` | :3001 | Si |
| Glance | GitHub releases (`glanceapp/glance`) | :5678 | Si |

### Modulo 03 -- Agentes AI (`03-ai-agents.ps1`)

| Agente | Instalacion | Servy |
|---|---|---|
| Claude Code | Instalador oficial (temp file + `&`) | No (interactivo) |
| OpenCode | Scoop | No (interactivo) |
| Engram | GitHub releases (`Gentleman-Programming/engram`) | No (stdio MCP) |
| Hermes Agent | `git clone NousResearch/hermes-agent` + `uv venv --clear --python 3.12` + `uv pip install -e .` + frontend build | Si (Gateway + Dashboard) |
| MoolMesh | `uv tool install moolmesh` | Si |
| Playwright MCP | `npm install -g @playwright/mcp` + `npx playwright install chromium` | No (stdio MCP) |
| NotebookLM MCP | `uv tool install notebooklm-mcp` | No (stdio MCP) |

### Modulo 04 -- Plataforma (`04-platform.ps1`)

| Servicio | Instalacion | Puerto | Servy |
|---|---|---|---|
| Paperclip | `npx paperclipai onboard --yes` (PG embebido, zero-config) | :3100 | Si |
| Odysseus | `git clone amish-github/odysseus` (fork Windows) + `uv venv --python 3.12` | :7000 | Si |

### Modulo 05 -- Conectividad (`05-connectivity.ps1`)

| Accion | Detalle |
|---|---|
| Firewall | Reglas TCP para puertos 9119, 5200, 8480, 3001, 5678, 3100, 7000 en interfaz Tailscale |
| Tailscale | Verificacion de estado |
| `.hermes/.env` | Template con TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_IDS, ANTHROPIC_API_KEY |
| `.env_agents` | Template con ANTHROPIC_API_KEY, OPENAI_API_KEY, SEARXNG_URL |

### Modulo 06 -- Post-install (`06-post-install.ps1`)

Imprime los pasos manuales requeridos (ver seccion siguiente).

---

## Pasos manuales post-bootstrap

El modulo 06 imprime esta lista. Si cerras la terminal, referencia aca.

### 1. Tailscale

Abrir Tailscale desde el menu de inicio y hacer login.

```powershell
tailscale status
```

### 2. Secrets

Completar los archivos creados por el bootstrap:

```
%USERPROFILE%\.hermes\.env      # Telegram bot token, allowed user IDs, API keys
%USERPROFILE%\.env_agents       # API keys compartidas, SEARXNG_URL
```

### 3. Hermes Gateway setup

```powershell
cd "$env:USERPROFILE\ai-lab\repos\hermes-agent"
uv run hermes gateway setup
# Configura: Telegram bot, allowed users, modelo default
```

### 4. Iniciar servicios

```powershell
servy start Dagu
servy start HermesGateway
servy start HermesDashboard
servy start MoolMesh
servy start UptimeKuma
servy start Glance
servy start Paperclip
servy start Odysseus

# Verificar:
servy list
```

Solo iniciar los servicios que se instalaron. Servy ignora los que no
estan registrados.

### 5. Health checks

```powershell
curl http://localhost:9119/api/health     # Hermes
curl http://localhost:5200/api/sessions   # MoolMesh
curl http://localhost:8480                # Dagu
curl http://localhost:3001                # Uptime Kuma
curl http://localhost:5678                # Glance
curl http://localhost:3100                # Paperclip
curl http://localhost:7000                # Odysseus
```

### 6. Logins de agentes

```powershell
claude            # login interactivo (abre browser)
nlm login         # NotebookLM (abre Chromium)
gh auth login     # GitHub CLI
```

### 7. Configurar MCP servers

En Claude Code y OpenCode, registrar:

| MCP | Tipo | Direccion |
|---|---|---|
| MoolMesh | HTTP | `localhost:5200` |
| Engram | stdio | binario local (`engram.exe`) |
| Playwright | stdio | `@playwright/mcp` (headed) |
| NotebookLM | stdio | `nlm` |
| Paperclip | HTTP | `localhost:3100` |

### 8. Dagu admin

Abrir http://localhost:8480 y crear usuario admin (primera vez).

### 9. Uptime Kuma

Abrir http://localhost:3001 y crear usuario admin, configurar monitors.

---

## Variables configurables

Exportar antes de correr `bootstrap-windows.ps1`:

```powershell
$env:INSTALL_HERMES = "true"            # Hermes Agent (default: true)
$env:INSTALL_PAPERCLIP = "true"         # Paperclip (default: true)
$env:INSTALL_ODYSSEUS = "true"          # Odysseus (default: true)
$env:INSTALL_DAGU = "true"             # Dagu scheduler (default: true)
$env:INSTALL_UPTIME_KUMA = "true"      # Uptime Kuma (default: true)
$env:INSTALL_GLANCE = "true"           # Glance dashboard (default: true)
$env:INSTALL_NLM = "true"             # NotebookLM MCP (default: true)
$env:LAB_INSTALL_SSH_SERVER = "false"  # OpenSSH Server (default: false)
.\bootstrap-windows.ps1
```

---

## Estructura de directorios

Despues del bootstrap:

```
%USERPROFILE%\
  ai-lab\
    apps\                    # servicios instalados (Glance, Uptime Kuma, etc)
    logs\                    # logs operativos
    repos\
      ai-lab-bootstrap\     # este repo
      hermes-agent\         # Hermes Agent (NousResearch)
      odysseus\             # Odysseus (fork Windows)
  .local\bin\               # binarios: engram.exe, dagu.exe, etc
  .hermes\
    .env                    # secrets de Hermes (nunca commitear)
  .env_agents               # API keys compartidas (nunca commitear)
  .paperclip\               # datos de Paperclip (PG embebido)
```

---

## Verificacion post-instalacion

```powershell
# Servicios registrados
servy list

# Binarios clave
foreach ($bin in @("git","node","uv","python","gh","claude","scoop","servy","dagu","psmux")) {
  if (Get-Command $bin -ErrorAction SilentlyContinue) {
    Write-Host "OK: $bin"
  } else {
    Write-Host "FALTA: $bin"
  }
}

# Defender exclusions
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath

# Plan de energia
powercfg /getactivescheme
```

---

## Troubleshooting

### Scoop falla con "Running the installer as administrator is disabled by default"

El bootstrap pasa `-RunAsAdmin` al instalador de Scoop. Si falla:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
iex "& {$(irm get.scoop.sh)} -RunAsAdmin"
```

### Paperclip PG falla con exit code 3221225781

El codigo `3221225781` (`0xC0000135`) significa DLL faltante: `vcruntime140_1.dll`.
El modulo 01 instala automaticamente el VC++ Redistributable. Si fallo:

```powershell
# Instalar manualmente:
Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile vc_redist.exe
.\vc_redist.exe /install /quiet /norestart
# Reintentar:
npx paperclipai onboard --yes
```

### uv/pip muestra output rojo pero la instalacion fue exitosa

PowerShell 5.1 trata stderr como error. uv y pip escriben progreso
y warnings a stderr. Si el script continua, el output rojo es cosmetic.
Los modulos usan `$ErrorActionPreference = "Continue"` para no abortar.

### `nlm` no encontrado despues de instalar

`uv tool install` pone binarios en `~/.local/bin`. Verificar que esta en PATH:

```powershell
$env:PATH -split ";" | Select-String ".local.bin"
# Si no aparece:
[Environment]::SetEnvironmentVariable("PATH","$([Environment]::GetEnvironmentVariable('PATH','User'));$env:USERPROFILE\.local\bin","User")
```

Cerrar y reabrir PowerShell para que tome efecto.

### Servy: "command not found" despues de instalar

Servy se instala via Scoop extras. Si falla:

```powershell
scoop bucket list     # debe incluir "extras"
scoop install innounp # dependencia de Servy
scoop install servy
```

### Dagu: no se encontro asset en GitHub releases

El repo es `dagucloud/dagu`. Si la descarga automatica falla:

1. Ir a https://github.com/dagucloud/dagu/releases
2. Descargar el `.zip` con `windows` y `amd64` en el nombre
3. Extraer `dagu.exe` a `%USERPROFILE%\.local\bin\`

### Tailscale: descarga fallo

Tailscale no esta en Scoop. Descargar directamente:

- https://tailscale.com/download/windows

### Hermes: clone fallo

Verificar acceso al repo:

```powershell
git ls-remote https://github.com/NousResearch/hermes-agent.git
```

Si da error de autenticacion, verificar `gh auth status`.

### SearXNG no disponible

SearXNG no corre nativo en Windows. Configurar la URL de una instancia
remota (servidor Linux u otro lab) en `~/.env_agents`:

```
SEARXNG_URL=http://<TAILSCALE_IP>:8080
```

---

## Mantenimiento

```powershell
# Ver servicios
servy list

# Logs de un servicio
servy logs <nombre>

# Reiniciar un servicio
servy restart <nombre>

# Detener un servicio
servy stop <nombre>

# Actualizar paquetes Scoop
scoop update *

# Actualizar Hermes
cd "$env:USERPROFILE\ai-lab\repos\hermes-agent"
git pull --ff-only
uv pip install -e .
servy restart HermesGateway
servy restart HermesDashboard
```

---

## Diferencias con la variante Linux (bare metal)

| Aspecto | Linux (servidor) | Windows (nativo) |
|---|---|---|
| Service manager | systemd | Servy |
| Package manager | apt + scripts | Scoop |
| Python toolchain | uv | uv |
| Docker | Docker CE | No (todo nativo) |
| Paperclip | Docker (3 containers) | PG embebido (zero-config) |
| Odysseus | Docker (2 containers) | Fork nativo (`amish-github/odysseus`) |
| SearXNG | Docker (local) | Remoto via Tailscale |
| Terminal multiplexer | tmux | psmux |
| Arranque | systemd al boot | Servy (auto-start) |
| Suspend | N/A (servidor 24/7) | Si Windows duerme, los servicios Servy se detienen |
