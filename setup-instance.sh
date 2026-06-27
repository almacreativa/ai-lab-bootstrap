#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
BOOTSTRAP_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_TAG="[setup-instance]"

log()  { echo "$LOG_TAG $*"; }
warn() { echo "$LOG_TAG WARN: $*"; }

usage() {
  echo "Uso: setup-instance.sh [--secrets secrets.age]"
  echo ""
  echo "Configura una instancia del lab después de correr bootstrap.sh."
  echo ""
  echo "Opciones:"
  echo "  --secrets FILE   Desencriptar secrets desde archivo age"
  echo "  --skip-backup    No configurar backup (útil para labs temporales)"
  echo "  --skip-services  No iniciar servicios systemd"
  echo "  -h, --help       Mostrar esta ayuda"
  exit 0
}

SECRETS_FILE=""
SKIP_BACKUP=false
SKIP_SERVICES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secrets) SECRETS_FILE="$2"; shift 2 ;;
    --skip-backup) SKIP_BACKUP=true; shift ;;
    --skip-services) SKIP_SERVICES=true; shift ;;
    -h|--help) usage ;;
    *) echo "Opción desconocida: $1"; usage ;;
  esac
done

echo "============================================"
echo "  setup-instance.sh — Configuración del lab"
echo "  $(date -Iseconds)"
echo "============================================"
echo ""

# -----------------------------------------------
# Paso 1: Secrets
# -----------------------------------------------
log "Paso 1/8: Secrets"

SCRIPTS_ENV="$LAB_DIR/scripts/.env"
HERMES_ENV="$HOME/.hermes/.env"

if [ -n "$SECRETS_FILE" ]; then
  if [ ! -f "$SECRETS_FILE" ]; then
    echo "$LOG_TAG ERROR: Archivo de secrets no encontrado: $SECRETS_FILE"
    exit 1
  fi

  if ! command -v age &>/dev/null; then
    echo "$LOG_TAG ERROR: age no instalado. Correr bootstrap.sh primero."
    exit 1
  fi

  log "Desencriptando secrets desde $SECRETS_FILE..."
  DECRYPTED=$(mktemp)
  trap 'shred -u "$DECRYPTED" 2>/dev/null; rm -f "$DECRYPTED"' EXIT

  if [ -f "$HOME/age-key.txt" ]; then
    age -d -i "$HOME/age-key.txt" -o "$DECRYPTED" "$SECRETS_FILE"
  else
    log "No se encontró ~/age-key.txt — solicitando passphrase"
    age -d -o "$DECRYPTED" "$SECRETS_FILE"
  fi

  log "Distribuyendo secrets a archivos .env..."

  mkdir -p "$(dirname "$SCRIPTS_ENV")"
  mkdir -p "$(dirname "$HERMES_ENV")"

  # Extraer variables por grupo
  extract_vars() {
    local prefix="$1"
    grep -E "^${prefix}" "$DECRYPTED" 2>/dev/null || true
  }

  # scripts/.env — backup, telegram, monitoring
  {
    echo "# Generado por setup-instance.sh — $(date -Iseconds)"
    extract_vars "B2_"
    extract_vars "RESTIC_"
    extract_vars "TELEGRAM_"
    extract_vars "UPTIME_KUMA_"
    extract_vars "KUMA_"
    extract_vars "CPU_TEMP_"
    extract_vars "CENTRO_"
  } > "$SCRIPTS_ENV"
  chmod 600 "$SCRIPTS_ENV"

  # hermes/.env — solo si hay variables de Hermes
  HERMES_VARS=$(extract_vars "OPENCODE_\|OLLAMA_\|MEM0_\|OUTLINE_\|PCP_\|DAGU_")
  if [ -n "$HERMES_VARS" ]; then
    {
      echo "# Generado por setup-instance.sh — $(date -Iseconds)"
      # Telegram también va a Hermes
      extract_vars "TELEGRAM_"
      echo "$HERMES_VARS"
    } > "$HERMES_ENV"
    chmod 600 "$HERMES_ENV"
    log "Secrets distribuidos a $SCRIPTS_ENV y $HERMES_ENV"
  else
    log "Secrets distribuidos a $SCRIPTS_ENV (sin variables de Hermes detectadas)"
  fi

