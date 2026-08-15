# Modulo 03 -- Agentes AI: Claude Code, OpenCode, Hermes, MoolMesh, Engram,
# Playwright MCP, NotebookLM MCP

$ErrorActionPreference = "Continue"

Write-LabLog "Paso 3/6 -- Agentes AI..."

function Refresh-LabPath {
  $env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")
}

$localBin = Join-Path $env:USERPROFILE ".local\bin"
$labDir = Join-Path $env:USERPROFILE "ai-lab"
$reposDir = Join-Path $labDir "repos"
New-Item -Path $reposDir -ItemType Directory -Force | Out-Null

# --- Claude Code ----------------------------------------------
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando Claude Code..."
  $claudeInstaller = Join-Path $env:TEMP "claude-install.ps1"
  Invoke-WebRequest -Uri "https://claude.ai/install.ps1" -OutFile $claudeInstaller -UseBasicParsing
  & $claudeInstaller
  Remove-Item $claudeInstaller -Force -ErrorAction SilentlyContinue
  Refresh-LabPath
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-LabLog "Claude Code instalado ($(claude --version 2>$null))."
  } else {
    Write-LabWarn "Claude Code: instalador completo pero no esta en PATH."
  }
} else {
  Write-LabLog "Claude Code ya instalado ($(claude --version 2>$null)), saltando."
}

# --- OpenCode (via Scoop) -------------------------------------
if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-LabLog "Instalando OpenCode via Scoop..."
    scoop install opencode
    Refresh-LabPath
    if (Get-Command opencode -ErrorAction SilentlyContinue) {
      Write-LabLog "OpenCode instalado ($(opencode --version 2>$null))."
    } else {
      Write-LabWarn "OpenCode: scoop install completo pero no en PATH."
    }
  } else {
    Write-LabWarn "Scoop no disponible, no se puede instalar OpenCode."
  }
} else {
  Write-LabLog "OpenCode ya instalado ($(opencode --version 2>$null)), saltando."
}

# --- Engram (binario Go) --------------------------------------
$engramBin = Join-Path $localBin "engram.exe"
if (-not (Test-Path $engramBin)) {
  Write-LabLog "Instalando Engram..."
  try {
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/Gentleman-Programming/engram/releases" -UseBasicParsing
    $release = $releases | Where-Object { $_.tag_name -match "^v[0-9]" -and $_.assets.Count -gt 0 } | Select-Object -First 1
    if ($release) {
      $asset = $release.assets | Where-Object { $_.name -match "windows_amd64" } | Select-Object -First 1
      if ($asset) {
        $tmpFile = Join-Path $env:TEMP "engram-windows.tar.gz"
        $tmpDir = Join-Path $env:TEMP "engram-extract"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpFile -UseBasicParsing
        New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
        tar -xzf $tmpFile -C $tmpDir
        $exeFile = Get-ChildItem -Path $tmpDir -Filter "engram.exe" -Recurse | Select-Object -First 1
        if ($exeFile) {
          Move-Item $exeFile.FullName $engramBin -Force
          Write-LabLog "Engram $($release.tag_name) instalado."
        } else {
          Write-LabWarn "Engram: archivo no contenia engram.exe"
        }
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
      } else {
        Write-LabWarn "Engram: no se encontro asset windows_amd64."
      }
    } else {
      Write-LabWarn "Engram: no se encontro release con assets."
    }
  } catch {
    Write-LabWarn "Engram: error consultando GitHub API."
  }
} else {
  Write-LabLog "Engram ya instalado, saltando."
}

