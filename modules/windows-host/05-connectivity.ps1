# Modulo 05 -- Conectividad: Firewall rules Tailscale, verificar red,
# crear .env templates

$ErrorActionPreference = "Continue"

Write-LabLog "Paso 5/6 -- Conectividad..."

# --- Firewall rules para interfaz Tailscale -------------------
Write-LabLog "Configurando firewall para servicios AI Lab..."

$ports = @(9119, 5200, 8480, 3001, 5678, 3100, 7000)

foreach ($port in $ports) {
  $ruleName = "AI-Lab-$port"
  $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
  if (-not $existing) {
    try {
      New-NetFirewallRule -DisplayName $ruleName `
        -Direction Inbound -Protocol TCP -LocalPort $port `
        -InterfaceAlias "Tailscale" -Action Allow | Out-Null
      Write-LabLog "Firewall rule: $ruleName (TCP $port, Tailscale)."
    } catch {
      # Puede fallar si Tailscale no esta configurado aun
      New-NetFirewallRule -DisplayName $ruleName `
        -Direction Inbound -Protocol TCP -LocalPort $port `
        -Action Allow | Out-Null
      Write-LabWarn "Firewall rule: $ruleName creada sin filtro de interfaz (Tailscale no detectada)."
    }
  }
}

# --- Verificar Tailscale --------------------------------------
$tailscaleStatus = $null
if (Get-Command tailscale -ErrorAction SilentlyContinue) {
  $tailscaleStatus = tailscale status 2>$null
  if ($tailscaleStatus) {
    Write-LabLog "Tailscale activo."
  } else {
    Write-LabWarn "Tailscale instalado pero no conectado. Ejecutar: tailscale up"
  }
} else {
  Write-LabWarn "Tailscale no instalado. Instalar y conectar para acceso remoto."
}

# --- Templates de .env ----------------------------------------
$hermesEnvDir = Join-Path $env:USERPROFILE ".hermes"
$hermesEnvFile = Join-Path $hermesEnvDir ".env"
$agentsEnvFile = Join-Path $env:USERPROFILE ".env_agents"

# .hermes/.env
if (-not (Test-Path $hermesEnvFile)) {
  New-Item -Path $hermesEnvDir -ItemType Directory -Force | Out-Null
  $hermesTemplate = @'
# Hermes Agent -- secrets (no commitear)
TELEGRAM_BOT_TOKEN=
TELEGRAM_ALLOWED_USER_IDS=
ANTHROPIC_API_KEY=
'@
  Set-Content -Path $hermesEnvFile -Value $hermesTemplate -Encoding UTF8
  Write-LabLog "Template creado: $hermesEnvFile (completar manualmente)."
} else {
  Write-LabLog ".hermes/.env ya existe, no se sobreescribe."
}

# .env_agents
if (-not (Test-Path $agentsEnvFile)) {
  $agentsTemplate = @'
# API keys compartidas entre agentes (no commitear)
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
SEARXNG_URL=
'@
  Set-Content -Path $agentsEnvFile -Value $agentsTemplate -Encoding UTF8
  Write-LabLog "Template creado: $agentsEnvFile (completar manualmente)."
} else {
  Write-LabLog ".env_agents ya existe, no se sobreescribe."
}

Write-LabLog "Modulo 05 completo."
