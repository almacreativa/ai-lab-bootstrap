# Módulo 02 (Windows host) — Provisionar WSL2/Ubuntu y delegar el setup al
# bootstrap.sh de Linux (casi sin cambios) corriendo dentro de la distro

Write-LabLog "Paso 2/3 — WSL2..."

$distro = "Ubuntu"

# wsl --list emite UTF-16 con bytes nulos al capturarse — se limpian antes de comparar
$existing = (wsl --list --quiet 2>$null) -replace "`0", "" | Where-Object { $_.Trim() -eq $distro }
if (-not $existing) {
  Write-LabLog "Instalando WSL2 con distro $distro..."
  wsl --install -d $distro --no-launch
  Write-LabWarn "Si es la primera instalación de WSL2, puede pedir reiniciar."
  Write-LabWarn "Tras reiniciar, abrir la app 'Ubuntu' una vez para crear el usuario Linux,"
  Write-LabWarn "y volver a correr bootstrap-windows.ps1."
  exit 0
} else {
  Write-LabLog "Distro $distro ya existe."
}

# systemd dentro de WSL2 — necesario para reusar hermes.service tal cual
$wslConfCheck = wsl -d $distro -- bash -c "grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null && echo yes || echo no"
if ($wslConfCheck.Trim() -eq "no") {
  wsl -d $distro -- bash -c "echo -e '[boot]\nsystemd=true' | sudo tee /etc/wsl.conf > /dev/null"
  Write-LabWarn "systemd habilitado en /etc/wsl.conf — reiniciando la distro para aplicar..."
  wsl --shutdown
  Start-Sleep -Seconds 5
} else {
  Write-LabLog "systemd ya habilitado en $distro."
}

# Clonar (o actualizar) el repo dentro de la distro y correr el bootstrap Linux
$labUserLinux = $env:LAB_USER_LINUX
if (-not $labUserLinux) { $labUserLinux = wsl -d $distro -- whoami }
$labUserLinux = $labUserLinux.Trim()

Write-LabLog "Clonando/actualizando ai-lab-bootstrap dentro de $distro (usuario: $labUserLinux)..."
wsl -d $distro -- bash -c "
  if [ ! -d ~/ai-lab-bootstrap/.git ]; then
    git clone https://github.com/almacreativa/ai-lab-bootstrap.git ~/ai-lab-bootstrap
  else
    git -C ~/ai-lab-bootstrap pull --ff-only
  fi
"

Write-LabLog "Lanzando bootstrap.sh dentro de WSL2 (esto puede tardar varios minutos)..."
Write-LabWarn "Vas a ver prompts interactivos dentro de la terminal de WSL2 (confirmación inicial)."
wsl -d $distro -- bash -lc "cd ~/ai-lab-bootstrap && bash bootstrap.sh"

Write-LabLog "Módulo 02 (Windows host) completo."