# --- Hermes Agent ---------------------------------------------
# Version fijada (pin) para consolidar. Windows compila desde fuente, y el repo
# tagea en CalVer (v2026.7.20 == release 0.19.0), no en semver como PyPI.
# Override con HERMES_TAG=v2026.x.y
$hermesTag = if ($env:HERMES_TAG) { $env:HERMES_TAG } else { "v2026.7.20" }
if ($env:INSTALL_HERMES -eq "true") {
  $hermesRepo = Join-Path $reposDir "hermes-agent"
  if (-not (Test-Path (Join-Path $hermesRepo ".git"))) {
    Write-LabLog "Clonando Hermes Agent ($hermesTag)..."
    git clone --branch $hermesTag --depth 1 https://github.com/NousResearch/hermes-agent.git $hermesRepo
    if (-not (Test-Path (Join-Path $hermesRepo ".git"))) {
      Write-LabWarn "Hermes: clone fallo. Verificar acceso al repo."
    }
  } else {
    Write-LabLog "Hermes Agent repo ya existe, fijando en $hermesTag..."
    Push-Location $hermesRepo
    git fetch --tags 2>$null
    git checkout $hermesTag 2>$null
    Pop-Location
  }

  if ((Test-Path $hermesRepo) -and (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-LabLog "Instalando dependencias de Hermes..."
    Push-Location $hermesRepo
    uv venv --clear --python 3.12
    uv pip install -e .
    Pop-Location

    # Compilar frontend
    $webDir = Join-Path $hermesRepo "apps\web"
    if (Test-Path $webDir) {
      Write-LabLog "Compilando frontend de Hermes..."
      Push-Location $webDir
      npm install
      npm run build
      Pop-Location
    }

    # Verificar
    Push-Location $hermesRepo
    $hermesVer = uv run hermes version 2>$null
    Pop-Location
    if ($hermesVer) {
      Write-LabLog "Hermes Agent instalado ($hermesVer)."
    } else {
      Write-LabWarn "Hermes: 'uv run hermes version' fallo."
    }

    # Registrar en Servy
    if ((Get-Command servy -ErrorAction SilentlyContinue) -and $hermesVer) {
      $uvPath = (Get-Command uv -ErrorAction SilentlyContinue).Source

      $svcExists = Get-Service -ErrorAction SilentlyContinue -Name "HermesGateway"
      if (-not $svcExists) {
        Write-LabLog "Registrando HermesGateway en Servy..."
        servy install --name "HermesGateway" --path $uvPath --params "run hermes gateway run --accept-hooks" --startupDir $hermesRepo --startupType Automatic --recoveryAction RestartProcess
      }

      $svcExists = Get-Service -ErrorAction SilentlyContinue -Name "HermesDashboard"
      if (-not $svcExists) {
        Write-LabLog "Registrando HermesDashboard en Servy..."
        servy install --name "HermesDashboard" --path $uvPath --params "run hermes dashboard --host 0.0.0.0 --port 9119 --no-open --insecure" --startupDir $hermesRepo --startupType Automatic --recoveryAction RestartProcess
      }
    }
  }
} else {
  Write-LabLog "Hermes no solicitado, saltando."
}

# --- MoolMesh -------------------------------------------------
if (Get-Command uv -ErrorAction SilentlyContinue) {
  if (-not (Get-Command mool -ErrorAction SilentlyContinue)) {
    Write-LabLog "Instalando MoolMesh..."
    uv tool install moolmesh
    $uvToolBin = (uv tool dir --bin 2>$null)
    if ($uvToolBin) {
      $uvToolBin = $uvToolBin.Trim()
      $userPath = [Environment]::GetEnvironmentVariable("PATH","User")
      if ($userPath -notlike "*$uvToolBin*") {
        [Environment]::SetEnvironmentVariable("PATH","$userPath;$uvToolBin","User")
      }
    }
    Refresh-LabPath
    if (Get-Command mool -ErrorAction SilentlyContinue) {
      Write-LabLog "MoolMesh instalado ($(mool --version 2>$null))."
    } else {
      Write-LabWarn "MoolMesh: instalacion completa pero no en PATH."
    }
  } else {
    Write-LabLog "MoolMesh ya instalado ($(mool --version 2>$null)), verificando updates..."
    $upgradeOutput = uv tool upgrade moolmesh 2>&1
    if ($upgradeOutput -match "upgraded|Updated") {
      Write-LabLog "MoolMesh actualizado: $upgradeOutput"
    } else {
      Write-LabLog "MoolMesh al dia."
    }
  }
} else {
  Write-LabWarn "uv no disponible, no se puede instalar MoolMesh."
}

# Registrar MoolMesh en Servy
if ((Get-Command mool -ErrorAction SilentlyContinue) -and (Get-Command servy -ErrorAction SilentlyContinue)) {
  $svcExists = Get-Service -ErrorAction SilentlyContinue -Name "MoolMesh"
  if (-not $svcExists) {
    $moolPath = (Get-Command mool -ErrorAction SilentlyContinue).Source
    Write-LabLog "Registrando MoolMesh en Servy..."
    servy install --name "MoolMesh" --path $moolPath --params "daemon start --host 0.0.0.0 --port 5200" --startupType Automatic --recoveryAction RestartProcess
  }
}

# --- Playwright MCP -------------------------------------------
if (-not (Get-Command playwright-mcp -ErrorAction SilentlyContinue)) {
  if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-LabLog "Instalando Playwright MCP..."
    npm install -g @playwright/mcp
    npx playwright install chromium
    Refresh-LabPath
    Write-LabLog "Playwright MCP + Chromium instalados."
  } else {
    Write-LabWarn "npm no disponible, no se puede instalar Playwright MCP."
  }
} else {
  Write-LabLog "Playwright MCP ya instalado, saltando."
}

# --- NotebookLM MCP (jacob-bd/notebooklm-mcp-cli) ----------------
# Paquete PyPI: notebooklm-mcp-cli (CLI: nlm)
if ($env:INSTALL_NLM -eq "true") {
  if (Get-Command uv -ErrorAction SilentlyContinue) {
    $nlmInstalled = uv tool list 2>$null | Select-String "notebooklm-mcp-cli"
    if (-not $nlmInstalled) {
      # Desinstalar paquete incorrecto si existe
      $wrongPkg = uv tool list 2>$null | Select-String "notebooklm-mcp\s"
      if ($wrongPkg) {
        Write-LabWarn "Desinstalando paquete incorrecto (notebooklm-mcp)..."
        uv tool uninstall notebooklm-mcp 2>$null
      }
      Write-LabLog "Instalando NotebookLM MCP (notebooklm-mcp-cli)..."
      uv tool install notebooklm-mcp-cli
      Refresh-LabPath
      if (Get-Command nlm -ErrorAction SilentlyContinue) {
        Write-LabLog "NotebookLM MCP instalado ($(nlm --version 2>$null))."
      } else {
        $nlmCheck = uv tool run --from notebooklm-mcp-cli nlm --version 2>$null
        if ($nlmCheck) {
          Write-LabLog "NotebookLM MCP instalado ($nlmCheck). Puede requerir reabrir PowerShell para PATH."
        } else {
          Write-LabWarn "NotebookLM MCP: instalacion fallo."
        }
      }
    } else {
      Write-LabLog "NotebookLM MCP ya instalado, verificando updates..."
      $upgradeOutput = uv tool upgrade notebooklm-mcp-cli 2>&1
      if ($upgradeOutput -match "upgraded|Updated") {
        Write-LabLog "NotebookLM MCP actualizado: $upgradeOutput"
      } else {
        Write-LabLog "NotebookLM MCP al dia."
      }
    }
  } else {
    Write-LabWarn "uv no disponible, no se puede instalar NotebookLM MCP."
  }
} else {
  Write-LabLog "NotebookLM MCP no solicitado, saltando."
}

Write-LabLog "Modulo 03 completo."
