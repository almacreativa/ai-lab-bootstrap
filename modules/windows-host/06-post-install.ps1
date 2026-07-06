# Modulo 06 -- Reporte de estado + pasos manuales post-bootstrap

# --- Reporte de estado -------------------------------------------
Write-Host ""
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "  REPORTE DE INSTALACION" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host ""

$report = @()
$hasErrors = $false

# Binarios
$bins = @(
  @{ Name = "Scoop";       Cmd = "scoop" },
  @{ Name = "Git";         Cmd = "git" },
  @{ Name = "Node.js";     Cmd = "node" },
  @{ Name = "uv";          Cmd = "uv" },
  @{ Name = "GitHub CLI";  Cmd = "gh" },
  @{ Name = "psmux";       Cmd = "psmux" },
  @{ Name = "Servy";       Cmd = "servy" },
  @{ Name = "Tailscale";   Cmd = "tailscale" }
)

foreach ($bin in $bins) {
  $found = Get-Command $bin.Cmd -ErrorAction SilentlyContinue
  if ($found) {
    $ver = ""
    try { $ver = & $bin.Cmd --version 2>$null | Select-Object -First 1 } catch {}
    $report += @{ Name = $bin.Name; Status = "OK"; Detail = $ver }
  } else {
    $report += @{ Name = $bin.Name; Status = "FALTA"; Detail = "" }
    $hasErrors = $true
  }
}

# Python 3.12 (instalado via uv, no pone 'python' en PATH)
$py312Check = $null
if (Get-Command uv -ErrorAction SilentlyContinue) {
  $py312Check = uv python list 2>$null | Select-String "3\.12"
}
if ($py312Check) {
  $report += @{ Name = "Python 3.12"; Status = "OK"; Detail = "via uv" }
} else {
  $report += @{ Name = "Python 3.12"; Status = "FALTA"; Detail = "" }
  $hasErrors = $true
}

# Agentes
$agents = @(
  @{ Name = "Claude Code"; Cmd = "claude" },
  @{ Name = "OpenCode";    Cmd = "opencode" },
  @{ Name = "Engram";      Cmd = "engram" },
  @{ Name = "MoolMesh";    Cmd = "mool" }
)

foreach ($agent in $agents) {
  $found = Get-Command $agent.Cmd -ErrorAction SilentlyContinue
  if ($found) {
    $report += @{ Name = $agent.Name; Status = "OK"; Detail = "" }
  } else {
    $report += @{ Name = $agent.Name; Status = "FALTA"; Detail = "" }
    $hasErrors = $true
  }
}

# NotebookLM MCP (paquete: notebooklm-mcp-cli, CLI: nlm)
if ($env:INSTALL_NLM -eq "true") {
  $nlmFound = Get-Command nlm -ErrorAction SilentlyContinue
  if (-not $nlmFound -and (Get-Command uv -ErrorAction SilentlyContinue)) {
    $nlmCheck = uv tool list 2>$null | Select-String "notebooklm-mcp-cli"
    if ($nlmCheck) { $nlmFound = $true }
  }
  if ($nlmFound) {
    $nlmVer = ""
    try { $nlmVer = nlm --version 2>$null } catch {}
    $report += @{ Name = "nlm (NLM MCP)"; Status = "OK"; Detail = $nlmVer }
  } else {
    $report += @{ Name = "nlm (NLM MCP)"; Status = "FALTA"; Detail = "" }
    $hasErrors = $true
  }
}

# Servicios opcionales (verificar por directorio/archivo)
$optServices = @()
if ($env:INSTALL_DAGU -eq "true") {
  $daguOk = Get-Command dagu -ErrorAction SilentlyContinue
  $optServices += @{ Name = "Dagu"; Status = $(if ($daguOk) { "OK" } else { "FALTA" }); Detail = "" }
}
if ($env:INSTALL_HERMES -eq "true") {
  $hermesRepo = Join-Path $env:USERPROFILE "ai-lab\repos\hermes-agent"
  $hermesOk = Test-Path (Join-Path $hermesRepo ".venv")
  $optServices += @{ Name = "Hermes Agent"; Status = $(if ($hermesOk) { "OK" } else { "FALTA" }); Detail = "" }
}
if ($env:INSTALL_UPTIME_KUMA -eq "true") {
  $kumaOk = Test-Path (Join-Path $env:USERPROFILE "ai-lab\apps\uptime-kuma\package.json")
  $optServices += @{ Name = "Uptime Kuma"; Status = $(if ($kumaOk) { "OK" } else { "FALTA" }); Detail = "" }
}
if ($env:INSTALL_GLANCE -eq "true") {
  $glanceOk = Test-Path (Join-Path $env:USERPROFILE "ai-lab\apps\glance\glance.exe")
  $optServices += @{ Name = "Glance"; Status = $(if ($glanceOk) { "OK" } else { "FALTA" }); Detail = "" }
}
if ($env:INSTALL_PAPERCLIP -eq "true") {
  $paperclipOk = Test-Path (Join-Path $env:USERPROFILE ".paperclip")
  $optServices += @{ Name = "Paperclip"; Status = $(if ($paperclipOk) { "OK" } else { "FALTA" }); Detail = "" }
}
if ($env:INSTALL_ODYSSEUS -eq "true") {
  $odysseusOk = Test-Path (Join-Path $env:USERPROFILE "ai-lab\repos\odysseus\.venv")
  $optServices += @{ Name = "Odysseus"; Status = $(if ($odysseusOk) { "OK" } else { "FALTA" }); Detail = "" }
}

foreach ($svc in $optServices) {
  $report += $svc
  if ($svc.Status -eq "FALTA") { $hasErrors = $true }
}