else
  log "Sin archivo de secrets. Modo interactivo."
  echo "  Opciones:"
  echo "    a) Configurar secrets interactivamente ahora"
  echo "    b) Saltar — configurar manualmente después"
  echo ""
  read -r -p "  Elegir (a/b): " SECRETS_CHOICE

  if [[ "$SECRETS_CHOICE" =~ ^[aA]$ ]]; then
    mkdir -p "$(dirname "$SCRIPTS_ENV")"

    echo ""
    echo "  --- Telegram ---"
    read -r -p "  TELEGRAM_BOT_TOKEN: " TG_TOKEN
    read -r -p "  TELEGRAM_ALLOWED_USERS (chat_id): " TG_USERS

    echo ""
    echo "  --- Backup (B2 + restic) ---"
    read -r -p "  B2_ACCOUNT_ID: " B2_ID
    read -r -p "  B2_BACKUP_KEY: " B2_KEY
    read -r -p "  Nombre del bucket B2: " B2_BUCKET
    read -r -s -p "  RESTIC_PASSWORD: " RESTIC_PW
    echo ""

    {
      echo "# Generado por setup-instance.sh — $(date -Iseconds)"
      echo "TELEGRAM_BOT_TOKEN=${TG_TOKEN}"
      echo "TELEGRAM_ALLOWED_USERS=${TG_USERS}"
      echo "B2_ACCOUNT_ID=${B2_ID}"
      echo "B2_BACKUP_KEY=${B2_KEY}"
      echo "RESTIC_REPOSITORY=b2:${B2_BUCKET}"
      echo "RESTIC_PASSWORD=${RESTIC_PW}"
    } > "$SCRIPTS_ENV"
    chmod 600 "$SCRIPTS_ENV"
    log "Secrets escritos en $SCRIPTS_ENV"
  else
    log "Secrets saltados — configurar manualmente en $SCRIPTS_ENV"
  fi
fi

# -----------------------------------------------
# Paso 2: Backup
# -----------------------------------------------
log "Paso 2/8: Backup"

if [ "$SKIP_BACKUP" = true ]; then
  log "Backup saltado (--skip-backup)"
elif [ -f "$SCRIPTS_ENV" ] && grep -q "RESTIC_PASSWORD" "$SCRIPTS_ENV" 2>/dev/null; then
  source "$SCRIPTS_ENV"
  export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
  export B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-}"
  export B2_ACCOUNT_KEY="${B2_BACKUP_KEY:-}"
  export RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"

  if restic snapshots &>/dev/null 2>&1; then
    log "Repo restic ya existe y es accesible."
  else
    log "Inicializando repo restic..."
    restic init || warn "No se pudo inicializar el repo. Verificar credenciales."
  fi
else
  warn "No hay credenciales de backup en $SCRIPTS_ENV — saltar configuración de backup"
fi

# -----------------------------------------------
# Paso 3: Copiar ops/ al host
# -----------------------------------------------
log "Paso 3/8: Framework operativo (ops/)"

OPS_DEST="$LAB_DIR/ops"
mkdir -p "$OPS_DEST"/{guards,backup,manifests,runbooks}
mkdir -p "$LAB_DIR/logs/guard"

