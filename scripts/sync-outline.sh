#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"
KNOWLEDGE_DIR="$LAB_DIR/knowledge"
DOCS_DIR="$LAB_DIR/repos/i7local-lab/docs"
DELIVERABLES_BASE="$LAB_DIR/ops"
COLLECTIONS_FILE="$KNOWLEDGE_DIR/.outline-collections.env"

source "$HOME/.hermes/.env"
OUTLINE_URL="https://i7local.tailb4d2b2.ts.net/api"
CHECKSUMS_FILE="$KNOWLEDGE_DIR/.outline-checksums"
DOC_IDS_FILE="$KNOWLEDGE_DIR/.outline-doc-ids"

CREATED=0
UPDATED=0
SKIPPED=0
ERRORS=0
RETVAL=""

log() { echo "[sync-outline] $1"; }
err() { echo "[sync-outline] ERROR: $1" >&2; ERRORS=$((ERRORS + 1)); }

touch "$CHECKSUMS_FILE" "$DOC_IDS_FILE"

file_checksum() { md5sum "$1" | cut -d' ' -f1; }

get_saved_checksum() {
  RETVAL=$(grep -F "	$1	" "$CHECKSUMS_FILE" 2>/dev/null | cut -f1)
}

save_checksum() {
  local key="$1" hash="$2"
  local tab=$'\t'
  if grep -qF "${tab}${key}${tab}" "$CHECKSUMS_FILE" 2>/dev/null; then
    sed -i "\|${tab}${key}${tab}|s/^[a-f0-9]*/${hash}/" "$CHECKSUMS_FILE"
  else
    printf '%s\t%s\t\n' "$hash" "$key" >> "$CHECKSUMS_FILE"
  fi
}

get_doc_id() {
  RETVAL=$(grep -F "	$1	" "$DOC_IDS_FILE" 2>/dev/null | cut -f1)
}

save_doc_id() {
  local key="$1" doc_id="$2"
  local tab=$'\t'
  if grep -qF "${tab}${key}${tab}" "$DOC_IDS_FILE" 2>/dev/null; then
    sed -i "\|${tab}${key}${tab}|s/^[a-f0-9-]*/${doc_id}/" "$DOC_IDS_FILE"
  else
    printf '%s\t%s\t\n' "$doc_id" "$key" >> "$DOC_IDS_FILE"
  fi
}

filename_to_title() {
  local name="${1%.md}"
  name="${name//_/ }"
  name="${name//-/ }"
  RETVAL=$(echo "$name" | sed 's/\b\(.\)/\u\1/g')
}

outline_api() {
  RETVAL=$(curl -sf "${OUTLINE_URL}/$1" \
    -H "Authorization: Bearer $OUTLINE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$2" 2>/dev/null)
}

outline_find_doc() {
  local collection_id="$1" title="$2" parent_id="${3:-}"

  outline_api "documents.search" \
    "$(jq -n --arg q "$title" --arg cid "$collection_id" '{query: $q, collectionId: $cid}')"
  local search_result="$RETVAL"

  if [ -z "$search_result" ]; then
    RETVAL=""
    return
  fi

  if [ -n "$parent_id" ]; then
    RETVAL=$(echo "$search_result" | jq -r \
      --arg title "$title" --arg pid "$parent_id" \
      '[.data[]? | select(.document.title == $title and .document.parentDocumentId == $pid)] | .[0].document.id // empty')
  else
    RETVAL=$(echo "$search_result" | jq -r \
      --arg title "$title" \
      '[.data[]? | select(.document.title == $title and (.document.parentDocumentId == null or .document.parentDocumentId == ""))] | .[0].document.id // empty')
  fi
}

outline_create_or_update() {
  local collection_id="$1" title="$2" content="$3" parent_id="${4:-}"

  outline_find_doc "$collection_id" "$title" "$parent_id"
  local existing_id="$RETVAL"

  if [ -n "$existing_id" ]; then
    sleep 2
    outline_api "documents.update" \
      "$(jq -n --arg id "$existing_id" --arg text "$content" --arg title "$title" \
        '{id: $id, title: $title, text: $text}')"
    if echo "$RETVAL" | jq -e '.ok' > /dev/null 2>&1; then
      UPDATED=$((UPDATED + 1))
      log "    actualizado: $title"
      RETVAL="$existing_id"
    else
      err "update failed: $title"
      RETVAL=""
    fi
  else
    sleep 2
    local create_data
    if [ -n "$parent_id" ]; then
      create_data=$(jq -n --arg t "$title" --arg txt "$content" --arg c "$collection_id" --arg p "$parent_id" \
        '{title: $t, text: $txt, collectionId: $c, parentDocumentId: $p, publish: true}')
    else
      create_data=$(jq -n --arg t "$title" --arg txt "$content" --arg c "$collection_id" \
        '{title: $t, text: $txt, collectionId: $c, publish: true}')
    fi
    outline_api "documents.create" "$create_data"
    local new_id
    new_id=$(echo "$RETVAL" | jq -r '.data.id // empty')
    if [ -n "$new_id" ]; then
      CREATED=$((CREATED + 1))
      log "    creado: $title"
      RETVAL="$new_id"
    else
      err "create failed: $title — $(echo "$RETVAL" | jq -r '.message // .error // "unknown"')"
      RETVAL=""
    fi
  fi
}

