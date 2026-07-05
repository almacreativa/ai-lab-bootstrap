# ============================================================
# ai-lab-bootstrap -- bootstrap-windows.ps1
# Levanta un AI agent lab 100% nativo en Windows 10/11.
# Sin WSL2, sin Docker. Todo corre bare metal con Servy.
#
# Uso (PowerShell como Administrador):
#   git clone https://github.com/almacreativa/ai-lab-bootstrap.git
#   cd ai-lab-bootstrap
#   .\bootstrap-windows.ps1
#
# Compatibilidad:
#   Windows 10 LTSC (22H2+) -- soporte principal (sin WinGet, usa Scoop)
#   Windows 11 (22H2+)      -- compatible
#
# Variables configurables (exportar antes de correr el script):
#
#   INSTALL_HERMES        instalar Hermes Agent (default: true)
#   INSTALL_PAPERCLIP     instalar Paperclip (default: true)
#   INSTALL_ODYSSEUS      instalar Odysseus (default: true)
#   INSTALL_NLM           instalar NotebookLM MCP (default: true)
#   INSTALL_DAGU          instalar Dagu scheduler (default: true)
#   INSTALL_UPTIME_KUMA   instalar Uptime Kuma (default: true)
#   INSTALL_GLANCE        instalar Glance dashboard (default: true)
#   LAB_INSTALL_SSH_SERVER "true" para instalar OpenSSH Server
#
# Arquitectura:
#   Todo nativo Windows. Servicios gestionados por Servy.
#   SearXNG se consume remoto via Tailscale (no soportado nativo).
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
Write-Host "  AI Agent Lab Bootstrap -- Windows Nativo (Scoop + Servy)" -ForegroundColor Cyan
Write-Host ""

# --- Deteccion de sistema ------------------------------------
$osBuild = [System.Environment]::OSVersion.Version.Build
$isWin11 = $osBuild -ge 22000
$osName = if ($isWin11) { "Windows 11" } else { "Windows 10" }
$osDisplayVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
$editionId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
$isLTSC = $editionId -match "EnterpriseS"

# --- Configuracion -------------------------------------------
if (-not $env:INSTALL_HERMES)      { $env:INSTALL_HERMES = "true" }
if (-not $env:INSTALL_PAPERCLIP)   { $env:INSTALL_PAPERCLIP = "true" }
if (-not $env:INSTALL_ODYSSEUS)    { $env:INSTALL_ODYSSEUS = "true" }
if (-not $env:INSTALL_NLM)         { $env:INSTALL_NLM = "true" }
if (-not $env:INSTALL_DAGU)        { $env:INSTALL_DAGU = "true" }
if (-not $env:INSTALL_UPTIME_KUMA) { $env:INSTALL_UPTIME_KUMA = "true" }
if (-not $env:INSTALL_GLANCE)      { $env:INSTALL_GLANCE = "true" }
if (-not $env:LAB_INSTALL_SSH_SERVER) { $env:LAB_INSTALL_SSH_SERVER = "false" }

$totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$totalCPU = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors

Write-Host "  Sistema operativo : $osName $osDisplayVersion (build $osBuild)"
Write-Host "  Edicion           : $editionId$(if ($isLTSC) { ' (LTSC)' })"
Write-Host "  Hardware           : ${totalRAM}GB RAM, $totalCPU CPUs"
Write-Host ""
Write-Host "  --- Servicios a instalar ---"
Write-Host "  Hermes             : $env:INSTALL_HERMES"
Write-Host "  Paperclip          : $env:INSTALL_PAPERCLIP"
Write-Host "  Odysseus           : $env:INSTALL_ODYSSEUS"
Write-Host "  Dagu               : $env:INSTALL_DAGU"
Write-Host "  Uptime Kuma        : $env:INSTALL_UPTIME_KUMA"
Write-Host "  Glance             : $env:INSTALL_GLANCE"
Write-Host "  NotebookLM MCP     : $env:INSTALL_NLM"
Write-Host "  SSH Server         : $env:LAB_INSTALL_SSH_SERVER"
Write-Host ""
Write-Host "  SearXNG            : remoto (via Tailscale)" -ForegroundColor DarkGray
Write-Host ""
$confirm = Read-Host "  Continuar con esta configuracion? [S/n]"
if (-not $confirm) { $confirm = "S" }
if ($confirm -notmatch "^[Ss]$") { Write-Host "Abortado."; exit 0 }

# --- Modulos -------------------------------------------------
. "$ScriptDir\modules\windows-host\01-host-prereqs.ps1"
. "$ScriptDir\modules\windows-host\02-native-services.ps1"
. "$ScriptDir\modules\windows-host\03-ai-agents.ps1"
. "$ScriptDir\modules\windows-host\04-platform.ps1"
. "$ScriptDir\modules\windows-host\05-connectivity.ps1"
. "$ScriptDir\modules\windows-host\06-post-install.ps1"
