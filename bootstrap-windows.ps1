# ============================================================
# ai-lab-bootstrap — bootstrap-windows.ps1
# Levanta un AI agent lab en Windows 11, via WSL2 + Ubuntu.
#
# Uso (PowerShell como Administrador):
#   git clone https://github.com/almacreativa/ai-lab-bootstrap.git
#   cd ai-lab-bootstrap
#   .\bootstrap-windows.ps1
#
# Variables configurables (exportar antes de correr el script):
#
#   LAB_USER_LINUX        usuario dentro de la distro WSL2 (default: el actual)
#   LAB_INSTALL_SSH_SERVER "true" para instalar OpenSSH Server en el host
#                          (solo si esta máquina debe aceptar SSH remoto;
#                          no es necesario si solo se usa WSL2 localmente)
#
# Arquitectura: este script (host Windows) instala WinGet packages +
# WSL2/Ubuntu, y dentro de la distro delega en el bootstrap.sh de Linux
# (con detección de $WSL_DISTRO_NAME para no duplicar Docker/Tailscale/
# Syncthing/SSH, que viven mejor en el host).
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

function Write-LabLog  { param($msg) Write-Host "[bootstrap] $msg" -ForegroundColor Green }
function Write-LabWarn { param($msg) Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Write-LabErr  { param($msg) Write-Host "[error] $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "  ===============================================" -ForegroundColor Cyan
Write-Host "   AI Agent Lab Bootstrap — Windows 11 (via WSL2)" -ForegroundColor Cyan
Write-Host "  ===============================================" -ForegroundColor Cyan
Write-Host ""

if (-not $env:LAB_INSTALL_SSH_SERVER) { $env:LAB_INSTALL_SSH_SERVER = "false" }

Write-Host "  Usuario Linux (WSL2) : $(if ($env:LAB_USER_LINUX) { $env:LAB_USER_LINUX } else { '(detectado automáticamente)' })"
Write-Host "  Instalar SSH Server  : $($env:LAB_INSTALL_SSH_SERVER)"
Write-Host ""
$confirm = Read-Host "  ¿Continuar con esta configuración? [S/n]"
if (-not $confirm) { $confirm = "S" }
if ($confirm -notmatch "^[Ss]$") { Write-Host "Abortado."; exit 0 }

# ─── Módulos ──────────────────────────────────────────────────
. "$ScriptDir\modules\windows-host\01-host-prereqs.ps1"
. "$ScriptDir\modules\windows-host\02-wsl-provision.ps1"
. "$ScriptDir\modules\windows-host\03-post-install.ps1"