upsert_file() {
  local collection_id="$1" file_path="$2" parent_id="${3:-}"
  local checksum_key="${collection_id}:${file_path}"

  local current_hash
  current_hash=$(file_checksum "$file_path")

  get_saved_checksum "$checksum_key"
  local saved_hash="$RETVAL"

  get_doc_id "$checksum_key"
  local cached_id="$RETVAL"

  if [ "$current_hash" = "$saved_hash" ] && [ -n "$cached_id" ]; then
    SKIPPED=$((SKIPPED + 1))
    RETVAL="$cached_id"
    return 0
  fi

  filename_to_title "$(basename "$file_path")"
  local title="$RETVAL"
  local content
  content=$(cat "$file_path")

  outline_create_or_update "$collection_id" "$title" "$content" "$parent_id"
  local doc_id="$RETVAL"

  if [ -n "$doc_id" ]; then
    save_checksum "$checksum_key" "$current_hash"
    save_doc_id "$checksum_key" "$doc_id"
  fi
  RETVAL="$doc_id"
}

ensure_folder_doc() {
  local collection_id="$1" folder_name="$2" parent_id="${3:-}"
  local cache_key="${collection_id}:folder:${folder_name}:${parent_id}"

  get_doc_id "$cache_key"
  if [ -n "$RETVAL" ]; then
    return 0
  fi

  filename_to_title "$folder_name"
  local title="$RETVAL"

  outline_create_or_update "$collection_id" "$title" "" "$parent_id"
  local doc_id="$RETVAL"

  if [ -n "$doc_id" ]; then
    save_doc_id "$cache_key" "$doc_id"
  fi
  RETVAL="$doc_id"
}

should_skip_path() {
  local path="$1"
  case "$path" in
    */raw/*|*/raw) return 0 ;;
    */.state/*|*/.state) return 0 ;;
    */.stfolder*) return 0 ;;
  esac
  local bname
  bname=$(basename "$path")
  case "$bname" in
    .gitkeep|.gitignore|.processed.yaml|*.yaml|*.yml) return 0 ;;
  esac
  return 1
}

sync_dir_recursive() {
  local collection_id="$1" dir_path="$2" parent_id="${3:-}"

  for file in "$dir_path"/*.md; do
    [ -f "$file" ] || continue
    should_skip_path "$file" && continue
    upsert_file "$collection_id" "$file" "$parent_id"
  done

  for subdir in "$dir_path"/*/; do
    [ -d "$subdir" ] || continue
    should_skip_path "$subdir" && continue

    local subdir_name
    subdir_name=$(basename "$subdir")

    local has_content=false
    if find "$subdir" -type f -name "*.md" -not -name ".gitkeep" -not -name ".gitignore" | grep -q .; then
      has_content=true
    fi
    $has_content || continue

    ensure_folder_doc "$collection_id" "$subdir_name" "$parent_id"
    local folder_id="$RETVAL"

    if [ -n "$folder_id" ]; then
      sync_dir_recursive "$collection_id" "$subdir" "$folder_id"
    fi
  done
}

sync_docs() {
  log "Sincronizando docs del repo..."
  source "$COLLECTIONS_FILE"
  local coll="$OUTLINE_DOCS"

  for file in "$DOCS_DIR"/*.md; do
    [ -f "$file" ] || continue
    upsert_file "$coll" "$file"
  done
}

sync_knowledge_company() {
  local company_id="$1"
  source "$COLLECTIONS_FILE"

  local var_name="OUTLINE_${company_id}"
  local coll="${!var_name:-}"
  if [ -z "$coll" ]; then
    err "no hay coleccion mapeada para empresa $company_id"
    return 1
  fi

  local company_dir="$KNOWLEDGE_DIR/companies/$company_id"
  [ -d "$company_dir" ] || { err "directorio $company_dir no existe"; return 1; }

  log "  empresa: $company_id → espejo completo con jerarquia"
  sync_dir_recursive "$coll" "$company_dir"
}

sync_knowledge_all() {
  log "Sincronizando knowledge por empresa..."
  for company_dir in "$KNOWLEDGE_DIR/companies"/*/; do
    [ -d "$company_dir" ] || continue
    local company_id
    company_id=$(basename "$company_dir")
    sync_knowledge_company "$company_id"
  done
}

