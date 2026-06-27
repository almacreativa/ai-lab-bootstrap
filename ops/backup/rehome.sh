#!/usr/bin/env bash
set -euo pipefail

# rehome.sh — Adapta un lab restaurado a su nuevo entorno
#
# Después de restaurar un backup en una máquina diferente, este script
# reemplaza la IP de Tailscale y el hostname del lab original por los
# valores del nuevo host. Hace el backup verdaderamente portable.
#
# Uso:
#   rehome.sh                          # auto-detecta old IP/hostname del manifest
#   rehome.sh --old-ip 100.79.30.67    # especifica manualmente
#   rehome.sh --dry-run                # muestra qué cambiaría sin tocar nada
#
# Qué modifica:
#   - stacks/glance/config/glance.yml
#   - stacks/*/docker-compose.yml
#   - repos/paperclip/.env.paperclip
#   - .config/dagu/config.yaml
#   - Regenera CLAUDE.md y core-manifest.yaml

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
MANIFEST="$LAB_DIR/ops/core-manifest.yaml"
BOOTSTRAP_DIR="$LAB_DIR/repos/ai-lab-bootstrap"
LOG_TAG="[rehome]"
DRY_RUN=false
OLD_IP=""
OLD_HOSTNAME=""

log()  { echo "$LOG_TAG $*"; }
warn() { echo "$LOG_TAG WARN: $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --old-ip) OLD_IP="$2"; shift 2 ;;
    --old-hostname) OLD_HOSTNAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      echo "Uso: rehome.sh [--old-ip IP] [--old-hostname NAME] [--dry-run]"
      echo ""
      echo "Adapta configs del lab a la IP/hostname del nuevo host."
      echo "Auto-detecta valores originales del manifest si no se especifican."
      exit 0
      ;;
    *) echo "Opción desconocida: $1"; exit 1 ;;
  esac
done

# --- Detectar identidad NUEVA ---
NEW_IP=$(tailscale ip -4 2>/dev/null || echo "")
if [ -z "$NEW_IP" ]; then
  echo "$LOG_TAG ERROR: Tailscale no está activo. Correr 'sudo tailscale up' primero."
  exit 1
fi
NEW_HOSTNAME=$(hostname -s)

