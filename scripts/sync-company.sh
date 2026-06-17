#!/bin/bash
# sync-company.sh <slug>
# Generic sync: entradas/ → validar → issue → container | workspaces → outputs/ → repo
#
# Flujos por empresa:
#   A) Entradas:   host entradas/ → guardrails → issue Paperclip → container knowledge/entradas/
#   B) Outputs:    container workspaces → host outputs/ (+ extras como alma-deliverables)
#   C) Repo loop:  git pull → detectar externos → issue → sync dirs → git push   (solo si repo.enabled)
#
# Config: ~/ai-lab/stacks/sync-config/<slug>.json
# Estado: ~/ai-lab/knowledge/.state/<slug>-*.json

set -uo pipefail

# ─── CONFIGURACIÓN DEL OPERADOR ────────────────────────────────────────────────
# Editar estas variables antes de usar el script.
CONTAINER="paperclip-server-1"           # nombre del contenedor en docker compose
DB_CONTAINER="paperclip-db-1"            # nombre del contenedor de postgres
CONFIG_DIR="${HOME}/ai-lab/stacks/sync-config"
STATE_DIR="${HOME}/ai-lab/knowledge/.state"
LOG_DIR="${HOME}/ai-lab/logs"
SYNC_AUTHOR="${PCSYNC_AUTHOR:-Operador Bot <bot@tuorganizacion.com>}"  # autor de los commits automáticos (o exportar PCSYNC_AUTHOR)

# ─── VALIDACIÓN DE ARGUMENTOS ──────────────────────────────────────────────────
SLUG="${1:-}"
[ -z "$SLUG" ] && { echo "Uso: $0 <slug>  (katun|alma|expansia)"; exit 1; }

CONFIG="${CONFIG_DIR}/${SLUG}.json"
[ -f "$CONFIG" ] || { echo "Config no encontrado: $CONFIG"; exit 1; }

mkdir -p "$LOG_DIR" "$STATE_DIR"
LOG="${LOG_DIR}/sync-${SLUG}.log"

# ─── HELPERS ───────────────────────────────────────────────────────────────────

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${SLUG}] $1" | tee -a "$LOG"
}

# cfg <key.path> — lee un valor del config JSON via python3
cfg() {
  python3 -c "
import json, sys
try:
    c = json.load(open('${CONFIG}'))
    keys = '${1}'.split('.')
    v = c
    for k in keys:
        v = v[k] if isinstance(v, dict) and k in v else None
        if v is None: break
    if v is None: pass
    elif isinstance(v, bool): print(str(v).lower(), end='')
    elif isinstance(v, list):
        for item in v:
            print(item if not isinstance(item, dict) else json.dumps(item, ensure_ascii=False))
    else: print(v, end='')
except Exception as e: pass
" 2>/dev/null
}

# ─── CARGAR CONFIG ─────────────────────────────────────────────────────────────
COMPANY_ID=$(cfg company_id)
ISSUE_PREFIX=$(cfg issue_prefix)
PROJECT_ID=$(cfg project_id)
CEO_AGENT_ID=$(cfg ceo_agent_id)
KNOWLEDGE_HOST=$(cfg knowledge_host_path)
CONTAINER_KNOWLEDGE=$(cfg container_knowledge_path)
WIKI_CONTAINER=$(cfg wiki_container_path)
REPO_ENABLED=$(cfg repo.enabled)

ENTRADAS_HOST="${KNOWLEDGE_HOST}/entradas"
OUTPUTS_HOST="${KNOWLEDGE_HOST}/outputs"
ENTRADAS_MANIFEST="${STATE_DIR}/${SLUG}-entradas.json"

