# Módulo 01 (Windows host) — Long paths, WSL2, WinGet packages, OpenSSH Server
# Requiere PowerShell elevado (Run as Administrator)

Write-LabLog "Paso 1/3 — Prerrequisitos del host..."

# Long paths — libera a Git/Node/npm del límite histórico de 260 caracteres
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null
Write-LabLog "Long paths habilitados en el registro (requiere reinicio para aplicar)."

# Habilitar WSL2 (feature de Windows)
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -ne "Enabled") {
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
  Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
  Write-LabWarn "WSL2 habilitado — puede requerir reinicio antes de continuar al módulo 02."
} else {
  Write-LabLog "WSL2 ya estaba habilitado."
}

# WinGet — paquetes del host (no se instalan dentro de WSL2)
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-LabWarn "winget no encontrado. Instalar 'App Installer' desde Microsoft Store y volver a correr."
  exit 1
}

$packages = @(
  "Git.Git",
  "Microsoft.WindowsTerminal",
  "Docker.DockerDesktop",
  "GitHub.cli",
  "Tailscale.Tailscale",
  "Syncthing.Syncthing"
)

foreach ($pkg in $packages) {
  $installed = winget list --id $pkg --exact 2>$null | Select-String $pkg
  if (-not $installed) {
    Write-LabLog "Instalando $pkg via winget..."
    winget install --id $pkg --exact --silent --accept-package-agreements --accept-source-agreements
  } else {
    Write-LabLog "$pkg ya instalado, saltando."
  }
}

# Docker Desktop — instalación silenciosa con backend WSL2 (si winget no aplicó los flags)
$dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
if (-not (Test-Path $dockerExe)) {
  Write-LabWarn "Docker Desktop no se encontró en la ruta esperada — verificar instalación manual."
}

# Chromium (para nlm login) — via winget, no via snap (no aplica en Windows)
$chromiumInstalled = winget list --id Hibbiki.Chromium --exact 2>$null | Select-String "Hibbiki.Chromium"
if (-not $chromiumInstalled) {
  Write-LabLog "Instalando Chromium via winget..."
  winget install --id Hibbiki.Chromium --exact --silent --accept-package-agreements --accept-source-agreements
} else {
  Write-LabLog "Chromium ya instalado, saltando."
}

# OpenSSH Server — solo si esta máquina debe ser accedida remotamente por SSH
if ($env:LAB_INSTALL_SSH_SERVER -eq "true") {
  $sshCapability = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0"
  if ($sshCapability.State -ne "Installed") {
    Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" | Out-Null
    Write-LabLog "OpenSSH Server instalado."
  } else {
    Write-LabLog "OpenSSH Server ya instalado."
  }
  Start-Service sshd
  Set-Service -Name sshd -StartupType Automatic

  $sshdConfig = "$env:ProgramData\ssh\sshd_config"
  (Get-Content $sshdConfig) `
    -replace '^#?PermitRootLogin.*', 'PermitRootLogin no' `
    -replace '^#?PasswordAuthentication.*', 'PasswordAuthentication no' `
    -replace '^#?TCPKeepAlive.*', 'TCPKeepAlive yes' `
    -replace '^#?ClientAliveInterval.*', 'ClientAliveInterval 30' `
    -replace '^#?ClientAliveCountMax.*', 'ClientAliveCountMax 3' `
    | Set-Content $sshdConfig
  Restart-Service sshd
  Write-LabLog "SSH hardening aplicado en el host Windows."
  Write-LabWarn "Si tu usuario es Administrador, agregar la llave pública en:"
  Write-LabWarn "  `$env:ProgramData\ssh\administrators_authorized_keys"
  Write-LabWarn "Y restringir permisos con:"
  Write-LabWarn '  icacls.exe "$env:ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"'
} else {
  Write-LabLog "LAB_INSTALL_SSH_SERVER no está en 'true' — saltando OpenSSH Server (no se necesita para WSL2)."
}

Write-LabLog "Módulo 01 (Windows host) completo."