for subdir in guards backup manifests; do
  for script in "$BOOTSTRAP_DIR/ops/$subdir"/*.sh; do
    [ -f "$script" ] || continue
    cp "$script" "$OPS_DEST/$subdir/"
    chmod +x "$OPS_DEST/$subdir/$(basename "$script")"
  done
done

for runbook in "$BOOTSTRAP_DIR/ops/runbooks"/*.md; do
  [ -f "$runbook" ] || continue
  cp "$runbook" "$OPS_DEST/runbooks/"
done

log "ops/ copiado a $OPS_DEST ($(find "$OPS_DEST" -type f | wc -l) archivos)"

# -----------------------------------------------
# Paso 4: Generar core-manifest.yaml
# -----------------------------------------------
log "Paso 4/8: Core manifest"

if [ -x "$OPS_DEST/manifests/generate-core-manifest.sh" ]; then
  "$OPS_DEST/manifests/generate-core-manifest.sh"
  log "core-manifest.yaml generado"
else
  warn "generate-core-manifest.sh no encontrado"
fi

# -----------------------------------------------
# Paso 5: Instalar DAGs operativos
# -----------------------------------------------
log "Paso 5/8: DAGs operativos"

DAGS_DIR="$HOME/.config/dagu/dags"
mkdir -p "$DAGS_DIR"

for dag in "$BOOTSTRAP_DIR/configs/dagu-dags"/lab-*.yaml; do
  [ -f "$dag" ] || continue
  dagname=$(basename "$dag")
  if [ ! -f "$DAGS_DIR/$dagname" ]; then
    cp "$dag" "$DAGS_DIR/$dagname"
    log "DAG instalado: $dagname"
  else
    log "DAG ya existe: $dagname (no sobreescrito)"
  fi
done

# -----------------------------------------------
# Paso 6: Generar CLAUDE.md
# -----------------------------------------------
log "Paso 6/8: CLAUDE.md"

TEMPLATE="$BOOTSTRAP_DIR/templates/CLAUDE.md.template"
CLAUDE_MD="$HOME/CLAUDE.md"

if [ -f "$TEMPLATE" ]; then
  HOSTNAME_VAL=$(hostname)
  OS_VERSION=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Linux")
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "no configurado")
  LAB_USER=$(whoami)
  CORE_VERSION="1.0.0"
  GIT_NAME=$(git config user.name 2>/dev/null || echo "sin configurar")
  GIT_EMAIL=$(git config user.email 2>/dev/null || echo "sin configurar")

  # Generar tabla de servicios desde core-manifest.yaml
  SERVICES_TABLE=""
  MANIFEST_FILE="$LAB_DIR/ops/core-manifest.yaml"
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
" 2>/dev/null || echo "| (generar con generate-core-manifest.sh) | | |")
  fi

  sed -e "s|{{HOSTNAME}}|${HOSTNAME_VAL}|g" \
      -e "s|{{OS_VERSION}}|${OS_VERSION}|g" \
      -e "s|{{TAILSCALE_IP}}|${TAILSCALE_IP}|g" \
      -e "s|{{LAB_USER}}|${LAB_USER}|g" \
      -e "s|{{CORE_VERSION}}|${CORE_VERSION}|g" \
      -e "s|{{GIT_NAME}}|${GIT_NAME}|g" \
      -e "s|{{GIT_EMAIL}}|${GIT_EMAIL}|g" \
      "$TEMPLATE" > "$CLAUDE_MD.tmp"

  # Reemplazar SERVICES_TABLE (multilínea, sed no sirve)
  python3 -c "
content = open('${CLAUDE_MD}.tmp').read()
content = content.replace('{{SERVICES_TABLE}}', '''${SERVICES_TABLE}''')
open('${CLAUDE_MD}', 'w').write(content)
"
  rm -f "$CLAUDE_MD.tmp"
  log "CLAUDE.md generado en $CLAUDE_MD"
else
  warn "Template no encontrado: $TEMPLATE"
fi

# -----------------------------------------------
# Paso 7: Repo de instancia (<hostname>-lab)
# -----------------------------------------------
log "Paso 7/8: Repo de instancia"

INSTANCE_HOSTNAME=$(hostname -s)
INSTANCE_REPO_DIR="$LAB_DIR/repos/${INSTANCE_HOSTNAME}-lab"
INSTANCE_TEMPLATES="$BOOTSTRAP_DIR/templates/instance-repo"

if [ -d "$INSTANCE_REPO_DIR/.git" ]; then
  log "Repo ${INSTANCE_HOSTNAME}-lab ya existe — no se sobreescribe"
elif [ ! -d "$INSTANCE_TEMPLATES" ]; then
  warn "Templates de repo de instancia no encontrados en $INSTANCE_TEMPLATES"
else
  log "Creando repo ${INSTANCE_HOSTNAME}-lab..."

  HOSTNAME_VAL="$INSTANCE_HOSTNAME"
  CREATED_DATE=$(date +%Y-%m-%d)
  OS_VERSION_VAL=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Linux")
  TS_IP_VAL=$(tailscale ip -4 2>/dev/null || echo "no configurado")
  GIT_NAME_VAL=$(git config user.name 2>/dev/null || echo "sin configurar")
  GIT_EMAIL_VAL=$(git config user.email 2>/dev/null || echo "sin configurar")
  GIT_USER_VAL=$(echo "$GIT_EMAIL_VAL" | sed 's/@.*//')

  mkdir -p "$INSTANCE_REPO_DIR"/{docs,configs,stacks,scripts}

  for tmpl in "$INSTANCE_TEMPLATES"/*.template; do
    [ -f "$tmpl" ] || continue
    filename=$(basename "$tmpl" .template)
    # gitignore.template → .gitignore
    if [ "$filename" = "gitignore" ]; then
      dest="$INSTANCE_REPO_DIR/.gitignore"
    elif [ "$filename" = "CHANGELOG.md" ]; then
      dest="$INSTANCE_REPO_DIR/docs/CHANGELOG.md"
    else
      dest="$INSTANCE_REPO_DIR/$filename"
    fi
    sed -e "s|{{HOSTNAME}}|${HOSTNAME_VAL}|g" \
        -e "s|{{CREATED_DATE}}|${CREATED_DATE}|g" \
        -e "s|{{OS_VERSION}}|${OS_VERSION_VAL}|g" \
        -e "s|{{TAILSCALE_IP}}|${TS_IP_VAL}|g" \
        -e "s|{{GIT_NAME}}|${GIT_NAME_VAL}|g" \
        -e "s|{{GIT_EMAIL}}|${GIT_EMAIL_VAL}|g" \
        -e "s|{{GIT_USER}}|${GIT_USER_VAL}|g" \
        "$tmpl" > "$dest"
  done

  cd "$INSTANCE_REPO_DIR"
  if git config user.name &>/dev/null && git config user.email &>/dev/null; then
    git init -q
    git add -A
    git commit -q -m "init: repo de instancia ${INSTANCE_HOSTNAME}-lab"
    log "Repo creado en $INSTANCE_REPO_DIR"
  else
    git init -q
    warn "git user.name/email no configurados — repo inicializado pero sin commit."
    warn "Configurar con: git config --global user.name '...' && git config --global user.email '...'"
    warn "Luego: cd $INSTANCE_REPO_DIR && git add -A && git commit -m 'init: repo de instancia'"
  fi
  cd - > /dev/null
  log "Para publicar en GitHub (después de gh auth login):"
  log "  cd $INSTANCE_REPO_DIR"
  log "  gh repo create ${GIT_USER_VAL}/${INSTANCE_HOSTNAME}-lab --private --source=. --push"
fi

# -----------------------------------------------
# Paso 8: Servicios
# -----------------------------------------------
log "Paso 8/8: Servicios"

if [ "$SKIP_SERVICES" = true ]; then
  log "Inicio de servicios saltado (--skip-services)"
else
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

  for svc in dagu moolmesh centro-de-comando; do
    if systemctl --user is-enabled "${svc}.service" &>/dev/null 2>&1; then
      systemctl --user start "${svc}.service" 2>/dev/null && \
        log "Servicio iniciado: $svc" || \
        warn "No se pudo iniciar: $svc"
    fi
  done
fi

# -----------------------------------------------
# Resumen
# -----------------------------------------------
echo ""
echo "============================================"
echo "  Instancia configurada: $(hostname)"
echo "============================================"
echo ""
echo "  Secrets:     $([ -f "$SCRIPTS_ENV" ] && echo "$SCRIPTS_ENV (600)" || echo "no configurados")"
echo "  Manifest:    $LAB_DIR/ops/core-manifest.yaml"
echo "  Guards:      $LAB_DIR/ops/guards/"
echo "  Backup:      $LAB_DIR/ops/backup/lab-backup.sh"
echo "  Runbooks:    $LAB_DIR/ops/runbooks/"
echo "  CLAUDE.md:   $CLAUDE_MD"
echo "  Repo:        $LAB_DIR/repos/$(hostname -s)-lab/"
echo ""

TS_IP=$(tailscale ip -4 2>/dev/null || echo "100.x.x.x")
echo "  URLs (vía Tailscale $TS_IP):"
echo "    Dagu:        http://${TS_IP}:8480"
echo "    Uptime Kuma: http://${TS_IP}:3001"
echo "    Glance:      http://${TS_IP}:9000"
echo ""
echo "  Próximos pasos:"
echo "    1. Verificar: ~/ai-lab/ops/guards/core-guard.sh"
echo "    2. Probar backup: ~/ai-lab/ops/backup/lab-backup.sh"
echo "    3. Configurar Tailscale: sudo tailscale up --ssh"
echo ""
