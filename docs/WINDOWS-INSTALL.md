# Instalación en Windows — Guía completa

Guía paso a paso para instalar el AI Agent Lab en Windows 10/11 usando WSL2.

---

## Requisitos previos

### Sistema operativo

- **Windows 11** (22H2 o superior) — recomendado, soporte completo
- **Windows 10** (22H2 o superior) — funcional, con limitaciones de networking (ver sección abajo)

### Hardware

- **Virtualización habilitada en BIOS/UEFI** (Intel VT-x / AMD-V / SVM). Sin esto, WSL2 no puede crear la VM.
- Mínimo **8 GB de RAM** (recomendado 16 GB+ — WSL2 usa la mitad)
- **40 GB de espacio libre** en disco (el `.vhdx` de WSL2 crece con el uso)

### Software y permisos

- Cuenta con permisos de **Administrador** (el script configura features de Windows, Defender, servicios)
- Conexión a **internet** (descarga paquetes via WinGet y apt)
- **Git** instalado en el host (si no lo tenés, el script lo instala via WinGet, pero necesitás Git para clonar el repo inicialmente)

### Verificar virtualización

```powershell
# PowerShell — debe decir "True"
(Get-CimInstance Win32_ComputerSystem).HypervisorPresent
```

Si dice `False`, entrar al BIOS/UEFI y habilitar:
- Intel: "Intel Virtualization Technology (VT-x)"
- AMD: "SVM Mode" o "AMD-V"

---

## Escenario A — Máquina limpia (sin WSL2)

Este es el camino más directo. El bootstrap configura todo desde cero.

### Paso 1: Clonar el repositorio

```powershell
# Abrir PowerShell como Administrador
mkdir -Force "$env:USERPROFILE\ai-lab\repos" | Out-Null
cd "$env:USERPROFILE\ai-lab\repos"
git clone https://github.com/almacreativa/ai-lab-bootstrap.git
cd ai-lab-bootstrap
```

### Paso 2: Primera ejecución

```powershell
.\bootstrap-windows.ps1
```

El script muestra un resumen del hardware detectado y la configuración.
Confirmar con `S` para continuar.

**Qué hace en esta primera ejecución:**
- Habilita las features de Windows para WSL2
- Genera `.wslconfig` con límites de recursos y networking
- Instala paquetes via WinGet (Git, GitHub CLI, Tailscale, Syncthing, Chromium)
- Configura exclusiones de Windows Defender
- Activa plan de energía "High Performance"
- Intenta instalar la distro Ubuntu en WSL2

**Si WSL2 no estaba habilitado antes**, el script sale con este mensaje:

```
[warn] Si es la primera instalación de WSL2, puede pedir reiniciar.
[warn] Tras reiniciar, abrir la app 'Ubuntu' una vez para crear el usuario Linux,
[warn] y volver a correr bootstrap-windows.ps1.
```

### Paso 3: Reiniciar Windows

Reiniciar el equipo para que las features de WSL2 se activen.

### Paso 4: Crear usuario Linux

Después del reinicio, abrir la app **Ubuntu** desde el menú de inicio.
La primera vez pide crear un usuario y contraseña para la distro.
Este usuario será el `LAB_USER` dentro de WSL2.

### Paso 5: Segunda ejecución

```powershell
# PowerShell como Administrador (otra vez)
cd "$env:USERPROFILE\ai-lab\repos\ai-lab-bootstrap"
.\bootstrap-windows.ps1
```

Esta vez el script detecta que WSL2 y Ubuntu ya existen. Ejecuta:
1. Módulo 01: verifica que el host está configurado (idempotente)
2. Módulo 02: clona el repo dentro de WSL2, habilita systemd, ejecuta `bootstrap.sh`
3. Módulo 03: imprime la lista de pasos manuales finales

**`bootstrap.sh` dentro de WSL2 instala:** Docker CE, Node.js, Python, Claude Code, Hermes, Paperclip, y toda la infraestructura del lab — idéntico al servidor Linux.

### Paso 6: Pasos manuales post-bootstrap

El módulo 03 imprime una lista numerada de pasos manuales (secrets, logins, verificaciones). Si cerrás la terminal, la referencia completa está en `docs/POST-BOOTSTRAP.md` y la sección "Notas para Windows (WSL2)" al final del mismo.

---

## Escenario B — Ya tenés WSL2 con Ubuntu

Si WSL2 ya está funcionando y tenés el repo clonado dentro de la distro:

```powershell
# PowerShell como Administrador
cd \\wsl$\Ubuntu\home\<tu-usuario>\ai-lab\repos\ai-lab-bootstrap
.\bootstrap-windows.ps1
```

**¿Por qué desde PowerShell y no directamente `bash bootstrap.sh` dentro de WSL2?**

El bootstrap configura cosas en el **host Windows** que no se pueden hacer desde dentro de WSL2:

