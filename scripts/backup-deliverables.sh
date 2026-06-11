#!/bin/bash
# Espejo de los entregables generados por los agentes de Paperclip
# hacia ~/alma/ops/deliverables/ en el host.
# Comportamiento: espejo exacto — archivos borrados o renombrados en el contenedor
# también desaparecen del host (rsync --delete vía directorio temporal).

set -euo pipefail

DEST="${HOME}/ai-lab/ops/deliverables"
CONTAINER="paperclip-server-1"
DB_CONTAINER="paperclip-db-1"
WORKSPACE_BASE="/paperclip/instances/default/workspaces"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

sync_dir() {
  local label="$1"
  local container_path="$2"
  local host_dest="$3"

  local tmp="$TMPDIR_BASE/$label"
  mkdir -p "$tmp" "$host_dest"

  # Extraer del contenedor a temp
  docker cp "$CONTAINER:$container_path/." "$tmp/" 2>/dev/null || return 0

  # Sincronizar con espejo exacto (borra en dest lo que ya no existe en origen)
  rsync -a --delete "$tmp/" "$host_dest/"
  echo "[sync] $label → $host_dest"
}

# Verificar que el contenedor esté corriendo
if ! docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
  echo "[sync] Contenedor $CONTAINER no está corriendo. Abortando."
  exit 1
fi

mkdir -p "$DEST"

# Sincronizar workspace de cada agente, SEPARADO POR EMPRESA (multi-tenant desde 2026-06-11):
#   <EmpresaA> (ALM)      → ~/alma/ops/deliverables/<agente>           (ruta histórica, sin romper wiki-ingest)
#   <EmpresaB> (EXP)  → ~/alma/ops/deliverables-<empresa-b>/<agente>
#   otras           → ~/alma/ops/deliverables-<prefijo>/<agente>
while IFS='|' read -r agent_name agent_id company_prefix; do
  agent_name=$(echo "$agent_name" | tr -d ' ')
  agent_id=$(echo "$agent_id" | tr -d ' ')
  company_prefix=$(echo "$company_prefix" | tr -d ' ')
  src="$WORKSPACE_BASE/$agent_id"

  case "$company_prefix" in
    ALM) company_dest="$DEST" ;;
    EXP) company_dest="${HOME}/ai-lab/ops/deliverables-<empresa-b>" ;;
    *)   company_dest="${HOME}/ai-lab/ops/deliverables-$(echo "$company_prefix" | tr '[:upper:]' '[:lower:]')" ;;
  esac

  if docker exec "$CONTAINER" test -d "$src" 2>/dev/null; then
    sync_dir "$agent_name" "$src" "$company_dest/$agent_name"
  fi
done < <(docker exec "$DB_CONTAINER" psql -U paperclip -d paperclip -tA \
  -c "SELECT a.name, a.id, c.issue_prefix FROM agents a JOIN companies c ON c.id = a.company_id ORDER BY a.name;")

# Sincronizar <empresa-a>-deliverables
if docker exec "$CONTAINER" test -d /paperclip/<empresa-a>-deliverables 2>/dev/null; then
  sync_dir "<empresa-a>-deliverables" "/paperclip/<empresa-a>-deliverables" "$DEST/<empresa-a>-deliverables"
fi

# Sincronizar <empresa-b>-deliverables (<EmpresaB>)
if docker exec "$CONTAINER" test -d /paperclip/<empresa-b>-deliverables 2>/dev/null; then
  sync_dir "<empresa-b>-deliverables" "/paperclip/<empresa-b>-deliverables" "${HOME}/ai-lab/ops/deliverables-<empresa-b>/<empresa-b>-deliverables"
fi

echo "[sync] Completado: $(date '+%Y-%m-%d %H:%M')"
