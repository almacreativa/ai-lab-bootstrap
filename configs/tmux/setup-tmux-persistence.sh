#!/bin/bash
# Configura persistencia de sesiones tmux: TPM + resurrect + continuum + systemd
# Uso: bash setup-tmux-persistence.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF="$HOME/.tmux.conf"
TPM_DIR="$HOME/.tmux/plugins/tpm"
SYSTEMD_DIR="$HOME/.config/systemd/user"

echo "==> Instalando TPM (Tmux Plugin Manager)..."
if [ -d "$TPM_DIR" ]; then
  echo "    TPM ya existe, actualizando..."
  git -C "$TPM_DIR" pull --quiet
else
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

echo "==> Instalando plugins (resurrect + continuum + assistant-resurrect)..."
for plugin in tmux-resurrect tmux-continuum; do
  dest="$HOME/.tmux/plugins/$plugin"
  if [ -d "$dest" ]; then
    echo "    $plugin ya existe, actualizando..."
    git -C "$dest" pull --quiet
  else
    git clone "https://github.com/tmux-plugins/$plugin" "$dest"
  fi
done

dest="$HOME/.tmux/plugins/tmux-assistant-resurrect"
if [ -d "$dest" ]; then
  echo "    tmux-assistant-resurrect ya existe, actualizando..."
  git -C "$dest" pull --quiet
else
  git clone "https://github.com/timvw/tmux-assistant-resurrect" "$dest"
fi

echo "==> Copiando tmux.conf..."
if [ -f "$TMUX_CONF" ]; then
  cp "$TMUX_CONF" "$TMUX_CONF.bak.$(date +%Y%m%d%H%M%S)"
  echo "    Backup creado: $TMUX_CONF.bak.*"
fi
cp "$SCRIPT_DIR/tmux.conf" "$TMUX_CONF"

echo "==> Configurando servicio systemd de usuario..."
mkdir -p "$SYSTEMD_DIR"
cp "$SCRIPT_DIR/tmux.service" "$SYSTEMD_DIR/tmux.service"

if command -v systemctl &>/dev/null; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  systemctl --user daemon-reload
  systemctl --user enable tmux.service
  echo "    Servicio tmux.service habilitado al boot."

  if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes"; then
    echo "    [!] Linger no está habilitado. Ejecuta manualmente:"
    echo "        sudo loginctl enable-linger $(whoami)"
  fi
else
  echo "    [!] systemctl no disponible, omitiendo servicio systemd."
fi

echo ""
echo "==> Listo. Próximos pasos:"
echo "    1. Si tmux está corriendo: tmux source-file ~/.tmux.conf"
echo "    2. Primer guardado manual: Ctrl+a luego Ctrl+s"
echo "    3. Verificar: ls ~/.tmux/resurrect/"
