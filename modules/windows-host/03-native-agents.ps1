# Modulo 03 (Windows host) --Agentes nativos en Windows
# Instala: Python 3.12, Claude Code, OpenCode, Hermes,
# MoolMesh, Playwright MCP, NotebookLM MCP, Engram, Servy, port forwarding
# Cada paso es idempotente: verifica antes de instalar.
# Scoop y uv ya instalados por modulo 01.

# PS 5.1 con $ErrorActionPreference=Stop trata stderr de comandos nativos
# (uv, npm, scoop, npx) como errores terminantes. Este modulo usa checks
# explicitos (Get-Command, Test-Path) para validar exito.
$ErrorActionPreference = "Continue"

Write-LabLog "Paso 3/4 --Agentes nativos en Windows..."

# --- Utilidad: refrescar PATH en la sesion actual ----------------
function Refresh-SessionPath {
  $env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")
}

# --- Asegurar directorio .local\bin ------------------------------
$localBin = Join-Path $env:USERPROFILE ".local\bin"
if (-not (Test-Path $localBin)) { New-Item -Path $localBin -ItemType Directory -Force | Out-Null }

$userPath = [Environment]::GetEnvironmentVariable("PATH","User")
if ($userPath -notlike "*$localBin*") {
  [Environment]::SetEnvironmentVariable("PATH","$userPath;$localBin","User")
  Write-LabLog "Agregado $localBin al PATH del usuario."
}
Refresh-SessionPath

# --- Verificar dependencias del modulo 01 -------------------------
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
  Write-LabWarn "Scoop no encontrado --debio instalarse en modulo 01. Saltando agentes nativos."
  return
}
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-LabWarn "uv no encontrado --debio instalarse en modulo 01. Algunas herramientas no se instalaran."
}

# --- 2. uv (fallback si modulo 01 fallo) -------------------------
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando uv (fallback)..."
  $uvInstaller = Join-Path $env:TEMP "uv-install.ps1"
  Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -OutFile $uvInstaller -UseBasicParsing
  & $uvInstaller
  Remove-Item $uvInstaller -Force -ErrorAction SilentlyContinue
  Refresh-SessionPath
  if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-LabLog "uv instalado ($(uv --version 2>$null))."
  } else {
    Write-LabWarn "uv: instalador completo pero 'uv' no esta en PATH."
  }
} else {
  Write-LabLog "uv ya instalado ($(uv --version 2>$null)), saltando."
}

# --- 3. Python 3.12 via uv ---------------------------------------
if (Get-Command uv -ErrorAction SilentlyContinue) {
  $py312 = uv python list 2>$null | Select-String "3\.12"
  if (-not $py312) {
    Write-LabLog "Instalando Python 3.12 via uv..."
    uv python install 3.12
    Write-LabLog "Python 3.12 instalado."
  } else {
    Write-LabLog "Python 3.12 ya disponible via uv, saltando."
  }
} else {
  Write-LabWarn "uv no disponible --saltando instalacion de Python 3.12."
}

# --- 4. Claude Code -----------------------------------------------
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-LabLog "Instalando Claude Code..."
  $claudeInstaller = Join-Path $env:TEMP "claude-install.ps1"
  Invoke-WebRequest -Uri "https://claude.ai/install.ps1" -OutFile $claudeInstaller -UseBasicParsing
  & $claudeInstaller
  Remove-Item $claudeInstaller -Force -ErrorAction SilentlyContinue
  Refresh-SessionPath
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-LabLog "Claude Code instalado ($(claude --version 2>$null))."
  } else {
    Write-LabWarn "Claude Code: instalador completo pero 'claude' no esta en PATH."
  }
} else {
  Write-LabLog "Claude Code ya instalado ($(claude --version 2>$null)), saltando."
}

# --- 5. OpenCode (via Scoop) --------------------------------------
if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-LabLog "Instalando OpenCode via Scoop..."
    scoop install opencode
    Refresh-SessionPath
    if (Get-Command opencode -ErrorAction SilentlyContinue) {
      Write-LabLog "OpenCode instalado ($(opencode --version 2>$null))."
    } else {
      Write-LabWarn "OpenCode: scoop install completo pero 'opencode' no esta en PATH."
    }
  } else {
    Write-LabWarn "Scoop no disponible --no se puede instalar OpenCode."
  }
} else {
  Write-LabLog "OpenCode ya instalado ($(opencode --version 2>$null)), saltando."
}