# --- Detectar identidad VIEJA (del manifest restaurado o del restore) ---
if [ -z "$OLD_IP" ] || [ -z "$OLD_HOSTNAME" ]; then
  # Buscar manifest en orden: restore reciente → manifest live
  CANDIDATE_MANIFESTS=(
    "$HOME/restore-test/home/"*"/ai-lab/ops/core-manifest.yaml"
    "$MANIFEST"
  )
  FOUND_MANIFEST=""
  for candidate in "${CANDIDATE_MANIFESTS[@]}"; do
    if [ -f "$candidate" ] 2>/dev/null; then
      FOUND_MANIFEST="$candidate"
      break
    fi
  done

  if [ -z "$FOUND_MANIFEST" ]; then
    echo "$LOG_TAG ERROR: No se encontró manifest (ni en restore-test ni en $MANIFEST)."
    echo "$LOG_TAG Usar --old-ip y --old-hostname manualmente."
    exit 1
  fi

  log "Leyendo identidad original de: $FOUND_MANIFEST"

  if [ -z "$OLD_HOSTNAME" ]; then
    OLD_HOSTNAME=$(python3 -c "
import yaml
with open('$FOUND_MANIFEST') as f:
    m = yaml.safe_load(f)
print(m.get('hostname', ''))
" 2>/dev/null || echo "")
  fi

  if [ -z "$OLD_IP" ]; then
    OLD_IP=$(python3 -c "
import yaml
with open('$FOUND_MANIFEST') as f:
    m = yaml.safe_load(f)
print(m.get('tailscale_ip', ''))
" 2>/dev/null || echo "")
  fi
fi

if [ -z "$OLD_IP" ]; then
  echo "$LOG_TAG ERROR: No se pudo detectar la IP original. Usar --old-ip"
  exit 1
fi

if [ "$OLD_IP" = "$NEW_IP" ] && [ "$OLD_HOSTNAME" = "$NEW_HOSTNAME" ]; then
  log "La identidad no cambió (IP: $NEW_IP, hostname: $NEW_HOSTNAME). Nada que hacer."
  exit 0
fi

echo "============================================"
echo "  rehome.sh — Adaptación de identidad"
echo "============================================"
echo ""
echo "  ORIGEN:   $OLD_HOSTNAME ($OLD_IP)"
echo "  DESTINO:  $NEW_HOSTNAME ($NEW_IP)"
echo ""

if [ "$DRY_RUN" = true ]; then
  log "Modo dry-run — solo muestra qué cambiaría"
  echo ""
fi

CHANGES=0

# --- Función de reemplazo ---
replace_in_file() {
  local file="$1"
  local old="$2"
  local new="$3"
  local desc="$4"

  if [ ! -f "$file" ]; then
    return
  fi

  if grep -q "$old" "$file" 2>/dev/null; then
    CHANGES=$((CHANGES + 1))
    if [ "$DRY_RUN" = true ]; then
      local count
      count=$(grep -c "$old" "$file" 2>/dev/null || echo "0")
      log "[dry-run] $desc: $count ocurrencias en $(basename "$file")"
    else
      sed -i "s|$old|$new|g" "$file"
      log "$desc: $(basename "$file") actualizado"
    fi
  fi
}

# --- 1. Glance ---
log "Verificando Glance..."
replace_in_file "$LAB_DIR/stacks/glance/config/glance.yml" \
  "$OLD_IP" "$NEW_IP" "Glance: IP de monitoreo"

# Glance docker-compose: network_mode: host → port mapping (evita conflictos de puerto)
GLANCE_COMPOSE="$LAB_DIR/stacks/glance/docker-compose.yml"
if [ -f "$GLANCE_COMPOSE" ] && grep -q "network_mode.*host" "$GLANCE_COMPOSE" 2>/dev/null; then
  GLANCE_PORT=$(grep -E "^\s*port:" "$LAB_DIR/stacks/glance/config/glance.yml" 2>/dev/null | awk '{print $2}' || echo "8080")
  [ -z "$GLANCE_PORT" ] && GLANCE_PORT="8080"
  CHANGES=$((CHANGES + 1))
  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] Glance: network_mode:host → ports 9000:${GLANCE_PORT}"
  else
    sed -i '/network_mode.*host/c\    ports:\n      - "9000:'"${GLANCE_PORT}"'"' "$GLANCE_COMPOSE"
    log "Glance: network_mode:host → ports 9000:${GLANCE_PORT}"
  fi
fi

# --- 2. Dagu config ---
log "Verificando Dagu..."
DAGU_CONFIG="$HOME/.config/dagu/config.yaml"
replace_in_file "$DAGU_CONFIG" "$OLD_IP" "$NEW_IP" "Dagu: host bind"
replace_in_file "$DAGU_CONFIG" "$OLD_HOSTNAME" "$NEW_HOSTNAME" "Dagu: navbar hostname"

# --- 3. Paperclip ---
log "Verificando Paperclip..."
PCP_ENV="$LAB_DIR/repos/paperclip/.env.paperclip"
replace_in_file "$PCP_ENV" "$OLD_IP" "$NEW_IP" "Paperclip: PUBLIC_URL"

# --- 4. Stacks con docker-compose ---
log "Verificando stacks Docker..."
while IFS= read -r compose_file; do
  [ -f "$compose_file" ] || continue
  replace_in_file "$compose_file" "$OLD_IP" "$NEW_IP" "Stack: $(dirname "$compose_file" | xargs basename)"
done < <(find "$LAB_DIR/stacks" -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null)

# --- 5. Tailscale DNS names (si existen) ---
if [ -n "$OLD_HOSTNAME" ]; then
  OLD_TS_DOMAIN="${OLD_HOSTNAME}.tail"
  NEW_TS_DOMAIN="${NEW_HOSTNAME}.tail"
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    if grep -q "$OLD_TS_DOMAIN" "$file" 2>/dev/null; then
      CHANGES=$((CHANGES + 1))
      if [ "$DRY_RUN" = true ]; then
        log "[dry-run] Tailscale DNS: $(basename "$file")"
      else
        sed -i "s|${OLD_HOSTNAME}\.tail[a-z0-9]*\.ts\.net|${NEW_HOSTNAME}.TAILSCALE_DOMAIN|g" "$file"
        log "Tailscale DNS: $(basename "$file") — REVISAR manualmente el dominio .ts.net"
      fi
    fi
  done < <(find "$LAB_DIR/stacks" -name "*.yml" -o -name "*.yaml" -o -name ".env*" 2>/dev/null)
fi

# --- 6. Regenerar archivos dinámicos ---
log "Regenerando archivos dinámicos..."

if [ "$DRY_RUN" = false ]; then
  # Regenerar manifest
  if [ -x "$LAB_DIR/ops/manifests/generate-core-manifest.sh" ]; then
    "$LAB_DIR/ops/manifests/generate-core-manifest.sh" 2>/dev/null
    log "core-manifest.yaml regenerado"
    CHANGES=$((CHANGES + 1))
  fi

  # Regenerar CLAUDE.md (via setup-instance.sh logic)
  TEMPLATE="$BOOTSTRAP_DIR/templates/CLAUDE.md.template"
  if [ -f "$TEMPLATE" ]; then
    OS_VERSION=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Linux")
    LAB_USER=$(whoami)
    CORE_VERSION="1.0.0"
    GIT_NAME=$(git config user.name 2>/dev/null || echo "sin configurar")
    GIT_EMAIL=$(git config user.email 2>/dev/null || echo "sin configurar")

    MANIFEST_FILE="$LAB_DIR/ops/core-manifest.yaml"
    SERVICES_TABLE=""
    if [ -f "$MANIFEST_FILE" ]; then
      SERVICES_TABLE=$(python3 -c "
import yaml
with open('$MANIFEST_FILE') as f:
    m = yaml.safe_load(f)
lines = ['| Servicio | Puerto | Estado |', '|---|---|---|']
for s in m.get('services', {}).get('systemd_user', []):
    name = s['name'].replace('.service','')
    lines.append(f'| {name} | systemd | {s[\"status\"]} |')
for c in m.get('services', {}).get('docker', []):
    lines.append(f'| {c[\"name\"]} | docker | {c[\"status\"]} |')
print('\n'.join(lines))
" 2>/dev/null || echo "| (regenerar manifest) | | |")
    fi

    CLAUDE_MD="$HOME/CLAUDE.md"
    sed -e "s|{{HOSTNAME}}|${NEW_HOSTNAME}|g" \
        -e "s|{{OS_VERSION}}|${OS_VERSION}|g" \
        -e "s|{{TAILSCALE_IP}}|${NEW_IP}|g" \
        -e "s|{{LAB_USER}}|${LAB_USER}|g" \
        -e "s|{{CORE_VERSION}}|${CORE_VERSION}|g" \
        -e "s|{{GIT_NAME}}|${GIT_NAME}|g" \
        -e "s|{{GIT_EMAIL}}|${GIT_EMAIL}|g" \
        "$TEMPLATE" > "$CLAUDE_MD.tmp"

    python3 -c "
content = open('${CLAUDE_MD}.tmp').read()
content = content.replace('{{SERVICES_TABLE}}', '''${SERVICES_TABLE}''')
open('${CLAUDE_MD}', 'w').write(content)
"
    rm -f "$CLAUDE_MD.tmp"
    log "CLAUDE.md regenerado"
    CHANGES=$((CHANGES + 1))
  fi
else
  log "[dry-run] Regeneraría: core-manifest.yaml, CLAUDE.md"
  CHANGES=$((CHANGES + 2))
fi

# --- Resumen ---
echo ""
echo "============================================"
if [ "$DRY_RUN" = true ]; then
  echo "  Dry-run: $CHANGES cambios detectados"
else
  echo "  Rehome completo: $CHANGES cambios aplicados"
fi
echo "============================================"
echo ""

if [ "$DRY_RUN" = false ] && [ $CHANGES -gt 0 ]; then
  echo "  Acciones post-rehome:"
  echo "    1. Reiniciar servicios Docker: docker compose up -d (en cada stack)"
  echo "    2. Reiniciar Dagu: systemctl --user restart dagu"
  echo "    3. Reiniciar Glance: docker restart glance"
  echo "    4. Verificar: ~/ai-lab/ops/guards/core-guard.sh"
  echo ""
  echo "  Revisar manualmente:"
  echo "    - Uptime Kuma monitors (viven en su DB, no en archivos)"
  echo "    - Outline OIDC config (si usa redirect URLs con IP)"
  echo "    - Tailscale serve rules: sudo tailscale serve status"
  echo ""
fi