sync_shared() {
  log "Sincronizando shared + projects..."
  source "$COLLECTIONS_FILE"
  local coll="$OUTLINE_COMPARTIDO"

  for file in "$KNOWLEDGE_DIR/shared"/*.md; do
    [ -f "$file" ] || continue
    upsert_file "$coll" "$file"
  done

  ensure_folder_doc "$coll" "projects"
  local projects_folder_id="$RETVAL"

  for file in "$KNOWLEDGE_DIR/projects"/*.md; do
    [ -f "$file" ] || continue
    upsert_file "$coll" "$file" "$projects_folder_id"
  done
}

sync_deliverables_company() {
  local company_id="$1"
  source "$COLLECTIONS_FILE"

  local var_name="OUTLINE_${company_id}"
  local coll="${!var_name:-}"
  if [ -z "$coll" ]; then
    err "no hay coleccion mapeada para empresa $company_id"
    return 1
  fi

  local deliv_dir
  case "$company_id" in
    85a05c8a) deliv_dir="$DELIVERABLES_BASE/deliverables" ;;
    6b8a8c27) deliv_dir="$DELIVERABLES_BASE/deliverables-kat" ;;
    0424a440) deliv_dir="$DELIVERABLES_BASE/deliverables-expansia" ;;
    c6f021e4) deliv_dir="$DELIVERABLES_BASE/deliverables-kat" ;;
    *)        deliv_dir="$DELIVERABLES_BASE/deliverables-${company_id}" ;;
  esac

  [ -d "$deliv_dir" ] || { log "  sin deliverables para $company_id"; return 0; }

  local file_count
  file_count=$(find "$deliv_dir" -type f -name "*.md" | wc -l)
  [ "$file_count" -eq 0 ] && { log "  deliverables vacio para $company_id"; return 0; }

  log "  deliverables $company_id: $file_count archivos"

  ensure_folder_doc "$coll" "deliverables"
  local deliv_folder_id="$RETVAL"

  if [ -n "$deliv_folder_id" ]; then
    sync_dir_recursive "$coll" "$deliv_dir" "$deliv_folder_id"
  fi
}

sync_deliverables_all() {
  log "Sincronizando deliverables por empresa..."
  for company_id in 85a05c8a 6b8a8c27 0424a440; do
    sync_deliverables_company "$company_id"
  done
}

show_usage() {
  echo "Uso: sync-outline.sh [--docs] [--knowledge] [--shared] [--deliverables] [--all] [--company ID]"
  echo ""
  echo "  --docs          Sincronizar docs del repo → Documentación Lab"
  echo "  --knowledge     Sincronizar knowledge curado → colecciones de empresa"
  echo "  --deliverables  Sincronizar deliverables de ops/ → colecciones de empresa"
  echo "  --shared        Sincronizar shared + projects → Compartido"
  echo "  --all           Todo lo anterior"
  echo "  --company ID    Sincronizar solo una empresa"
  exit 1
}

DO_DOCS=false
DO_KNOWLEDGE=false
DO_SHARED=false
DO_DELIVERABLES=false
SINGLE_COMPANY=""

[ $# -eq 0 ] && show_usage

while [ $# -gt 0 ]; do
  case "$1" in
    --docs)         DO_DOCS=true ;;
    --knowledge)    DO_KNOWLEDGE=true ;;
    --shared)       DO_SHARED=true ;;
    --deliverables) DO_DELIVERABLES=true ;;
    --all)          DO_DOCS=true; DO_KNOWLEDGE=true; DO_SHARED=true; DO_DELIVERABLES=true ;;
    --company)      SINGLE_COMPANY="$2"; shift ;;
    *)              show_usage ;;
  esac
  shift
done

log "Inicio de sincronizacion con Outline"

if $DO_DOCS; then sync_docs; fi

if [ -n "$SINGLE_COMPANY" ]; then
  sync_knowledge_company "$SINGLE_COMPANY"
  if $DO_DELIVERABLES; then sync_deliverables_company "$SINGLE_COMPANY"; fi
elif $DO_KNOWLEDGE; then
  sync_knowledge_all
fi

if $DO_DELIVERABLES && [ -z "$SINGLE_COMPANY" ]; then sync_deliverables_all; fi

if $DO_SHARED; then sync_shared; fi

log "Resultado: $CREATED creados, $UPDATED actualizados, $SKIPPED sin cambios, $ERRORS errores"