# --- 6. Hermes Agent (condicional) --------------------------------
if ($env:INSTALL_HERMES -eq "true") {
  $hermesRepo = Join-Path $env:USERPROFILE "ai-lab\repos\hermes-agent"
  if (-not (Test-Path (Join-Path $hermesRepo ".git"))) {
    Write-LabLog "Clonando Hermes Agent..."
    $reposDir = Join-Path $env:USERPROFILE "ai-lab\repos"
    New-Item -Path $reposDir -ItemType Directory -Force | Out-Null
    git clone https://github.com/NousResearch/hermes-agent.git $hermesRepo
    if (-not (Test-Path (Join-Path $hermesRepo ".git"))) {
      Write-LabWarn "Hermes: clone fallo. Verificar acceso al repo y volver a correr."
      $env:INSTALL_HERMES = "false"
    }
  } else {
    Write-LabLog "Hermes Agent repo ya existe, actualizando..."
    Push-Location $hermesRepo
    git pull --ff-only 2>$null
    Pop-Location
  }

  if ($env:INSTALL_HERMES -eq "true" -and (Test-Path $hermesRepo) -and (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-LabLog "Instalando dependencias de Hermes..."
    Push-Location $hermesRepo
    uv venv --clear
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
      Write-LabWarn "Hermes: instalacion completa pero 'uv run hermes version' fallo."
    }
  } else {
    Write-LabWarn "uv no disponible --no se puede instalar Hermes."
  }
} else {
  Write-LabLog "INSTALL_HERMES no es 'true' --saltando Hermes Agent."
}

# --- 7. MoolMesh --------------------------------------------------
if (-not (Get-Command mool -ErrorAction SilentlyContinue)) {
  if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-LabLog "Instalando MoolMesh..."
    uv tool install moolmesh
    Refresh-SessionPath
    if (Get-Command mool -ErrorAction SilentlyContinue) {
      Write-LabLog "MoolMesh instalado ($(mool --version 2>$null))."
    } else {
      Write-LabWarn "MoolMesh: uv tool install completo pero 'mool' no esta en PATH."
    }
  } else {
    Write-LabWarn "uv no disponible --no se puede instalar MoolMesh."
  }
} else {
  Write-LabLog "MoolMesh ya instalado ($(mool --version 2>$null)), saltando."
}

# --- 8. Playwright MCP --------------------------------------------
if (-not (Get-Command playwright-mcp -ErrorAction SilentlyContinue)) {
  if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-LabLog "Instalando Playwright MCP..."
    npm install -g @playwright/mcp
    npx playwright install chromium
    Refresh-SessionPath
    Write-LabLog "Playwright MCP + Chromium instalados."
  } else {
    Write-LabWarn "npm no disponible --no se puede instalar Playwright MCP."
  }
} else {
  Write-LabLog "Playwright MCP ya instalado, saltando."
}

# --- 9. NotebookLM MCP --------------------------------------------
if (-not (Get-Command nlm -ErrorAction SilentlyContinue)) {
  if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-LabLog "Instalando NotebookLM MCP..."
    uv tool install notebooklm-mcp
    Refresh-SessionPath
    if (Get-Command nlm -ErrorAction SilentlyContinue) {
      Write-LabLog "NotebookLM MCP instalado ($(nlm --version 2>$null))."
    } else {
      Write-LabWarn "NotebookLM MCP: instalacion completa pero 'nlm' no esta en PATH."
    }
  } else {
    Write-LabWarn "uv no disponible --no se puede instalar NotebookLM MCP."
  }
} else {
  Write-LabLog "NotebookLM MCP ya instalado ($(nlm --version 2>$null)), saltando."
}

# --- 10. Engram ---------------------------------------------------
$engramBin = Join-Path $localBin "engram.exe"
if (-not (Test-Path $engramBin)) {
  Write-LabLog "Instalando Engram..."
  try {
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/Gentleman-Programming/engram/releases" -UseBasicParsing
    $release = $releases | Where-Object { $_.tag_name -match "^v[0-9]" -and $_.assets.Count -gt 0 } | Select-Object -First 1
    if ($release) {
      $asset = $release.assets | Where-Object { $_.name -match "windows_amd64" } | Select-Object -First 1
      if ($asset) {
        $tmpZip = Join-Path $env:TEMP "engram-windows.tar.gz"
        $tmpDir = Join-Path $env:TEMP "engram-extract"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -UseBasicParsing
        New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
        tar -xzf $tmpZip -C $tmpDir
        $exeFile = Get-ChildItem -Path $tmpDir -Filter "engram.exe" -Recurse | Select-Object -First 1
        if ($exeFile) {
          Move-Item -Path $exeFile.FullName -Destination $engramBin -Force
          Write-LabLog "Engram $($release.tag_name) instalado."
        } else {
          Write-LabWarn "Engram: archivo no contenia engram.exe"
        }
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
      } else {
        Write-LabWarn "Engram: no se encontro asset windows_amd64 en release $($release.tag_name)."
      }
    } else {
      Write-LabWarn "Engram: no se encontro release con tag v* y assets."
    }
  } catch {
    Write-LabWarn "Engram: error al consultar GitHub API --instalar manualmente."
  }
} else {
  Write-LabLog "Engram ya instalado en $engramBin, saltando."
}

