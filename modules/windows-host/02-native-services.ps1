# Modulo 02 -- Servicios nativos: Dagu, Uptime Kuma, Glance
# Cada uno se instala y registra en Servy.

$ErrorActionPreference = "Continue"

Write-LabLog "Paso 2/6 -- Servicios nativos..."

$labDir = Join-Path $env:USERPROFILE "ai-lab"
$appsDir = Join-Path $labDir "apps"
$logsDir = Join-Path $labDir "logs"
New-Item -Path $appsDir -ItemType Directory -Force | Out-Null
New-Item -Path $logsDir -ItemType Directory -Force | Out-Null

# --- Dagu (scheduler) ----------------------------------------
if ($env:INSTALL_DAGU -eq "true") {
  if (-not (Get-Command dagu -ErrorAction SilentlyContinue)) {
    Write-LabLog "Instalando Dagu..."
    try {
      $daguInstaller = Join-Path $env:TEMP "dagu-install.ps1"
      Invoke-WebRequest -Uri "https://dagu.sh/install.ps1" -OutFile $daguInstaller -UseBasicParsing
      & $daguInstaller -Service yes
      Remove-Item $daguInstaller -Force -ErrorAction SilentlyContinue
      $env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")
      if (Get-Command dagu -ErrorAction SilentlyContinue) {
        Write-LabLog "Dagu instalado (servicio registrado por su installer)."
      } else {
        Write-LabWarn "Dagu: installer completo pero 'dagu' no en PATH."
      }
    } catch {
      Write-LabWarn "Dagu: instalacion fallo. Instalar manualmente: https://docs.dagu.sh/deploy/windows"
    }
  } else {
    Write-LabLog "Dagu ya instalado, saltando."
  }
} else {
  Write-LabLog "Dagu no solicitado, saltando."
}

# --- Uptime Kuma ----------------------------------------------
if ($env:INSTALL_UPTIME_KUMA -eq "true") {
  $kumaDir = Join-Path $appsDir "uptime-kuma"
  if (-not (Test-Path (Join-Path $kumaDir "package.json"))) {
    Write-LabLog "Instalando Uptime Kuma..."
    git clone https://github.com/louislam/uptime-kuma.git $kumaDir
    if (Test-Path (Join-Path $kumaDir "package.json")) {
      Push-Location $kumaDir
      npm run setup
      Pop-Location
      Write-LabLog "Uptime Kuma instalado."
    } else {
      Write-LabWarn "Uptime Kuma: clone fallo."
    }
  } else {
    Write-LabLog "Uptime Kuma ya existe, saltando."
  }

  # Registrar en Servy
  if ((Test-Path (Join-Path $kumaDir "server\server.js")) -and (Get-Command servy -ErrorAction SilentlyContinue)) {
    $svcExists = servy list 2>$null | Select-String "UptimeKuma"
    if (-not $svcExists) {
      $nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
      if ($nodePath) {
        Write-LabLog "Registrando Uptime Kuma en Servy..."
        servy install --name "UptimeKuma" --exe $nodePath --args "server\server.js" --working-dir $kumaDir --start-type auto --restart-on-failure
      }
    }
  }
} else {
  Write-LabLog "Uptime Kuma no solicitado, saltando."
}

# --- Glance (dashboard) ---------------------------------------
if ($env:INSTALL_GLANCE -eq "true") {
  $glanceDir = Join-Path $appsDir "glance"
  $glanceExe = Join-Path $glanceDir "glance.exe"
  if (-not (Test-Path $glanceExe)) {
    Write-LabLog "Instalando Glance..."
    New-Item -Path $glanceDir -ItemType Directory -Force | Out-Null
    try {
      $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/glanceapp/glance/releases/latest" -UseBasicParsing
      $asset = $releases.assets | Where-Object { $_.name -match "windows.*amd64" -and $_.name -match "\.zip$" } | Select-Object -First 1
      if ($asset) {
        $tmpZip = Join-Path $env:TEMP "glance.zip"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -UseBasicParsing
        Expand-Archive -Path $tmpZip -DestinationPath $glanceDir -Force
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        if (Test-Path $glanceExe) {
          Write-LabLog "Glance $($releases.tag_name) instalado."
        } else {
          $found = Get-ChildItem -Path $glanceDir -Filter "glance.exe" -Recurse | Select-Object -First 1
          if ($found) { Move-Item $found.FullName $glanceExe -Force }
        }
      } else {
        Write-LabWarn "Glance: no se encontro asset windows-amd64 en releases."
      }
    } catch {
      Write-LabWarn "Glance: error descargando. Instalar manualmente."
    }
  } else {
    Write-LabLog "Glance ya instalado, saltando."
  }

  # Crear glance.yml si no existe
  $glanceYml = Join-Path $glanceDir "glance.yml"
  if (-not (Test-Path $glanceYml)) {
    $glanceConfig = @'
server:
  port: 5678
  host: 0.0.0.0

pages:
  - name: Home
    columns:
      - size: full
        widgets:
          - type: greeting
'@
    Set-Content -Path $glanceYml -Value $glanceConfig -Encoding UTF8
    Write-LabLog "glance.yml creado (editar para personalizar)."
  }

  # Registrar en Servy
  if ((Test-Path $glanceExe) -and (Get-Command servy -ErrorAction SilentlyContinue)) {
    $svcExists = servy list 2>$null | Select-String "Glance"
    if (-not $svcExists) {
      Write-LabLog "Registrando Glance en Servy..."
      servy install --name "Glance" --exe $glanceExe --working-dir $glanceDir --start-type auto --restart-on-failure
    }
  }
} else {
  Write-LabLog "Glance no solicitado, saltando."
}

Write-LabLog "Modulo 02 completo."