# ─── GUARDRAILS ────────────────────────────────────────────────────────────────
validate_entry() {
  local file="$1"
  local filename
  filename=$(basename "$file")
  local ext="${filename##*.}"

  # Extensión permitida
  if [[ "$ext" != "md" && "$ext" != "txt" ]]; then
    log "GUARDRAIL BLOCKED [${filename}]: extensión .${ext} no permitida (solo .md .txt)"
    return 1
  fi

  # Tamaño máximo 50 KB
  local size
  size=$(stat -c%s "$file" 2>/dev/null || echo 999999)
  if [ "$size" -gt 51200 ]; then
    log "GUARDRAIL BLOCKED [${filename}]: ${size}B supera 50 KB"
    return 1
  fi

  # Patrones prohibidos: destructivos e inyección de prompt
  local patterns=(
    "rm -rf"
    "docker exec"
    "sudo "
    "eval("
    'ignora tus instrucciones'
    'ignore your instructions'
    "olvida todo"
    "forget everything"
    "nuevo sistema prompt"
    "new system prompt"
    "\`\`\`system"
    "<system>"
  )
  for p in "${patterns[@]}"; do
    if grep -qi "$p" "$file" 2>/dev/null; then
      log "GUARDRAIL BLOCKED [${filename}]: patrón prohibido detectado"
      return 1
    fi
  done

  return 0
}

