# ============================================================
# ai-lab-bootstrap --bootstrap-windows.ps1
# Levanta un AI agent lab en Windows 10/11, via WSL2 + Ubuntu.
#
# Uso (PowerShell como Administrador):
#   git clone https://github.com/almacreativa/ai-lab-bootstrap.git
#   cd ai-lab-bootstrap
#   .\bootstrap-windows.ps1
#
# Compatibilidad:
#   Windows 11 (22H2+) --soporte completo (mirrored networking, autoMemoryReclaim)
#   Windows 10 (22H2+) --funcional (NAT, sin features experimentales de WSL2)
#
# Variables configurables (exportar antes de correr el script):
#
#   LAB_USER_LINUX        usuario dentro de la distro WSL2 (default: detectado)
#   INSTALL_PAPERCLIP     instalar Paperclip en WSL2 (default: true)
#   INSTALL_HERMES        instalar Hermes Agent nativo (default: true)
#   INSTALL_NLM           instalar notebooklm-mcp-cli (default: true)
#   INSTALL_NATIVE_AGENTS instalar capa de agentes nativos Windows (default: true)
#   LAB_INSTALL_SSH_SERVER "true" para instalar OpenSSH Server en el host
#   WSL_MEMORY            RAM para WSL2 en GB (default: 50% del total)
#   WSL_PROCESSORS        CPUs para WSL2 (default: 50% de los logicos)
#
# Arquitectura de dos capas:
#   Capa Nativa (Windows bare metal):
#     Hermes, Claude Code, OpenCode, MoolMesh, Playwright MCP, Engram,
#     NotebookLM MCP -- servicios gestionados con Servy
#   Capa WSL2 (Ubuntu):
#     Docker CE, Paperclip, Dagu, SearXNG, Portainer, Uptime Kuma, Glance
#     -- systemd dentro de WSL2, port forwarding via netsh portproxy
#
# Docker Desktop NO se instala --es incompatible con networkingMode=mirrored.
# Se usa docker-ce nativo dentro de WSL2.
#
# Guia completa: docs/WINDOWS-INSTALL.md
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

function Write-LabLog  { param($msg) Write-Host "[bootstrap] $msg" -ForegroundColor Green }
function Write-LabWarn { param($msg) Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Write-LabErr  { param($msg) Write-Host "[error] $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "  ____   ___   ___ _____ ____ _____ ____   _    ____  " -ForegroundColor Cyan
Write-Host " | __ ) / _ \ / _ \_   _/ ___|_   _|  _ \ / \  |  _ \ " -ForegroundColor Cyan
Write-Host " |  _ \| | | | | | || | \___ \ | | | |_) / _ \ | |_) |" -ForegroundColor Cyan
Write-Host " | |_) | |_| | |_| || |  ___) || | |  _ / ___ \|  __/ " -ForegroundColor Cyan
Write-Host " |____/ \___/ \___/ |_| |____/ |_| |_|/_/   \_\_|    " -ForegroundColor Cyan
Write-Host ""
Write-Host "  AI Agent Lab Bootstrap -- Windows 10/11 (via WSL2 + Docker CE)" -ForegroundColor Cyan
Write-Host ""

# --- Deteccion de sistema ------------------------------------
$osBuild = [System.Environment]::OSVersion.Version.Build
$isWin11 = $osBuild -ge 22000
$osName = if ($isWin11) { "Windows 11" } else { "Windows 10" }
$osDisplayVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion

# --- Configuracion --------------------------------------------
if (-not $env:LAB_INSTALL_SSH_SERVER) { $env:LAB_INSTALL_SSH_SERVER = "false" }
if (-not $env:INSTALL_PAPERCLIP) { $env:INSTALL_PAPERCLIP = "true" }
if (-not $env:INSTALL_HERMES)    { $env:INSTALL_HERMES = "true" }
if (-not $env:INSTALL_NLM)       { $env:INSTALL_NLM = "true" }
if (-not $env:INSTALL_NATIVE_AGENTS) { $env:INSTALL_NATIVE_AGENTS = "true" }

$totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$totalCPU = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors
$wslMem = if ($env:WSL_MEMORY) { $env:WSL_MEMORY } else { [math]::Max(4, [math]::Floor($totalRAM / 2)) }
$wslCpu = if ($env:WSL_PROCESSORS) { $env:WSL_PROCESSORS } else { [math]::Max(2, [math]::Floor($totalCPU / 2)) }

$networkLabel = if ($isWin11) { "Mirrored (comparte IP del host)" } else { "NAT (IP propia)" }
$userLabel = if ($env:LAB_USER_LINUX) { $env:LAB_USER_LINUX } else { "(detectado auto)" }

Write-Host "  Sistema operativo    : $osName $osDisplayVersion (build $osBuild)"
Write-Host "  Hardware detectado   : ${totalRAM}GB RAM, $totalCPU CPUs"
Write-Host "  WSL2 asignado        : ${wslMem}GB RAM, $wslCpu CPUs"
Write-Host "  Networking WSL2      : $networkLabel"
Write-Host "  Usuario Linux (WSL2) : $userLabel"
Write-Host "  Instalar Paperclip   : $env:INSTALL_PAPERCLIP"
Write-Host "  Instalar Hermes      : $env:INSTALL_HERMES"
Write-Host "  Instalar nlm         : $env:INSTALL_NLM"
Write-Host "  Agentes nativos Win  : $env:INSTALL_NATIVE_AGENTS"
Write-Host "  Instalar SSH Server  : $env:LAB_INSTALL_SSH_SERVER"
if (-not $isWin11) {
  Write-Host ""
  Write-Host "  NOTA: Windows 10 --sin mirrored networking ni features" -ForegroundColor Yellow
  Write-Host "  experimentales de WSL2. Ver docs/WINDOWS-INSTALL.md" -ForegroundColor Yellow
}
Write-Host ""
$confirm = Read-Host "  Continuar con esta configuracion? [S/n]"
if (-not $confirm) { $confirm = "S" }
if ($confirm -notmatch "^[Ss]$") { Write-Host "Abortado."; exit 0 }

# --- Modulos --------------------------------------------------
. "$ScriptDir\modules\windows-host\01-host-prereqs.ps1"
. "$ScriptDir\modules\windows-host\02-wsl-provision.ps1"
if ($env:INSTALL_NATIVE_AGENTS -eq "true") {
  . "$ScriptDir\modules\windows-host\03-native-agents.ps1"
}
. "$ScriptDir\modules\windows-host\04-post-install.ps1"
