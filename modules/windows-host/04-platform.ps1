# Modulo 04 -- Plataforma: Paperclip, Odysseus
# Registra en Servy.

$ErrorActionPreference = "Continue"

Write-LabLog "Paso 4/6 -- Plataforma..."

function Refresh-LabPath {
  $env:PATH = [Environment]::GetEnvironmentVariable("PATH","User") + ";" + [Environment]::GetEnvironmentVariable("PATH","Machine")
}

$labDir = Join-Path $env:USERPROFILE "ai-lab"
$reposDir = Join-Path $labDir "repos"
$appsDir = Join-Path $labDir "apps"

# --- Paperclip ------------------------------------------------
if ($env:INSTALL_PAPERCLIP -eq "true") {
  $paperclipDir = Join-Path $appsDir "paperclip"
  $paperclipData = Join-Path $env:USERPROFILE ".paperclip"

  if (-not (Test-Path $paperclipData)) {
    if (Get-Command npx -ErrorAction SilentlyContinue) {
      Write-LabLog "Instalando Paperclip (onboard wizard)..."
      New-Item -Path $paperclipDir -ItemType Directory -Force | Out-Null
      Push-Location $paperclipDir
      npx paperclipai onboard --yes
      Pop-Location
      if (Test-Path $paperclipData) {
        Write-LabLog "Paperclip instalado (PG embebido, zero-config)."
      } else {
        Write-LabWarn "Paperclip: onboard completo pero ~/.paperclip no creado."
        Write-LabWarn "Si PG embebido fallo (exit 3221225781), verificar que VC++ Redistributable este instalado."
        Write-LabWarn "Modulo 01 lo instala automaticamente. Reintentar: npx paperclipai onboard --yes"
      }
    } else {
      Write-LabWarn "npx no disponible, no se puede instalar Paperclip."
    }
  } else {
    Write-LabLog "Paperclip ya instalado (~/.paperclip existe), saltando."
  }

  # Registrar en Servy
  if ((Test-Path $paperclipDir) -and (Get-Command servy -ErrorAction SilentlyContinue)) {
    $svcExists = servy list 2>$null | Select-String "Paperclip"
    if (-not $svcExists) {
      $npxPath = (Get-Command npx -ErrorAction SilentlyContinue).Source
      if ($npxPath) {
        Write-LabLog "Registrando Paperclip en Servy..."
        servy install --name "Paperclip" --path $npxPath --params "paperclipai start" --startupDir $paperclipDir --startupType Automatic --recoveryAction RestartProcess
      }
    }
  }
} else {
  Write-LabLog "Paperclip no solicitado, saltando."
}

# --- Odysseus -------------------------------------------------
if ($env:INSTALL_ODYSSEUS -eq "true") {
  $odysseusRepo = Join-Path $reposDir "odysseus"
  if (-not (Test-Path (Join-Path $odysseusRepo ".git"))) {
    Write-LabLog "Clonando Odysseus (fork Windows)..."
    git clone https://github.com/amish-github/odysseus.git $odysseusRepo
    if (-not (Test-Path (Join-Path $odysseusRepo ".git"))) {
      Write-LabWarn "Odysseus: clone fallo."
    }
  } else {
    Write-LabLog "Odysseus repo ya existe, actualizando..."
    Push-Location $odysseusRepo
    git pull --ff-only 2>$null
    Pop-Location
  }

  if ((Test-Path $odysseusRepo) -and (Get-Command uv -ErrorAction SilentlyContinue)) {
    $venvDir = Join-Path $odysseusRepo ".venv"
    if (-not (Test-Path $venvDir)) {
      Write-LabLog "Configurando entorno Odysseus..."
      Push-Location $odysseusRepo
      uv venv --python 3.12
      if (Test-Path "requirements.txt") {
        uv pip install -r requirements.txt
      } elseif (Test-Path "pyproject.toml") {
        uv pip install -e .
      }
      Pop-Location
      Write-LabLog "Odysseus configurado."
    } else {
      Write-LabLog "Odysseus venv ya existe, saltando setup."
    }

    # Registrar en Servy
    if (Get-Command servy -ErrorAction SilentlyContinue) {
      $svcExists = servy list 2>$null | Select-String "Odysseus"
      if (-not $svcExists) {
        $uvPath = (Get-Command uv -ErrorAction SilentlyContinue).Source
        Write-LabLog "Registrando Odysseus en Servy..."
        servy install --name "Odysseus" --path $uvPath --params "run python -m odysseus" --startupDir $odysseusRepo --startupType Automatic --recoveryAction RestartProcess
      }
    }
  }
} else {
  Write-LabLog "Odysseus no solicitado, saltando."
}

Write-LabLog "Modulo 04 completo."
