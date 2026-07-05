# Modulo 01 (Windows host) --Long paths, WSL2, paquetes, .wslconfig,
# Windows Defender exclusions, OpenSSH Server, plan de energia
# Requiere PowerShell elevado (Run as Administrator)
#
# Detecta LTSC automaticamente y usa Scoop en vez de WinGet.
# WinGet es inutilizable en LTSC (App Execution Aliases rotos sin Store).

Write-LabLog "Paso 1/4 --Prerrequisitos del host..."

# --- Deteccion LTSC ----------------------------------------------
$editionId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
$isLTSC = $editionId -match "EnterpriseS"
$hasWinGet = $false
if (-not $isLTSC) {
  try {
    $wgVer = winget --version 2>$null
    if ($wgVer) { $hasWinGet = $true }
  } catch {}
}
$useScoop = $isLTSC -or (-not $hasWinGet)

if ($useScoop) {
  $reason = if ($isLTSC) { "edicion LTSC detectada" } else { "winget no funcional" }
  Write-LabLog "Package manager: Scoop ($reason). WinGet no se usara."
} else {
  Write-LabLog "Package manager: WinGet (edicion $editionId)."
}

# --- Long paths -----------------------------------------------
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null
git config --system core.longpaths true 2>$null
Write-LabLog "Long paths habilitados (registro + git --system)."

# --- WSL2 features -------------------------------------------
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -ne "Enabled") {
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
  Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
  Write-LabWarn "WSL2 habilitado --puede requerir reinicio antes de continuar al modulo 02."
} else {
  Write-LabLog "WSL2 ya estaba habilitado."
}

# --- .wslconfig (ANTES de provisionar la distro) -------------
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
if (-not (Test-Path $wslConfigPath)) {
  $totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
  $wslMemory = if ($env:WSL_MEMORY) { $env:WSL_MEMORY } else { [math]::Max(4, [math]::Floor($totalRAM / 2)) }
  $wslProcessors = if ($env:WSL_PROCESSORS) { $env:WSL_PROCESSORS } else {
    [math]::Max(2, [math]::Floor((Get-CimInstance Win32_Processor).NumberOfLogicalProcessors / 2))
  }

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
    Write-LabLog ".wslconfig generado: memory=${wslMemory}GB, processors=$wslProcessors (Windows 10 --sin mirrored)."
    Write-LabWarn "Windows 10: WSL2 usara NAT (IP propia). Ver docs/WINDOWS-INSTALL.md para implicaciones."
  }

  Set-Content -Path $wslConfigPath -Value $wslConfigContent -Encoding UTF8
} else {
  Write-LabLog ".wslconfig ya existe --no se sobreescribe. Verificar manualmente si es necesario."
}

# --- Scoop (siempre, necesario para agentes nativos y como fallback en LTSC)
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando Scoop (con -RunAsAdmin para sesion elevada)..."
  $scoopInstaller = Join-Path $env:TEMP "scoop-install.ps1"
  Invoke-WebRequest -Uri "https://get.scoop.sh" -OutFile $scoopInstaller -UseBasicParsing
  & $scoopInstaller -RunAsAdmin
  Remove-Item $scoopInstaller -Force -ErrorAction SilentlyContinue
  $env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")
  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-LabLog "Scoop instalado."
  } else {
    Write-LabWarn "Scoop: instalacion completo pero 'scoop' no esta en PATH aun."
  }
} else {
  Write-LabLog "Scoop ya instalado, saltando."
}

# Agregar extras bucket (Windows Terminal, Syncthing, Chromium)
if (Get-Command scoop -ErrorAction SilentlyContinue) {
  $buckets = scoop bucket list 2>$null
  if ($buckets -notmatch "extras") {
    Write-LabLog "Agregando Scoop extras bucket..."
    scoop bucket add extras
  }
}