# Servy services (registrados como Windows services)
$servyServices = @()
$knownServices = @("Dagu","HermesGateway","HermesDashboard","MoolMesh","UptimeKuma","Glance","Paperclip","Odysseus")
foreach ($svc in $knownServices) {
  $winSvc = Get-Service -Name $svc -ErrorAction SilentlyContinue
  if ($winSvc) {
    $servyServices += "$svc ($($winSvc.Status))"
  }
}

# Imprimir reporte
Write-Host "  COMPONENTE              ESTADO    DETALLE" -ForegroundColor White
Write-Host "  ---------               ------    -------" -ForegroundColor DarkGray
foreach ($item in $report) {
  $color = if ($item.Status -eq "OK") { "Green" } else { "Red" }
  $name = $item.Name.PadRight(24)
  $status = $item.Status.PadRight(10)
  $detail = if ($item.Detail) { $item.Detail } else { "" }
  Write-Host "  $name$status$detail" -ForegroundColor $color
}

Write-Host ""
if ($servyServices.Count -gt 0) {
  Write-Host "  Servicios Servy registrados ($($servyServices.Count)):" -ForegroundColor White
  foreach ($line in $servyServices) {
    Write-Host "    - $line"
  }
} else {
  if (Get-Command servy -ErrorAction SilentlyContinue) {
    Write-Host "  Servicios Servy: ninguno registrado aun." -ForegroundColor Yellow
  } else {
    Write-Host "  Servy no disponible -- servicios no registrados." -ForegroundColor Red
  }
}

Write-Host ""
if ($hasErrors) {
  Write-Host "  ** Hay componentes faltantes. Revisar errores arriba. **" -ForegroundColor Red
} else {
  Write-Host "  Todos los componentes instalados correctamente." -ForegroundColor Green
}

# --- Pasos manuales ----------------------------------------------
Write-Host ""
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "  PASOS MANUALES REQUERIDOS" -ForegroundColor Yellow
Write-Host "  (no se pueden automatizar -- requieren interaccion)"
Write-Host ""
Write-Host "  -- 1. TAILSCALE -------------------------------------------------"
Write-Host "     Abrir Tailscale desde el menu de inicio y hacer login."
Write-Host "     Verificar: tailscale status"
Write-Host ""
Write-Host "  -- 2. SECRETS ----------------------------------------------------"
Write-Host "     Completar los archivos de secrets creados:"
Write-Host "       %USERPROFILE%\.hermes\.env      (Telegram token, user IDs)"
Write-Host "       %USERPROFILE%\.env_agents       (API keys, SearXNG URL)"
Write-Host ""
Write-Host "  -- 3. HERMES GATEWAY SETUP ---------------------------------------"
Write-Host "     cd %USERPROFILE%\ai-lab\repos\hermes-agent"
Write-Host "     uv run hermes gateway setup"
Write-Host "     (configura: Telegram bot, allowed users, modelo default)"
Write-Host ""
Write-Host "  -- 4. INICIAR SERVICIOS ------------------------------------------"
Write-Host "     servy start Dagu"
Write-Host "     servy start HermesGateway"
Write-Host "     servy start HermesDashboard"
Write-Host "     servy start MoolMesh"
Write-Host "     servy start UptimeKuma"
Write-Host "     servy start Glance"
Write-Host "     servy start Paperclip"
Write-Host "     servy start Odysseus"
Write-Host ""
Write-Host "     Verificar: servy status <nombre>"
Write-Host ""
Write-Host "  -- 5. HEALTH CHECKS ---------------------------------------------"
Write-Host "     curl http://localhost:9119/api/health    (Hermes)"
Write-Host "     curl http://localhost:5200/api/sessions  (MoolMesh)"
Write-Host "     curl http://localhost:8480               (Dagu)"
Write-Host "     curl http://localhost:3001               (Uptime Kuma)"
Write-Host "     curl http://localhost:5678               (Glance)"
Write-Host "     curl http://localhost:3100               (Paperclip)"
Write-Host "     curl http://localhost:7000               (Odysseus)"
Write-Host ""
Write-Host "  -- 6. LOGINS DE AGENTES -----------------------------------------"
Write-Host "     claude           <- completar login interactivo"
Write-Host "     nlm login        <- NotebookLM (abre Chromium)"
Write-Host "     gh auth login    <- GitHub CLI"
Write-Host ""
Write-Host "  -- 7. CONFIGURAR MCP SERVERS ------------------------------------"
Write-Host "     En Claude Code y OpenCode, configurar MCP:"
Write-Host "       MoolMesh:      localhost:5200"
Write-Host "       Engram:        stdio (binario local)"
Write-Host "       Playwright:    stdio (@playwright/mcp, headed)"
Write-Host "       NotebookLM:    stdio (nlm)"
Write-Host "       Paperclip:     localhost:3100"
Write-Host ""
Write-Host "  -- 8. DAGU ADMIN ------------------------------------------------"
Write-Host "     Abrir http://localhost:8480"
Write-Host "     Crear usuario admin si es primera vez."
Write-Host ""
Write-Host "  -- 9. UPTIME KUMA -----------------------------------------------"
Write-Host "     Abrir http://localhost:3001"
Write-Host "     Crear usuario admin, configurar monitors."
Write-Host ""
Write-Host "  MANTENIMIENTO:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  - Ver servicios:     servy status <nombre>"
Write-Host "  - Logs de servicio:  servy logs <nombre>"
Write-Host "  - Reiniciar:         servy restart <nombre>"
Write-Host "  - Detener:           servy stop <nombre>"
Write-Host ""
Write-Host "  - SearXNG es REMOTO (no soportado nativo Windows)."
Write-Host "    Configurar SEARXNG_URL en ~/.env_agents apuntando a una instancia."
Write-Host ""
Write-Host "  Guia detallada: docs/WINDOWS-INSTALL.md"
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host ""