# ─── CREACIÓN DE ISSUES ────────────────────────────────────────────────────────
create_issue() {
  local title="$1"
  local body="$2"
  local agent_id="$3"
  local priority="${4:-high}"

  local next_num
  next_num=$(docker exec "$DB_CONTAINER" psql -U paperclip -d paperclip -tA \
    -c "SELECT COALESCE(MAX(CAST(REGEXP_REPLACE(identifier, '[^0-9]', '', 'g') AS INT)), 0) + 1
        FROM issues WHERE identifier ~ '^${ISSUE_PREFIX}-[0-9]+$';" 2>/dev/null | tr -d ' ')

  if [ -z "$next_num" ]; then
    log "ERROR: no se pudo calcular número de issue"
    echo ""
    return 1
  fi

  local identifier="${ISSUE_PREFIX}-${next_num}"
  local safe_title
  safe_title=$(python3 -c "import sys; print(sys.stdin.read().replace(\"'\",\"''\"), end='')" <<< "$title" 2>/dev/null || echo "$title")

  docker exec "$DB_CONTAINER" psql -U paperclip -d paperclip -tA -c "
    INSERT INTO issues (id, company_id, project_id, title, description, status, priority, assignee_agent_id, identifier, issue_number)
    VALUES (
      gen_random_uuid(),
      '${COMPANY_ID}',
      '${PROJECT_ID}',
      '${safe_title}',
      \$PCSYNC\$${body}\$PCSYNC\$,
      'todo',
      '${priority}',
      '${agent_id}',
      '${identifier}',
      ${next_num}
    ) RETURNING identifier;" 2>> "$LOG" >/dev/null && \
    log "Issue creada: ${identifier}" || log "ERROR: fallo al crear issue ${identifier}"

  echo "$identifier"
}

# ─── PROCESAR ENTRADAS NUEVAS ─────────────────────────────────────────────────
process_new_entradas() {
  [ -d "$ENTRADAS_HOST" ] || return 0

  # Inicializar manifest si no existe
  [ -f "$ENTRADAS_MANIFEST" ] || echo '{}' > "$ENTRADAS_MANIFEST"

  local count=0
  while IFS= read -r file; do
    local filename
    filename=$(basename "$file")
    local file_hash
    file_hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}' || echo "")
    [ -z "$file_hash" ] && continue

    # Saltar si ya fue procesado con el mismo hash
    local known_hash
    known_hash=$(python3 -c "
import json
try:
    m = json.load(open('${ENTRADAS_MANIFEST}'))
    print(m.get('${filename}', {}).get('hash', ''))
except: pass
" 2>/dev/null)
    [ "$file_hash" = "$known_hash" ] && continue

    # Validar guardrails
    validate_entry "$file" || {
      # Guardar en manifest como bloqueado para no reintentar cada ciclo
      python3 -c "
import json, datetime
m = {}
try: m = json.load(open('${ENTRADAS_MANIFEST}'))
except: pass
m['${filename}'] = {'hash': '${file_hash}', 'issue': '', 'status': 'blocked', 'processed_at': datetime.datetime.now().isoformat()}
with open('${ENTRADAS_MANIFEST}', 'w') as f: json.dump(m, f, indent=2)
" 2>/dev/null
      continue
    }

    # Determinar agente por reglas de routing
    local agent_id="$CEO_AGENT_ID"
    while IFS= read -r rule_json; do
      [ -z "$rule_json" ] && continue
      local keyword rule_agent
      keyword=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('keyword',''))" "$rule_json" 2>/dev/null)
      rule_agent=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('agent_id',''))" "$rule_json" 2>/dev/null)
      if [ -n "$keyword" ] && echo "$filename" | grep -qi "$keyword" 2>/dev/null; then
        [ -n "$rule_agent" ] && agent_id="$rule_agent"
        break
      fi
    done < <(python3 -c "
import json
c = json.load(open('${CONFIG}'))
for r in c.get('entradas_routing', {}).get('rules', []):
    import json as j; print(j.dumps(r))
" 2>/dev/null)

    # Construir cuerpo del issue
    local file_lines
    file_lines=$(wc -l < "$file" 2>/dev/null || echo "?")
    local file_content
    file_content=$(head -100 "$file" 2>/dev/null || echo "(no se pudo leer el contenido)")
    local base_name="${filename%.*}"

    local body="## Nueva entrada para procesamiento

El operador depositó el archivo \`${filename}\` en la carpeta \`entradas/\`. Lee el contenido, entiende el propósito, y produce trabajo de valor basado en él.

### Contenido del archivo (\`${filename}\`, ${file_lines} líneas)

\`\`\`
${file_content}
\`\`\`

---

## Tu tarea

1. Lee el contenido completo arriba.
2. Determina el tipo de input: brief, feedback, investigación, instrucción, contexto, etc.
3. Produce el entregable correspondiente según tu rol.
4. Guarda tu output en tu workspace o en la carpeta de deliverables de la empresa.
5. Deja un comentario en esta issue explicando qué produjiste y dónde lo guardaste.

El archivo original está disponible en el contenedor: \`${CONTAINER_KNOWLEDGE}/entradas/${filename}\`"

    local issue_id
    issue_id=$(create_issue "${ISSUE_PREFIX}: Entrada — ${base_name}" "$body" "$agent_id")

    # Actualizar manifest (siempre, éxito o fallo en issue creation)
    python3 -c "
import json, datetime
m = {}
try: m = json.load(open('${ENTRADAS_MANIFEST}'))
except: pass
m['${filename}'] = {
    'hash': '${file_hash}',
    'issue': '${issue_id}',
    'status': 'processed',
    'processed_at': datetime.datetime.now().isoformat()
}
with open('${ENTRADAS_MANIFEST}', 'w') as f:
    json.dump(m, f, indent=2)
" 2>/dev/null

    count=$((count + 1))
  done < <(find "$ENTRADAS_HOST" -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) | sort)

  if [ $count -gt 0 ]; then
    log "Entradas procesadas en este ciclo: ${count}"
  else
    log "Sin entradas nuevas"
  fi
}

# ─── SYNC ENTRADAS HOST → CONTAINER ──────────────────────────────────────────
sync_entradas_to_container() {
  docker exec "$CONTAINER" mkdir -p "${CONTAINER_KNOWLEDGE}/entradas/" 2>/dev/null || true

  if [ -n "$(ls -A "${ENTRADAS_HOST}/" 2>/dev/null)" ]; then
    docker cp "${ENTRADAS_HOST}/." "${CONTAINER}:${CONTAINER_KNOWLEDGE}/entradas/" 2>> "$LOG" || \
      log "WARN: fallo sync entradas → container"
    log "Entradas sincronizadas al contenedor"
  fi
}

# ─── SYNC OUTPUTS (workspaces → host) ────────────────────────────────────────
sync_outputs() {
  # Workspace de cada agente → outputs/<nombre>/
  python3 -c "
import json
for a in json.load(open('${CONFIG}'))['agents']:
    print(f\"{a['name']}:{a['id']}\")
" 2>/dev/null | while IFS=: read -r agent_name agent_id; do
    local out_dir="${OUTPUTS_HOST}/${agent_name}"
    mkdir -p "$out_dir"
    local tmp
    tmp=$(mktemp -d)
    docker cp "${CONTAINER}:/paperclip/instances/default/workspaces/${agent_id}/." \
      "$tmp/" 2>> "$LOG" || { rm -rf "$tmp"; continue; }
    rsync -a "$tmp/" "$out_dir/" 2>> "$LOG"
    rm -rf "$tmp"
  done

  # Directorios extra del contenedor (alma-deliverables, expansia-deliverables, etc.)
  python3 -c "
import json
for e in json.load(open('${CONFIG}')).get('extra_container_dirs', []):
    print(f\"{e['output_name']}:{e['container_path']}\")
" 2>/dev/null | while IFS=: read -r out_name container_path; do
    [ -z "$out_name" ] && continue
    local out_dir="${OUTPUTS_HOST}/${out_name}"
    mkdir -p "$out_dir"
    local tmp
    tmp=$(mktemp -d)
    docker cp "${CONTAINER}:${container_path}/." "$tmp/" 2>> "$LOG" || \
      { rm -rf "$tmp"; continue; }
    rsync -a "$tmp/" "$out_dir/" 2>> "$LOG"
    rm -rf "$tmp"
    log "Extra dir ${out_name} sincronizado a outputs/"
  done

  # Wiki LLM → outputs/wiki/
  if [ -n "$WIKI_CONTAINER" ] && \
     docker exec "$CONTAINER" test -d "$WIKI_CONTAINER" 2>/dev/null; then
    mkdir -p "${OUTPUTS_HOST}/wiki"
    local tmp
    tmp=$(mktemp -d)
    docker cp "${CONTAINER}:${WIKI_CONTAINER}/." "$tmp/" 2>> "$LOG" && \
      { rsync -a "$tmp/" "${OUTPUTS_HOST}/wiki/" 2>> "$LOG"; log "Wiki → outputs/wiki/ done"; } || true
    rm -rf "$tmp"
  fi

  log "Outputs sincronizados"
}

# ─── REPO: pull + detectar commits externos ───────────────────────────────────
do_repo_pull() {
  local repo_path
  repo_path=$(cfg repo.host_path)
  local last_commit_file="${STATE_DIR}/${SLUG}-last-commit.txt"

  cd "$repo_path" || { log "ERROR: no se puede acceder a ${repo_path}"; return 1; }

  local prev_commit
  prev_commit=$(cat "$last_commit_file" 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo "")

  git pull --ff-only 2>> "$LOG" || { log "WARN: git pull --ff-only falló, continuando con estado local"; return 0; }

  local curr_commit
  curr_commit=$(git rev-parse HEAD 2>/dev/null || echo "")

  if [ -n "$prev_commit" ] && [ "$prev_commit" != "$curr_commit" ]; then
    detect_external_commits "$repo_path" "$prev_commit" "$curr_commit" || true
    echo "$curr_commit" > "$last_commit_file"
  else
    log "Sin cambios en repo remoto"
    [ -z "$(cat "$last_commit_file" 2>/dev/null)" ] && echo "$curr_commit" > "$last_commit_file" || true
  fi
}

detect_external_commits() {
  local repo_path="$1"
  local prev="$2"
  local curr="$3"

  # Autores bot desde config
  local -a bot_emails=()
  while IFS= read -r email; do
    [ -n "$email" ] && bot_emails+=("$email")
  done < <(python3 -c "
import json
for a in json.load(open('${CONFIG}')).get('repo', {}).get('bot_authors', []):
    print(a)
" 2>/dev/null)

  # Verificar commits de autores externos
  local ext_count=0
  while IFS= read -r email; do
    [ -z "$email" ] && continue
    local is_bot=false
    for bot in "${bot_emails[@]}"; do
      [[ "$email" == *"$bot"* ]] && is_bot=true && break
    done
    $is_bot || ext_count=$((ext_count + 1))
  done < <(cd "$repo_path" && git log --pretty=format:"%ae" "${prev}..${curr}" 2>/dev/null)

  if [ $ext_count -eq 0 ]; then
    log "Solo commits del bot, sin issue nueva"
    return 0
  fi

  log "Commits externos detectados: ${ext_count}"

  # Contexto del diff (excluyendo produccion/ que es output del bot)
  local changed_files
  changed_files=$(cd "$repo_path" && git diff --name-only "${prev}" "${curr}" \
    -- fuentes/ contenidos/ '*.md' 2>/dev/null | grep -v "^produccion/" | head -30 || echo "")

  local diff_stat
  diff_stat=$(cd "$repo_path" && git diff --stat "${prev}" "${curr}" \
    -- fuentes/ contenidos/ '*.md' 2>/dev/null | grep -v "^produccion/" | tail -20 || echo "")

  local commit_msgs
  commit_msgs=$(cd "$repo_path" && git log --pretty=format:"- %s (%an, %ar)" \
    "${prev}..${curr}" 2>/dev/null | grep -v "^- sync: " | head -10 || echo "")

  # Snippets de archivos clave (hasta 3, primeras 60 líneas)
  local file_snippets=""
  local fcount=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ $fcount -ge 3 ] && break
    if [ -f "${repo_path}/$f" ]; then
      file_snippets="${file_snippets}
### \`${f}\`
\`\`\`
$(head -60 "${repo_path}/$f" 2>/dev/null)
\`\`\`
"
      fcount=$((fcount + 1))
    fi
  done <<< "$changed_files"

  # Routing: archivos de contenidos → agente de contenido (si existe regla)
  local assignee_id="$CEO_AGENT_ID"
  if echo "$changed_files" | grep -q "^contenidos/"; then
    local content_agent
    content_agent=$(python3 -c "
import json
c = json.load(open('${CONFIG}'))
for r in c.get('entradas_routing', {}).get('rules', []):
    if 'contenido' in r.get('keyword', '').lower():
        print(r['agent_id']); break
" 2>/dev/null)
    [ -n "$content_agent" ] && assignee_id="$content_agent"
  fi

  local display="${SLUG^^}"
  local body="## Cambios externos detectados en el repositorio

El repo de ${display} recibió commits de colaboradores externos. Tu trabajo es leer los cambios, entender qué aportaron, y construir sobre ello.

### Commits recibidos
${commit_msgs}

### Archivos modificados
\`\`\`
${diff_stat}
\`\`\`

### Contenido de los archivos clave
${file_snippets}

---

## Tu tarea

1. **Leé los archivos modificados** desde \`${CONTAINER_KNOWLEDGE}/\` — ya están actualizados.
2. **Identificá qué aportaron** los colaboradores: correcciones, nuevos conceptos, feedback, ideas.
3. **Producí trabajo nuevo** que construya sobre esos aportes — no reescribas, construí encima.
4. **Guardá los entregables** en tu workspace según corresponda.
5. **Dejá un comentario** en esta issue explicando qué encontraste y qué produjiste."

  create_issue "Cambios externos — construir sobre aportes del repo" \
    "$body" "$assignee_id" >/dev/null || true
}

# ─── REPO: sync directorios repo → container ──────────────────────────────────
sync_repo_to_container() {
  local repo_path
  repo_path=$(cfg repo.host_path)

  # Directorios del repo → container knowledge
  cfg repo.sync_repo_to_container_dirs | while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    docker exec "$CONTAINER" mkdir -p "${CONTAINER_KNOWLEDGE}/${dir}/" 2>/dev/null || true
    if [ -d "${repo_path}/${dir}" ]; then
      docker cp "${repo_path}/${dir}/." \
        "${CONTAINER}:${CONTAINER_KNOWLEDGE}/${dir}/" 2>> "$LOG" || \
        log "WARN: fallo sync ${dir}/ → container"
    fi
  done

  # Archivos raíz del repo → container
  cfg repo.sync_root_files | while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ -f "${repo_path}/$f" ]; then
      docker cp "${repo_path}/$f" \
        "${CONTAINER}:${CONTAINER_KNOWLEDGE}/$f" 2>> "$LOG" || true
    fi
  done

  # Repo entradas/ → host knowledge/entradas/
  # Archivos que el equipo externo sube al repo fluyen al pipeline de procesamiento.
  local sync_entradas_from_repo
  sync_entradas_from_repo=$(cfg repo.sync_entradas_from_repo)
  if [ "$sync_entradas_from_repo" = "true" ] && [ -d "${repo_path}/entradas" ]; then
    rsync -a --exclude="README.md" \
      "${repo_path}/entradas/" "${ENTRADAS_HOST}/" 2>> "$LOG" || true
    log "Repo entradas/ → host knowledge/entradas/ synced"
  fi

  log "Repo → container sync done"
}

# ─── REPO: container → repo → commit → push ───────────────────────────────────
sync_container_to_repo_and_push() {
  local repo_path
  repo_path=$(cfg repo.host_path)

  # Directorios del container → repo host (contenidos/)
  cfg repo.sync_container_to_repo_dirs | while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    mkdir -p "${repo_path}/${dir}"
    local tmp
    tmp=$(mktemp -d)
    docker cp "${CONTAINER}:${CONTAINER_KNOWLEDGE}/${dir}/." "$tmp/" 2>> "$LOG" && \
      rsync -a "$tmp/" "${repo_path}/${dir}/" 2>> "$LOG" || \
      log "WARN: fallo sync container ${dir}/ → repo"
    rm -rf "$tmp"
  done

  # Workspaces → repo/produccion/<agente>/
  # PROTECCIÓN hash-based: compara (workspace_hash, repo_hash, last_sync_hash).
  # Si un humano modificó un archivo (repo≠last_sync) y el agente no lo actualizó
  # (workspace=last_sync), el archivo se preserva. Si ambos cambiaron → humano gana.
  # El manifest en .state/<slug>-produccion-manifest.json registra lo que sync escribió.
  local prod_from_ws
  prod_from_ws=$(cfg repo.produccion_from_workspaces)
  if [ "$prod_from_ws" = "true" ]; then
    local PRODUCCION_MANIFEST="${STATE_DIR}/${SLUG}-produccion-manifest.json"
    [ -f "$PRODUCCION_MANIFEST" ] || echo '{}' > "$PRODUCCION_MANIFEST"

    local py_result
    py_result=$(python3 - "${CONFIG}" "${PRODUCCION_MANIFEST}" \
                  "${OUTPUTS_HOST}" "${repo_path}/produccion" <<'PYEOF'
import json, os, hashlib, subprocess, sys

config_path, manifest_path, outputs_base, prod_base = sys.argv[1:5]

with open(config_path) as f:
    config = json.load(f)

try:
    manifest = json.load(open(manifest_path))
except Exception:
    manifest = {}

agents = [a['name'] for a in config['agents']]
protected = []

def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()

os.makedirs(prod_base, exist_ok=True)

for agent in agents:
    agent_out = os.path.join(outputs_base, agent)
    agent_prod = os.path.join(prod_base, agent)
    if not os.path.isdir(agent_out):
        continue
    os.makedirs(agent_prod, exist_ok=True)

    exclude = []
    for root, dirs, files in os.walk(agent_out):
        dirs.sort(); files.sort()
        for fname in files:
            ws_file = os.path.join(root, fname)
            rel = os.path.relpath(ws_file, agent_out)
            repo_file = os.path.join(agent_prod, rel)
            key = f"{agent}/{rel}"

            ws_hash = md5(ws_file)
            repo_hash = md5(repo_file) if os.path.exists(repo_file) else ''
            last_hash = manifest.get(key, {}).get('hash', '')

            # Protect if human modified (repo≠last) and agent unchanged (ws=last)
            # OR conflict (both changed but differently) → human wins
            if last_hash and repo_hash != last_hash and (ws_hash == last_hash or ws_hash != repo_hash):
                exclude.append(rel)
                protected.append(key)

    excl_path = f'/tmp/.pcsync_excl_{agent}'
    with open(excl_path, 'w') as fh:
        fh.write('\n'.join(exclude))
    subprocess.run(
        ['rsync', '-a', f'--exclude-from={excl_path}',
         f'{agent_out}/', f'{agent_prod}/'],
        capture_output=True)
    os.unlink(excl_path)

    # Update manifest: only for files where ws_hash==repo_hash (were synced)
    for root, dirs, files in os.walk(agent_out):
        for fname in files:
            ws_file = os.path.join(root, fname)
            rel = os.path.relpath(ws_file, agent_out)
            repo_file = os.path.join(agent_prod, rel)
            key = f"{agent}/{rel}"
            ws_hash = md5(ws_file)
            repo_hash = md5(repo_file) if os.path.exists(repo_file) else ''
            if ws_hash == repo_hash:
                manifest[key] = {'hash': ws_hash}

with open(manifest_path, 'w') as fh:
    json.dump(manifest, fh, indent=2)

print(json.dumps({'protected': protected}))
PYEOF
    )

    local pcount=0
    pcount=$(echo "$py_result" | python3 -c \
      "import json,sys; print(len(json.loads(sys.stdin.read()).get('protected',[])))" \
      2>/dev/null || echo 0)

    if [ "$pcount" -gt 0 ]; then
      log "Protegidos ${pcount} archivos con ediciones humanas en produccion/:"
      echo "$py_result" | python3 -c "
import json,sys
for f in json.loads(sys.stdin.read()).get('protected',[]): print(f'  → {f}')
" 2>/dev/null | while IFS= read -r line; do log "$line"; done
    fi
  fi

  # Wiki → repo/produccion/wiki/ (con --delete, la wiki es autoritativa del LLM)
  local sync_wiki
  sync_wiki=$(cfg repo.sync_wiki_to_repo)
  if [ "$sync_wiki" = "true" ] && [ -d "${OUTPUTS_HOST}/wiki" ]; then
    mkdir -p "${repo_path}/produccion/wiki"
    rsync -a --delete "${OUTPUTS_HOST}/wiki/" \
      "${repo_path}/produccion/wiki/" 2>> "$LOG"
  fi

  # Git add + commit + push si hay cambios
  cd "$repo_path" || return 1

  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    for dir in contenidos produccion entradas; do
      [ -d "${repo_path}/$dir" ] && git add "$dir" 2>> "$LOG" || true
    done
    git commit \
      -m "sync: actualización automática ${SLUG}" \
      --author="$SYNC_AUTHOR" 2>> "$LOG" || true
    git push 2>> "$LOG" || log "WARN: git push falló (se reintentará en el próximo ciclo)"
    log "Git commit + push completado"
  else
    log "Sin cambios git que committear"
  fi
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
log "=== Sync ${SLUG^^} started ==="

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  log "ERROR: Container ${CONTAINER} no está corriendo — abortando"
  exit 1
fi

# 1. Repo pull + detección de commits externos
if [ "$REPO_ENABLED" = "true" ]; then
  do_repo_pull || log "WARN: do_repo_pull falló, continuando"
  sync_repo_to_container || log "WARN: sync_repo_to_container falló, continuando"
fi

# 2. Sync host entradas/ → container knowledge/entradas/
sync_entradas_to_container

# 3. Detectar entradas nuevas → guardrails → issues
process_new_entradas

# 4. Sync outputs: workspaces + extras + wiki → host outputs/
sync_outputs

# 5. Repo: container → repo → git push
if [ "$REPO_ENABLED" = "true" ]; then
  sync_container_to_repo_and_push || log "WARN: sync_container_to_repo_and_push falló"
fi

log "=== Sync ${SLUG^^} complete ==="
