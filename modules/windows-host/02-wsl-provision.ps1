# Modulo 02 (Windows host) -- Provisionar WSL2/Ubuntu y delegar el setup al
# bootstrap.sh de Linux corriendo dentro de la distro.
# Docker CE se instala dentro de WSL2 (no Docker Desktop).
#
# IMPORTANTE: los comandos bash se pasan en una sola linea para evitar
# problemas con CRLF (los .ps1 en Windows tienen \r\n, y bash interpreta
# el \r como $'\r': command not found).

Write-LabLog "Paso 2/4 -- WSL2..."

$distro = "Ubuntu"

# wsl --list emite UTF-16 con bytes nulos al capturarse -- se limpian antes de comparar
$existing = (wsl --list --quiet 2>$null) -replace "`0", "" | Where-Object { $_.Trim() -eq $distro }
if (-not $existing) {
  Write-LabLog "Instalando WSL2 con distro $distro..."
  wsl --install -d $distro --no-launch
  Write-LabWarn "Si es la primera instalacion de WSL2, puede pedir reiniciar."
  Write-LabWarn "Tras reiniciar, abrir la app 'Ubuntu' una vez para crear el usuario Linux,"
  Write-LabWarn "y volver a correr bootstrap-windows.ps1."
  exit 0
} else {
  Write-LabLog "Distro $distro ya existe."
}

# systemd dentro de WSL2 -- necesario para hermes.service y docker.service
$wslConfCheck = wsl -d $distro -- bash -c "grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null && echo yes || echo no"
if ($wslConfCheck.Trim() -eq "no") {
  wsl -d $distro -- bash -c "echo -e '[boot]\nsystemd=true' | sudo tee /etc/wsl.conf > /dev/null"
  Write-LabWarn "systemd habilitado en /etc/wsl.conf -- reiniciando la distro para aplicar..."
  wsl --shutdown
  Start-Sleep -Seconds 10
  Write-LabLog "WSL2 reiniciado. Esperando que la distro este lista..."
  wsl -d $distro -- bash -c "echo ok" 2>$null | Out-Null
} else {
  Write-LabLog "systemd ya habilitado en $distro."
}

# Detectar usuario Linux
$labUserLinux = $env:LAB_USER_LINUX
if (-not $labUserLinux) { $labUserLinux = wsl -d $distro -- whoami }
$labUserLinux = $labUserLinux.Trim()

# Clonar (o actualizar) el repo dentro de la distro
Write-LabLog "Clonando/actualizando ai-lab-bootstrap dentro de $distro (usuario: $labUserLinux)..."
wsl -d $distro -- bash -c "mkdir -p ~/ai-lab/repos && if [ ! -d ~/ai-lab/repos/ai-lab-bootstrap/.git ]; then git clone https://github.com/almacreativa/ai-lab-bootstrap.git ~/ai-lab/repos/ai-lab-bootstrap; else git -C ~/ai-lab/repos/ai-lab-bootstrap pull --ff-only 2>/dev/null || true; fi"

# Verificar que el clone funciono
$repoCheck = wsl -d $distro -- bash -c "[ -d ~/ai-lab/repos/ai-lab-bootstrap/.git ] && echo ok || echo fail"
if ($repoCheck.Trim() -ne "ok") {
  Write-LabErr "No se pudo clonar ai-lab-bootstrap dentro de WSL2. Verificar conectividad y git."
}

# Preparar variables para el bootstrap Linux
$installPaperclip = if ($env:INSTALL_PAPERCLIP) { $env:INSTALL_PAPERCLIP } else { "true" }
$installHermes    = if ($env:INSTALL_HERMES)    { $env:INSTALL_HERMES }    else { "true" }
$installNlm       = if ($env:INSTALL_NLM)       { $env:INSTALL_NLM }       else { "true" }

Write-LabLog "Lanzando bootstrap.sh dentro de WSL2 (esto puede tardar varios minutos)..."
Write-LabLog "  INSTALL_PAPERCLIP=$installPaperclip  INSTALL_HERMES=$installHermes  INSTALL_NLM=$installNlm"
Write-LabWarn "Vas a ver prompts interactivos dentro de la terminal de WSL2 (confirmacion inicial)."

wsl -d $distro -- bash -lc "export INSTALL_PAPERCLIP=$installPaperclip && export INSTALL_HERMES=$installHermes && export INSTALL_NLM=$installNlm && cd ~/ai-lab/repos/ai-lab-bootstrap && bash bootstrap.sh"

if ($LASTEXITCODE -ne 0) {
  Write-LabWarn "bootstrap.sh termino con errores (exit code: $LASTEXITCODE)."
  Write-LabWarn "Revisar el output arriba. Se puede re-ejecutar manualmente:"
  Write-LabWarn "  wsl -d Ubuntu -- bash -lc 'cd ~/ai-lab/repos/ai-lab-bootstrap && bash bootstrap.sh'"
}

Write-LabLog "Modulo 02 (Windows host) completo."
