# Modulo 01 -- Prerrequisitos: Scoop, uv, Node LTS, Git, VC++ Build Tools,
# Servy, psmux. Todo via Scoop + descargas directas (no WinGet).

$ErrorActionPreference = "Continue"

Write-LabLog "Paso 1/6 -- Prerrequisitos..."

# --- Utilidad -------------------------------------------------
function Refresh-LabPath {
  $env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")
}

# --- Directorio .local\bin ------------------------------------
$localBin = Join-Path $env:USERPROFILE ".local\bin"
if (-not (Test-Path $localBin)) { New-Item -Path $localBin -ItemType Directory -Force | Out-Null }
$userPath = [Environment]::GetEnvironmentVariable("PATH","User")
if ($userPath -notlike "*$localBin*") {
  [Environment]::SetEnvironmentVariable("PATH","$userPath;$localBin","User")
}
Refresh-LabPath

# --- Long paths -----------------------------------------------
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null
Write-LabLog "Long paths habilitados."

# --- Scoop ----------------------------------------------------
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando Scoop..."
  $scoopInstaller = Join-Path $env:TEMP "scoop-install.ps1"
  Invoke-WebRequest -Uri "https://get.scoop.sh" -OutFile $scoopInstaller -UseBasicParsing
  & $scoopInstaller -RunAsAdmin
  Remove-Item $scoopInstaller -Force -ErrorAction SilentlyContinue
  Refresh-LabPath
  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-LabLog "Scoop instalado."
  } else {
    Write-LabErr "Scoop: instalacion fallo. No se puede continuar."
  }
} else {
  Write-LabLog "Scoop ya instalado, saltando."
}

# Extras bucket
$buckets = scoop bucket list 2>$null
if ($buckets -notmatch "extras") {
  scoop bucket add extras
  Write-LabLog "Scoop extras bucket agregado."
}

# --- Git ------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando Git via Scoop..."
  scoop install git
  Refresh-LabPath
} else {
  Write-LabLog "Git ya instalado, saltando."
}
git config --system core.longpaths true 2>$null

# --- Node.js LTS ----------------------------------------------
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando Node.js LTS via Scoop..."
  scoop install nodejs-lts
  Refresh-LabPath
} else {
  Write-LabLog "Node.js ya instalado ($(node --version 2>$null)), saltando."
}

# --- uv (Python toolchain) ------------------------------------
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando uv..."
  $uvInstaller = Join-Path $env:TEMP "uv-install.ps1"
  Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -OutFile $uvInstaller -UseBasicParsing
  & $uvInstaller
  Remove-Item $uvInstaller -Force -ErrorAction SilentlyContinue
  Refresh-LabPath
  if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-LabLog "uv instalado ($(uv --version 2>$null))."
  } else {
    Write-LabWarn "uv: instalacion completa pero no esta en PATH."
  }
} else {
  Write-LabLog "uv ya instalado ($(uv --version 2>$null)), saltando."
}

# --- Python 3.12 via uv --------------------------------------
if (Get-Command uv -ErrorAction SilentlyContinue) {
  $py312 = uv python list 2>$null | Select-String "3\.12"
  if (-not $py312) {
    Write-LabLog "Instalando Python 3.12 via uv..."
    uv python install 3.12
  } else {
    Write-LabLog "Python 3.12 ya disponible, saltando."
  }
}

# --- GitHub CLI -----------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando GitHub CLI via Scoop..."
  scoop install gh
  Refresh-LabPath
} else {
  Write-LabLog "GitHub CLI ya instalado, saltando."
}

# --- psmux (terminal multiplexer nativo) ----------------------
if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando psmux via Scoop..."
  scoop install psmux
  Refresh-LabPath
} else {
  Write-LabLog "psmux ya instalado, saltando."
}

# --- Visual C++ Build Tools (deteccion) -----------------------
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasBuildTools = $false
if (Test-Path $vswhere) {
  $vsInstances = & $vswhere -products * -requires Microsoft.VisualStudio.Workload.VCTools -format json 2>$null | ConvertFrom-Json
  if ($vsInstances) { $hasBuildTools = $true }
}
if ($hasBuildTools) {
  Write-LabLog "Visual C++ Build Tools detectados."
} else {
  Write-LabWarn "Visual C++ Build Tools NO detectados."
  Write-LabWarn "Opcionales, solo para compilar extensiones nativas (node-gyp)."
  Write-LabWarn "El VC++ Redistributable (runtime) se instala aparte."
}