# --- Paquetes: ruta WinGet o ruta Scoop --------------------------
if ($useScoop) {
  # --- RUTA SCOOP (LTSC o sin WinGet funcional) ---
  Write-LabLog "Instalando paquetes via Scoop..."

  # Main bucket: git, nodejs-lts, gh
  $scoopMainPkgs = @("git", "nodejs-lts", "gh")
  foreach ($pkg in $scoopMainPkgs) {
    if (-not (Get-Command $pkg -ErrorAction SilentlyContinue)) {
      Write-LabLog "Instalando $pkg via Scoop..."
      scoop install $pkg
    } else {
      Write-LabLog "$pkg ya instalado, saltando."
    }
  }

  # Extras bucket: windows-terminal, syncthing, chromium
  $scoopExtraPkgs = @("windows-terminal", "syncthing", "chromium")
  foreach ($pkg in $scoopExtraPkgs) {
    $installed = scoop list 2>$null | Select-String $pkg
    if (-not $installed) {
      Write-LabLog "Instalando $pkg via Scoop (extras)..."
      scoop install $pkg
    } else {
      Write-LabLog "$pkg ya instalado, saltando."
    }
  }

  # Tailscale: no esta en Scoop, descarga directa
  if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
    Write-LabLog "Instalando Tailscale (descarga directa)..."
    $tailscaleInstaller = Join-Path $env:TEMP "tailscale-setup.exe"
    try {
      Invoke-WebRequest -Uri "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe" -OutFile $tailscaleInstaller -UseBasicParsing
      Start-Process -FilePath $tailscaleInstaller -ArgumentList "/S" -Wait
      Remove-Item $tailscaleInstaller -Force -ErrorAction SilentlyContinue
      $env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")
      Write-LabLog "Tailscale instalado."
    } catch {
      Write-LabWarn "Tailscale: descarga fallo. Instalar manualmente desde tailscale.com/download/windows"
    }
  } else {
    Write-LabLog "Tailscale ya instalado, saltando."
  }

} else {
  # --- RUTA WINGET (Windows normal con Store funcional) ---
  Write-LabLog "Verificando paquetes WinGet (primera vez puede tardar mientras actualiza el indice)..."

  $packages = @(
    "Git.Git",
    "Microsoft.WindowsTerminal",
    "GitHub.cli",
    "Tailscale.Tailscale",
    "Syncthing.Syncthing"
  )

  foreach ($pkg in $packages) {
    $installed = winget list --id $pkg --exact --accept-source-agreements 2>$null | Select-String $pkg
    if (-not $installed) {
      Write-LabLog "Instalando $pkg via winget..."
      winget install --id $pkg --exact --silent --accept-package-agreements --accept-source-agreements
    } else {
      Write-LabLog "$pkg ya instalado, saltando."
    }
  }

  # Node.js LTS
  $nodeInstalled = winget list --id OpenJS.NodeJS.LTS --exact --accept-source-agreements 2>$null | Select-String "OpenJS.NodeJS.LTS"
  if (-not $nodeInstalled) {
    Write-LabLog "Instalando Node.js LTS via winget..."
    winget install --id OpenJS.NodeJS.LTS --exact --silent --accept-package-agreements --accept-source-agreements
  } else {
    Write-LabLog "Node.js LTS ya instalado, saltando."
  }

  # Chromium
  $chromiumInstalled = winget list --id Hibbiki.Chromium --exact --accept-source-agreements 2>$null | Select-String "Hibbiki.Chromium"
  if (-not $chromiumInstalled) {
    Write-LabLog "Instalando Chromium via winget..."
    winget install --id Hibbiki.Chromium --exact --silent --accept-package-agreements --accept-source-agreements
  } else {
    Write-LabLog "Chromium ya instalado, saltando."
  }
}

# Refrescar PATH despues de instalar paquetes
$env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")

# --- uv (Python toolchain unificado) ----------------------------
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando uv (Astral Python toolchain)..."
  Invoke-Expression (Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -UseBasicParsing).Content
  $env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")
  if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-LabLog "uv instalado ($(uv --version 2>$null))."
  } else {
    Write-LabWarn "uv: instalador completo pero 'uv' no esta en PATH aun."
  }
} else {
  Write-LabLog "uv ya instalado ($(uv --version 2>$null)), saltando."
}

# --- Windows Defender --exclusiones para WSL2 ----------------
Write-LabLog "Configurando exclusiones de Windows Defender para WSL2..."
try {
  Add-MpPreference -ExclusionProcess "vmmem.exe", "vmmemWSL.exe", "wsl.exe", "wslhost.exe", "msrdc.exe" -ErrorAction SilentlyContinue
  Add-MpPreference -ExclusionPath "\\wsl$\", "\\wsl.localhost\" -ErrorAction SilentlyContinue
  Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Packages" -ErrorAction SilentlyContinue
  Write-LabLog "Exclusiones de Defender aplicadas (procesos WSL + paths virtuales + VHDX)."
} catch {
  Write-LabWarn "No se pudieron aplicar exclusiones de Defender --verificar manualmente."
}

# --- Plan de energia --High Performance ----------------------
$currentPlan = powercfg /getactivescheme 2>$null
if ($currentPlan -notmatch "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c") {
  powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
  if ($?) {
    Write-LabLog "Plan de energia cambiado a 'High Performance'."
  } else {
    Write-LabWarn "No se pudo activar 'High Performance' --el plan puede no existir en este equipo."
    Write-LabWarn "Verificar manualmente: Configuracion > Sistema > Energia."
  }
} else {
  Write-LabLog "Plan de energia ya es 'High Performance'."
}

# --- OpenSSH Server (opcional) -------------------------------
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
  Write-LabLog "LAB_INSTALL_SSH_SERVER no esta en 'true' --saltando OpenSSH Server."
}

Write-LabLog "Modulo 01 (Windows host) completo."
