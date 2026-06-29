#!/usr/bin/env bash
set -euo pipefail

# Escanea el sistema y genera ~/ai-lab/ops/core-manifest.yaml
# Este manifiesto es la fuente de verdad para core-guard.sh

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
MANIFEST="$LAB_DIR/ops/core-manifest.yaml"

mkdir -p "$(dirname "$MANIFEST")"

HOSTNAME=$(hostname)
GENERATED=$(date -Iseconds)

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "not configured")

cat > "$MANIFEST" << HEADER
# core-manifest.yaml — generado automáticamente por generate-core-manifest.sh
# NO editar a mano — regenerar con: ~/ai-lab/ops/manifests/generate-core-manifest.sh
generated: "${GENERATED}"
hostname: "${HOSTNAME}"
tailscale_ip: "${TAILSCALE_IP}"
core_version: "1.0.0"

HEADER

# Binarios en ~/.local/bin/
echo "binaries:" >> "$MANIFEST"
if [ -d "$HOME/.local/bin" ]; then
  for bin in "$HOME/.local/bin"/*; do
    [ -f "$bin" ] || [ -L "$bin" ] || continue
    name=$(basename "$bin")
    # Saltar archivos .old y similares
    [[ "$name" == *.old* ]] && continue
    version=$("$bin" --version 2>/dev/null | head -1 || "$bin" version 2>/dev/null | head -1 || echo "unknown")
    version=$(echo "$version" | head -c 80)
    echo "  - name: \"${name}\"" >> "$MANIFEST"
    echo "    path: \"${bin}\"" >> "$MANIFEST"
    echo "    version: \"${version}\"" >> "$MANIFEST"
  done
fi

# Servicios systemd user habilitados (solo .service, no sockets/timers)
echo "" >> "$MANIFEST"
echo "services:" >> "$MANIFEST"
echo "  systemd_user:" >> "$MANIFEST"
if systemctl --user list-unit-files --state=enabled --type=service --no-pager --no-legend 2>/dev/null; then
  :
fi | while read -r unit state _; do
  echo "    - name: \"${unit}\"" >> "$MANIFEST"
  if systemctl --user is-active "$unit" &>/dev/null; then
    echo "      status: \"active\"" >> "$MANIFEST"
  else
    echo "      status: \"inactive\"" >> "$MANIFEST"
  fi
done

# Servicios systemd system del lab (hermes, dagu — no todos los del sistema)
echo "  systemd_system:" >> "$MANIFEST"
for unit in hermes.service dagu.service; do
  if systemctl list-unit-files "$unit" --no-pager --no-legend 2>/dev/null | grep -q "$unit"; then
    echo "    - name: \"${unit}\"" >> "$MANIFEST"
    if systemctl is-active "$unit" &>/dev/null; then
      echo "      status: \"active\"" >> "$MANIFEST"
    else
      echo "      status: \"inactive\"" >> "$MANIFEST"
    fi
  fi
done

# Containers Docker corriendo
echo "  docker:" >> "$MANIFEST"
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null | while IFS=$'\t' read -r name image status; do
  echo "    - name: \"${name}\"" >> "$MANIFEST"
  echo "      image: \"${image}\"" >> "$MANIFEST"
  echo "      status: \"running\"" >> "$MANIFEST"
done

# Redes Docker custom
echo "" >> "$MANIFEST"
echo "networks:" >> "$MANIFEST"
docker network ls --format '{{.Name}}\t{{.Driver}}' 2>/dev/null | grep -v -E '^(bridge|host|none)\t' | while IFS=$'\t' read -r name driver; do
  echo "  - name: \"${name}\"" >> "$MANIFEST"
  echo "    driver: \"${driver}\"" >> "$MANIFEST"
done

# DAGs de Dagu
echo "" >> "$MANIFEST"
echo "dags:" >> "$MANIFEST"
if [ -d "$HOME/.config/dagu/dags" ]; then
  for dag in "$HOME/.config/dagu/dags"/*.yaml; do
    [ -f "$dag" ] || continue
    echo "  - \"$(basename "$dag")\"" >> "$MANIFEST"
  done
fi

# Estado del backup
echo "" >> "$MANIFEST"
echo "backup:" >> "$MANIFEST"
if [ -f "$LAB_DIR/scripts/.env" ] && grep -q "RESTIC_PASSWORD" "$LAB_DIR/scripts/.env" 2>/dev/null; then
  echo "  configured: true" >> "$MANIFEST"
  source "$LAB_DIR/scripts/.env" 2>/dev/null || true
  if [ -z "${RESTIC_REPOSITORY:-}" ]; then
    RESTIC_REPOSITORY=$(grep -h '^RESTIC_REPO=' "$LAB_DIR/scripts/lab-backup.sh" "$LAB_DIR/ops/backup/lab-backup.sh" 2>/dev/null | head -1 | cut -d'"' -f2 || true)
  fi
  export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
  export B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-}"
  export B2_ACCOUNT_KEY="${B2_BACKUP_KEY:-}"
  export RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"
  LAST_SNAP=$(restic snapshots --latest 1 --json 2>/dev/null | python3 -c "import json,sys; s=json.load(sys.stdin); print(s[0]['time'][:19] if s else 'none')" 2>/dev/null || echo "unknown")
  echo "  last_snapshot: \"${LAST_SNAP}\"" >> "$MANIFEST"
else
  echo "  configured: false" >> "$MANIFEST"
fi

# Software de sistema
echo "" >> "$MANIFEST"
echo "system:" >> "$MANIFEST"
echo "  os: \"$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')\"" >> "$MANIFEST"
echo "  docker: \"$(docker --version 2>/dev/null | head -1)\"" >> "$MANIFEST"
echo "  python: \"$(python3 --version 2>&1)\"" >> "$MANIFEST"
echo "  node: \"$(node --version 2>/dev/null || echo 'not installed')\"" >> "$MANIFEST"
echo "  tailscale: \"$(tailscale version 2>/dev/null | head -1 || echo 'not installed')\"" >> "$MANIFEST"

echo "[generate-core-manifest] Manifiesto generado en $MANIFEST"