# --- 11. Servy (service manager) ----------------------------------
$servyInstalled = winget list --id Servy --exact --accept-source-agreements 2>$null | Select-String "Servy"
if (-not $servyInstalled) {
  Write-LabLog "Instalando Servy via winget..."
  $result = winget install --id Servy --exact --silent --accept-package-agreements --accept-source-agreements 2>$null
  if (-not $?) {
    Write-LabWarn "Servy: winget install fallo. Intentando via Scoop..."
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
      scoop install servy
    } else {
      Write-LabWarn "Servy: instalar manualmente desde https://github.com/jandre-m/servy/releases"
    }
  }
  Refresh-SessionPath
  if (Get-Command servy -ErrorAction SilentlyContinue) {
    Write-LabLog "Servy instalado."
  } else {
    Write-LabWarn "Servy: instalacion completa pero 'servy' no esta en PATH."
  }
} else {
  Write-LabLog "Servy ya instalado, saltando."
}

# --- 12. Registrar servicios con Servy ----------------------------
if ($env:INSTALL_HERMES -eq "true" -and (Get-Command servy -ErrorAction SilentlyContinue)) {
  $hermesRepo = Join-Path $env:USERPROFILE "ai-lab\repos\hermes-agent"
  $uvPath = (Get-Command uv -ErrorAction SilentlyContinue).Source

  if ($uvPath -and (Test-Path $hermesRepo)) {
    # HermesGateway
    $svcExists = servy list 2>$null | Select-String "HermesGateway"
    if (-not $svcExists) {
      Write-LabLog "Registrando servicio HermesGateway..."
      servy install --name "HermesGateway" --exe $uvPath --args "run hermes gateway run --accept-hooks" --working-dir $hermesRepo --start-type auto --restart-on-failure
    }

    # HermesDashboard
    $svcExists = servy list 2>$null | Select-String "HermesDashboard"
    if (-not $svcExists) {
      Write-LabLog "Registrando servicio HermesDashboard..."
      servy install --name "HermesDashboard" --exe $uvPath --args "run hermes dashboard --host 0.0.0.0 --port 9119 --no-open --insecure" --working-dir $hermesRepo --start-type auto --restart-on-failure
    }
  }

  # MoolMesh
  $moolPath = (Get-Command mool -ErrorAction SilentlyContinue).Source
  if ($moolPath) {
    $svcExists = servy list 2>$null | Select-String "MoolMesh"
    if (-not $svcExists) {
      Write-LabLog "Registrando servicio MoolMesh..."
      servy install --name "MoolMesh" --exe $moolPath --args "daemon start --host 0.0.0.0 --port 5200" --start-type auto --restart-on-failure
    }
  }

  Write-LabLog "Servicios registrados (NO iniciados --completar secrets primero)."
} elseif (-not (Get-Command servy -ErrorAction SilentlyContinue)) {
  Write-LabWarn "Servy no disponible --servicios no registrados."
}

# --- 13. Port forwarding WSL2 ------------------------------------
$scriptsDir = Join-Path $env:USERPROFILE "ai-lab\scripts"
New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
$portProxyScript = Join-Path $scriptsDir "update-portproxy.ps1"

if (-not (Test-Path $portProxyScript)) {
  Write-LabLog "Creando script update-portproxy.ps1..."
  $scriptContent = @'
# update-portproxy.ps1 --Actualiza netsh portproxy con la IP actual de WSL2
# Ejecutar como Administrador (tarea programada al logon)

$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
if (-not $wslIp) { Write-Host "WSL2 no disponible"; exit 1 }

$ports = @(3100, 8084, 3001, 8080, 9443)

foreach ($port in $ports) {
  netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>$null
  netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$wslIp
}

Write-Host "Port proxy actualizado: WSL2 IP = $wslIp, puertos: $($ports -join ', ')"
'@
  Set-Content -Path $portProxyScript -Value $scriptContent -Encoding ASCII
  Write-LabLog "update-portproxy.ps1 creado en $scriptsDir."

  # Registrar tarea programada
  $taskExists = Get-ScheduledTask -TaskName "WSL2-PortProxy-Update" -ErrorAction SilentlyContinue
  if (-not $taskExists) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$portProxyScript`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    Register-ScheduledTask -TaskName "WSL2-PortProxy-Update" -Action $action -Trigger $trigger -RunLevel Highest -Description "Actualiza netsh portproxy con IP actual de WSL2" | Out-Null
    Write-LabLog "Tarea programada 'WSL2-PortProxy-Update' registrada (corre al logon)."
  }
} else {
  Write-LabLog "update-portproxy.ps1 ya existe, saltando."
}

# Restaurar ErrorActionPreference para modulos siguientes
$ErrorActionPreference = "Stop"

Write-LabLog "Modulo 03 (agentes nativos) completo."
