# Módulo 01 (Windows host) — Long paths, WSL2, WinGet packages, .wslconfig,
# Windows Defender exclusions, OpenSSH Server, plan de energía
# Requiere PowerShell elevado (Run as Administrator)

Write-LabLog "Paso 1/3 — Prerrequisitos del host..."

# ─── Long paths ───────────────────────────────────────────────
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null
git config --system core.longpaths true 2>$null
Write-LabLog "Long paths habilitados (registro + git --system)."

# ─── WSL2 features ───────────────────────────────────────────
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -ne "Enabled") {
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
  Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
  Write-LabWarn "WSL2 habilitado — puede requerir reinicio antes de continuar al módulo 02."
} else {
  Write-LabLog "WSL2 ya estaba habilitado."
}

# ─── .wslconfig (ANTES de provisionar la distro) ─────────────
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
if (-not (Test-Path $wslConfigPath)) {
  $totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
  $wslMemory = if ($env:WSL_MEMORY) { $env:WSL_MEMORY } else { [math]::Max(4, [math]::Floor($totalRAM / 2)) }
  $wslProcessors = if ($env:WSL_PROCESSORS) { $env:WSL_PROCESSORS } else {
    [math]::Max(2, [math]::Floor((Get-CimInstance Win32_Processor).NumberOfLogicalProcessors / 2))
  }

  # Detectar versión de Windows para features disponibles
  if ($null -eq $isWin11) { $isWin11 = [System.Environment]::OSVersion.Version.Build -ge 22000 }

  if ($isWin11) {
    $wslConfigContent = @"
[wsl2]
memory=${wslMemory}GB
processors=$wslProcessors
swap=4GB
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@
    Write-LabLog ".wslconfig generado: memory=${wslMemory}GB, processors=$wslProcessors, mirrored networking."
  } else {
    $wslConfigContent = @"
[wsl2]
memory=${wslMemory}GB
processors=$wslProcessors
swap=4GB
localhostForwarding=true
"@
    Write-LabLog ".wslconfig generado: memory=${wslMemory}GB, processors=$wslProcessors (Windows 10 — sin mirrored)."
    Write-LabWarn "Windows 10: WSL2 usará NAT (IP propia). Ver docs/WINDOWS-INSTALL.md para implicaciones."
  }

  Set-Content -Path $wslConfigPath -Value $wslConfigContent -Encoding UTF8
} else {
  Write-LabLog ".wslconfig ya existe — no se sobreescribe. Verificar manualmente si es necesario."
}

# ─── WinGet packages ─────────────────────────────────────────
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-LabWarn "winget no encontrado. Instalar 'App Installer' desde Microsoft Store y volver a correr."
  exit 1
}

$packages = @(
  "Git.Git",
  "Microsoft.WindowsTerminal",
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

# Chromium (para nlm login y Playwright MCP)
$chromiumInstalled = winget list --id Hibbiki.Chromium --exact 2>$null | Select-String "Hibbiki.Chromium"
if (-not $chromiumInstalled) {
  Write-LabLog "Instalando Chromium via winget..."
  winget install --id Hibbiki.Chromium --exact --silent --accept-package-agreements --accept-source-agreements
} else {
  Write-LabLog "Chromium ya instalado, saltando."
}

# ─── Windows Defender — exclusiones para WSL2 ────────────────
Write-LabLog "Configurando exclusiones de Windows Defender para WSL2..."
try {
  Add-MpPreference -ExclusionProcess "vmmem.exe", "vmmemWSL.exe", "wsl.exe", "wslhost.exe", "msrdc.exe" -ErrorAction SilentlyContinue
  Add-MpPreference -ExclusionPath "\\wsl$\", "\\wsl.localhost\" -ErrorAction SilentlyContinue
  Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Packages" -ErrorAction SilentlyContinue
  Write-LabLog "Exclusiones de Defender aplicadas (procesos WSL + paths virtuales + VHDX)."
} catch {
  Write-LabWarn "No se pudieron aplicar exclusiones de Defender — verificar manualmente."
}

# ─── Plan de energía — High Performance ──────────────────────
$currentPlan = powercfg /getactivescheme 2>$null
if ($currentPlan -notmatch "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c") {
  powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
  if ($?) {
    Write-LabLog "Plan de energía cambiado a 'High Performance'."
  } else {
    Write-LabWarn "No se pudo activar 'High Performance' — el plan puede no existir en este equipo."
    Write-LabWarn "Verificar manualmente: Configuración > Sistema > Energía."
  }
} else {
  Write-LabLog "Plan de energía ya es 'High Performance'."
}

# ─── OpenSSH Server (opcional) ───────────────────────────────
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

  # Hardening: deshabilitar root y password auth
  $sshdConfig = "$env:ProgramData\ssh\sshd_config"
  (Get-Content $sshdConfig) `
    -replace '^#?PermitRootLogin.*', 'PermitRootLogin no' `
    -replace '^#?PasswordAuthentication.*', 'PasswordAuthentication no' `
    -replace '^#?TCPKeepAlive.*', 'TCPKeepAlive yes' `
    -replace '^#?ClientAliveInterval.*', 'ClientAliveInterval 30' `
    -replace '^#?ClientAliveCountMax.*', 'ClientAliveCountMax 3' `
    | Set-Content $sshdConfig
  Restart-Service sshd

  # ACLs para administrators_authorized_keys
  $authKeysFile = Join-Path "$env:ProgramData\ssh" "administrators_authorized_keys"
  if (-not (Test-Path $authKeysFile)) {
    New-Item -Path $authKeysFile -ItemType File -Force | Out-Null
  }
  icacls.exe $authKeysFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null

  Write-LabLog "SSH hardening aplicado + ACLs de administrators_authorized_keys configuradas."
  Write-LabWarn "Agregar tu public key en: $authKeysFile"
} else {
  Write-LabLog "LAB_INSTALL_SSH_SERVER no está en 'true' — saltando OpenSSH Server."
}

Write-LabLog "Módulo 01 (Windows host) completo."