| Configuración | Por qué importa |
|---|---|
| `.wslconfig` | Límites de RAM/CPU, mirrored networking. Debe existir antes de que WSL2 arranque |
| Windows Defender exclusions | Sin exclusiones, I/O de WSL2 se degrada 40-60% |
| Plan de energía | Evita throttling de CPU durante compilaciones |
| WinGet packages | Tailscale y Syncthing corren en el host, no en WSL2 |
| OpenSSH Server | Acceso remoto al host (opcional) |

El script detecta que WSL2 ya existe, que el repo ya está clonado, y salta lo que ya está hecho. Solo va a hacer `wsl --shutdown` momentáneamente para aplicar el `.wslconfig` si lo genera por primera vez.

Si por algún motivo necesitás correr **solo** el bootstrap de Linux sin tocar el host:

```bash
# Dentro de WSL2 (Ubuntu)
cd ~/ai-lab/repos/ai-lab-bootstrap
bash bootstrap.sh
```

Esto funciona, pero te saltás toda la configuración del host. Solo hacerlo si ya configuraste el host manualmente.

---

## Qué hace cada módulo

### Módulo 01 — Host Windows (`01-host-prereqs.ps1`)

| Acción | Detalle |
|---|---|
| Long paths | Registro + `git config --system core.longpaths true` |
| WSL2 features | Habilita `Microsoft-Windows-Subsystem-Linux` y `VirtualMachinePlatform` |
| `.wslconfig` | Genera con límites auto-detectados. En W11: mirrored networking + experimental. En W10: básico |
| WinGet packages | Git, Windows Terminal, GitHub CLI, Tailscale, Syncthing, Chromium |
| Windows Defender | Exclusiones para procesos WSL2 (vmmem, wsl*) y paths virtuales (`\\wsl$\`) |
| Plan de energía | "High Performance" (GUID `8c5e7fda...`) |
| OpenSSH Server | Solo si `$env:LAB_INSTALL_SSH_SERVER = "true"`. Incluye hardening y ACLs |

### Módulo 02 — WSL2 (`02-wsl-provision.ps1`)

| Acción | Detalle |
|---|---|
| Instalar distro | `wsl --install -d Ubuntu --no-launch` (si no existe) |
| systemd | Inyecta `[boot] systemd=true` en `/etc/wsl.conf` (necesario para hermes.service, docker.service) |
| Detectar usuario | Usa `$env:LAB_USER_LINUX` o `wsl -- whoami` |
| Clonar repo | `git clone` dentro de WSL2, o `git pull` si ya existe |
| Delegar | Ejecuta `bootstrap.sh` dentro de WSL2 con las variables `INSTALL_PAPERCLIP`, `INSTALL_HERMES`, `INSTALL_NLM` |

### Módulo 03 — Post-install (`03-post-install.ps1`)

Imprime a pantalla todos los pasos manuales que el usuario debe completar:
reinicio pendiente, verificar Docker CE, secrets, Tailscale, GitHub CLI,
Claude Code, NLM, servicios, Portainer, Syncthing, arranque automático de WSL2,
y tips de mantenimiento.

---

## Windows 10 vs Windows 11

WSL2 funciona en ambas versiones, pero algunas features de `.wslconfig`
solo están disponibles en Windows 11:

| Característica | Windows 11 (22H2+) | Windows 10 (22H2+) |
|---|---|---|
| WSL2 + Ubuntu | ✓ | ✓ |
| systemd en WSL2 | ✓ | ✓ |
| Docker CE en WSL2 | ✓ | ✓ |
| Hermes, Paperclip, agentes | ✓ | ✓ |
| `networkingMode=mirrored` | ✓ | ✗ |
| `autoMemoryReclaim=gradual` | ✓ | ✗ |
| `sparseVhd=true` | ✓ | ✗ |
| `dnsTunneling` / `autoProxy` | ✓ | ✗ |

El script detecta la versión de Windows automáticamente y genera el `.wslconfig` apropiado.

### Implicaciones prácticas en Windows 10

**Networking (la diferencia más importante):**

En Windows 11 con mirrored, WSL2 comparte la IP del host — Tailscale del host cubre a WSL2 automáticamente, y los servicios son accesibles desde la LAN sin configuración extra.

En Windows 10, WSL2 tiene su **propia IP** (NAT `172.x.x.x`). Esto significa:
- Tailscale del host **no** cubre a WSL2 automáticamente
- Para acceder a servicios de WSL2 desde Windows, `localhost` funciona (via `localhostForwarding`)
- Para acceder desde otros dispositivos en la LAN, configurar port forwarding manualmente
- Si necesitás Tailscale dentro de WSL2, instalarlo manualmente: `curl -fsSL https://tailscale.com/install.sh | sh`

**Memoria:**

Sin `autoMemoryReclaim`, el proceso `vmmem` retiene toda la RAM que use aunque WSL2 la libere. El límite en `.wslconfig` es más importante — sin él, `vmmem` puede consumir toda la RAM del sistema.

**Disco:**

Sin `sparseVhd`, el archivo `.vhdx` (disco virtual de WSL2) solo crece, nunca se achica. Ejecutar periódicamente:

```powershell
wsl -d Ubuntu -- sudo fstrim -av
```

---

## Variables configurables

Exportar antes de correr `bootstrap-windows.ps1`:

```powershell
$env:INSTALL_PAPERCLIP = "true"          # default: true
$env:INSTALL_HERMES = "true"             # default: true
$env:INSTALL_NLM = "true"               # default: true
$env:LAB_INSTALL_SSH_SERVER = "true"     # default: false
$env:WSL_MEMORY = "12"                   # GB para WSL2 (default: 50% de RAM total)
$env:WSL_PROCESSORS = "6"               # CPUs para WSL2 (default: 50% de lógicos)
$env:LAB_USER_LINUX = "miusuario"       # usuario dentro de WSL2 (default: auto-detectado)
.\bootstrap-windows.ps1
```

---

## Verificación post-instalación

Después de completar los pasos manuales del módulo 03:

```powershell
# Desde PowerShell — verificar Docker CE
wsl -d Ubuntu -- docker run --rm hello-world

# Verificar systemd
wsl -d Ubuntu -- systemctl list-units --type=service --state=running

# Verificar Hermes
wsl -d Ubuntu -- sudo systemctl status hermes

# Verificar .wslconfig aplicado
wsl --status

# Verificar Defender exclusions
Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath

# Verificar plan de energía
powercfg /getactivescheme
```

---

## Troubleshooting

### "Virtualization must be enabled"

WSL2 necesita virtualización por hardware. Verificar:
1. Entrar al BIOS/UEFI (reiniciar → F2/F10/DEL según fabricante)
2. Buscar Intel VT-x, AMD-V, o SVM Mode → habilitar
3. Guardar y reiniciar

### WSL2 no arranca después del reinicio

```powershell
# Verificar estado
wsl --status

# Si falta el kernel, actualizarlo
wsl --update
```

### Docker CE no arranca dentro de WSL2

```bash
# Verificar que systemd está activo
ps -p 1 -o comm=
# Debe decir "systemd", no "init"

# Si dice "init", verificar /etc/wsl.conf:
cat /etc/wsl.conf
# Debe tener [boot] systemd=true

# Reiniciar WSL2 si se cambió wsl.conf:
# (desde PowerShell): wsl --shutdown
# Esperar 5 segundos, volver a entrar: wsl -d Ubuntu

# Verificar servicio Docker
sudo systemctl status docker
sudo systemctl start docker
```

### vmmem consume toda la RAM

El proceso `vmmem` es la VM de WSL2. Si crece sin control:
1. Verificar que `.wslconfig` existe: `type %USERPROFILE%\.wslconfig`
2. Verificar que tiene `memory=XGB`
3. Aplicar cambios: `wsl --shutdown` y esperar 10 segundos
4. En Windows 11: verificar que `autoMemoryReclaim=gradual` está en `[experimental]`

### Filesystem lento (WSL2)

Causas comunes:
1. **Windows Defender** escaneando archivos de WSL2 — verificar que las exclusiones se aplicaron
2. **Archivos en `/mnt/c/`** — el acceso a archivos del host desde WSL2 es lento por diseño. Trabajar siempre dentro del filesystem nativo de WSL2 (`~/`)
3. **Antivirus de terceros** — agregar exclusiones para `vmmem.exe` y `\\wsl$\`

### No puedo acceder a servicios de WSL2 desde la LAN (Windows 10)

Sin mirrored networking, WSL2 tiene IP propia. Opciones:
1. Desde Windows, usar `localhost` (funciona via `localhostForwarding`)
2. Desde la LAN, configurar port forwarding:
   ```powershell
   netsh interface portproxy add v4tov4 listenport=3100 listenaddress=0.0.0.0 connectport=3100 connectaddress=$(wsl hostname -I).Trim()
   ```
3. Considerar actualizar a Windows 11 para mirrored networking

---

## Mantenimiento

### Recuperar espacio en disco

El `.vhdx` de WSL2 crece con el uso pero no se achica solo (incluso con `sparseVhd` en W11):

```bash
# Dentro de WSL2
sudo fstrim -av
```

### Actualizar WSL2

```powershell
wsl --update
```

### Si la máquina se suspende

WSL2 y todos sus servicios (Docker, Hermes, systemd) se detienen cuando Windows entra en suspensión. Al despertar, WSL2 se reactiva automáticamente pero los servicios necesitan arrancar:

```bash
# Dentro de WSL2 — verificar que todo esté corriendo
sudo systemctl start docker hermes
docker ps  # verificar containers
```

Para máquinas que se usan como servidor (siempre encendidas), desactivar suspensión:
```powershell
powercfg /change standby-timeout-ac 0
```

### Arranque automático de WSL2

WSL2 no arranca solo al encender Windows. Registrar una tarea programada:

```powershell
$action = New-ScheduledTaskAction -Execute 'wsl.exe' -Argument '-d Ubuntu -- true'
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName 'WSL2-Ubuntu-Autostart' `
  -Action $action -Trigger $trigger -RunLevel Highest
```