# --- Visual C++ Redistributable (runtime para Paperclip PG) ---
$vcRedist = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
if (-not $vcRedist) {
  Write-LabLog "Instalando Visual C++ Redistributable (x64)..."
  $vcInstaller = Join-Path $env:TEMP "vc_redist.x64.exe"
  try {
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcInstaller -UseBasicParsing
    Start-Process -FilePath $vcInstaller -ArgumentList "/install /quiet /norestart" -Wait
    Remove-Item $vcInstaller -Force -ErrorAction SilentlyContinue
    Write-LabLog "Visual C++ Redistributable instalado."
  } catch {
    Write-LabWarn "VC++ Redistributable: descarga fallo. Instalar manualmente:"
    Write-LabWarn "  https://aka.ms/vs/17/release/vc_redist.x64.exe"
  }
} else {
  Write-LabLog "Visual C++ Redistributable ya instalado."
}

# --- Servy (service manager, via Scoop) -----------------------
if (-not (Get-Command servy -ErrorAction SilentlyContinue)) {
  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-LabLog "Instalando Servy via Scoop..."
    scoop install innounp
    scoop install servy
    Refresh-LabPath
    if (Get-Command servy -ErrorAction SilentlyContinue) {
      Write-LabLog "Servy instalado."
    } else {
      $scoopServyDir = Join-Path $env:USERPROFILE "scoop\apps\servy\current"
      $servyExeFound = $null
      if (Test-Path $scoopServyDir) {
        $servyExeFound = Get-ChildItem -Path $scoopServyDir -Filter "*.exe" -Recurse |
          Where-Object { $_.Name -match "servy" } | Select-Object -First 1
      }
      if ($servyExeFound) {
        Copy-Item $servyExeFound.FullName (Join-Path $localBin "servy.exe") -Force
        Refresh-LabPath
        Write-LabLog "Servy instalado (shim manual: $($servyExeFound.Name) -> .local\bin\servy.exe)."
      } else {
        Write-LabWarn "Servy: scoop install completo pero ejecutable no encontrado."
        Write-LabWarn "Verificar: dir $scoopServyDir -Recurse *.exe"
      }
    }
  } else {
    Write-LabWarn "Scoop no disponible, no se puede instalar Servy."
  }
} else {
  Write-LabLog "Servy ya instalado, saltando."
}

# --- Tailscale (descarga directa, no en Scoop) ----------------
if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando Tailscale (descarga directa)..."
  $tailscaleInstaller = Join-Path $env:TEMP "tailscale-setup.exe"
  try {
    Invoke-WebRequest -Uri "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe" -OutFile $tailscaleInstaller -UseBasicParsing
    Start-Process -FilePath $tailscaleInstaller -ArgumentList "/S" -Wait
    Remove-Item $tailscaleInstaller -Force -ErrorAction SilentlyContinue
    Refresh-LabPath
    Write-LabLog "Tailscale instalado."
  } catch {
    Write-LabWarn "Tailscale: descarga fallo. Instalar desde tailscale.com/download/windows"
  }
} else {
  Write-LabLog "Tailscale ya instalado, saltando."
}

# --- OpenSSH Server (opcional) --------------------------------
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
  Write-LabLog "OpenSSH Server habilitado y en auto-start."
} else {
  Write-LabLog "SSH Server no solicitado, saltando."
}

# --- Windows Defender exclusiones -----------------------------
Write-LabLog "Configurando exclusiones de Windows Defender..."
try {
  $labDir = Join-Path $env:USERPROFILE "ai-lab"
  Add-MpPreference -ExclusionPath $labDir -ErrorAction SilentlyContinue
  Add-MpPreference -ExclusionPath $localBin -ErrorAction SilentlyContinue
  Write-LabLog "Exclusiones de Defender aplicadas ($labDir, $localBin)."
} catch {
  Write-LabWarn "No se pudieron aplicar exclusiones de Defender."
}

# --- Plan de energia --High Performance -----------------------
$currentPlan = powercfg /getactivescheme 2>$null
if ($currentPlan -notmatch "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c") {
  powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
  if ($?) { Write-LabLog "Plan de energia: High Performance." }
} else {
  Write-LabLog "Plan de energia ya es High Performance."
}

Refresh-LabPath
Write-LabLog "Modulo 01 completo."
