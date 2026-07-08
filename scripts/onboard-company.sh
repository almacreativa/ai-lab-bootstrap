#!/usr/bin/env bash
# Onboarding de una empresa nueva del lab — automatiza lo seguro, guía lo manual.
# Mantiene la información saludable: aislamiento por empresa en TODAS las capas.
#
# Uso:    bash onboard-company.sh "<NombreEmpresa>"
#         (la empresa ya debe existir en Paperclip — crearla primero en la UI)
#
# Automatiza: detección de ID/prefijo, carpetas de knowledge,
#             mapa del ingest, paso en el DAG semanal de Dagu, doc de Mem0,
#             AGENTS.md esqueleto.
# Imprime guía para lo manual: mounts del compose, plugin LLM Wiki, instrucciones
#             de agentes, limpieza de workspaces clonados.
#
# Doc completo: docs/ONBOARDING_EMPRESA.md

set -euo pipefail

NAME="${1:?Uso: onboard-company.sh \"<NombreEmpresa>\" (debe existir ya en Paperclip)}"
KNOWLEDGE="$HOME/ai-lab/knowledge"
OPS="$HOME/ai-lab/ops"
SCRIPTS="$HOME/ai-lab/scripts"

log() { echo "[onboard] $*"; }

if [[ "$(uname)" == "Darwin" ]]; then
  IS_MACOS=true
  DB_CMD="psql -U paperclip -d paperclip -tA"
  PCP_BASE="$HOME/ai-lab/repos/paperclip"
else
  IS_MACOS=false
  DB_CMD="docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA"
fi

# ── 1. Detectar la empresa en Paperclip ──────────────────────────────────────
ROW=$($DB_CMD \
  -c "SELECT id, issue_prefix FROM companies WHERE name ILIKE '${NAME}';")
[ -z "$ROW" ] && { log "ERROR: empresa '$NAME' no existe en Paperclip. Crearla en la UI primero."; exit 1; }
UUID=$(echo "$ROW" | cut -d'|' -f1)
PREFIX=$(echo "$ROW" | cut -d'|' -f2)
ID8="${UUID:0:8}"
SLUG=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
log "Empresa: $NAME | UUID: $UUID | id8: $ID8 | prefijo: $PREFIX | slug: $SLUG"

# ── 2. ¿Workspaces clonados? (la portabilidad copia contenido de la origen) ──
AGENTS=$($DB_CMD \
  -c "SELECT name, id FROM agents WHERE company_id='${UUID}';")
if [ -n "$AGENTS" ]; then
  log "Agentes existentes:"
  echo "$AGENTS" | sed 's/^/    /'
  while IFS='|' read -r aname aid; do
    if $IS_MACOS; then
      CNT=$(ls -A "${PCP_BASE}/instances/default/workspaces/$aid" 2>/dev/null | wc -l || echo 0)
    else
      CNT=$(docker exec paperclip-server-1 sh -c \
        "ls -A /paperclip/instances/default/workspaces/$aid 2>/dev/null | wc -l" || echo 0)
    fi
    if [ "${CNT:-0}" -gt 0 ]; then
      log "Workspace de '$aname' tiene $CNT items — si la empresa fue CLONADA, contiene datos de la origen."
      read -rp "    ¿Vaciar workspace de $aname? [s/N] " R
      if [ "$R" = "s" ]; then
        if $IS_MACOS; then
          find "${PCP_BASE}/instances/default/workspaces/$aid" -mindepth 1 -delete && log "    vaciado"
        else
          docker exec paperclip-server-1 \
            find "/paperclip/instances/default/workspaces/$aid" -mindepth 1 -delete && log "    vaciado"
        fi
      fi
    fi
  done <<< "$AGENTS"
fi

# ── 3. Carpetas de knowledge ─────────────────────────────────────────────────
mkdir -p "$KNOWLEDGE/companies/$ID8"/{deliverables,sessions,wiki}
log "Knowledge: $KNOWLEDGE/companies/$ID8/{deliverables,sessions,wiki} ✓"

# ── 4. Espejo de deliverables ────────────────────────────────────────────────
# Lo cubre sync-company.sh: los workspaces y dirs compartidos del contenedor se
# espejan a ~/ai-lab/knowledge/<slug>/outputs/ según stacks/sync-config/<slug>.json
# (ver paso manual B para registrar el dir compartido <slug>-deliverables).
log "Espejo de deliverables: via sync-company.sh + sync-config/$SLUG.json (paso B)"

# ── 5. Mapa del ingest semanal (weekly-ingest.sh) ────────────────────────────
if ! grep -q "  $ID8)" "$SCRIPTS/weekly-ingest.sh"; then
  python3 - "$ID8" "$SLUG" "$SCRIPTS/weekly-ingest.sh" << 'PYEOF'
import sys
id8, slug, path = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
anchor = '  *)        DELIVERABLES_DIR='
nueva = f'  {id8}) DELIVERABLES_DIR="$HOME/ai-lab/knowledge/{slug}/outputs" ;;\n'
s = s.replace(anchor, nueva + anchor, 1)
open(path, 'w').write(s)
PYEOF
  log "Mapa de ingest: $ID8 → deliverables-$SLUG ✓"
fi
bash -n "$SCRIPTS/weekly-ingest.sh"

# ── 6. Paso de ingest en el DAG semanal de Dagu ──────────────────────────────
# (el crontab quedó retirado — la fuente de scheduling es Dagu desde 2026-06-20)
DAG_FILE="$HOME/.config/dagu/dags/weekly-ingest.yaml"
if [ -f "$DAG_FILE" ] && ! grep -q "weekly-ingest.sh $ID8" "$DAG_FILE"; then
  python3 - "$ID8" "$SLUG" "$DAG_FILE" << 'PYEOF'
import re, sys
id8, slug, path = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
steps = re.findall(r'^  - name: (\S+)', s, re.M)
depends = f"    depends: [{steps[-1]}]\n" if steps else ""
new = (f"  - name: ingest-{slug}\n"
       f"    run: $HOME_PLACEHOLDER/ai-lab/scripts/weekly-ingest.sh {id8}\n"
       f"    timeout_sec: 5400\n"
       f"    continue_on:\n      failure: true\n"
       f"{depends}"
       f"    retry_policy:\n      limit: 2\n      interval_sec: 120\n\n")
import os
new = new.replace("$HOME_PLACEHOLDER", os.path.expanduser("~"))
if "handler_on:" in s:
    s = s.replace("handler_on:", new + "handler_on:", 1)
else:
    s = s.rstrip() + "\n\n" + new
open(path, "w").write(s)
PYEOF
  log "DAG weekly-ingest: paso ingest-$SLUG agregado ✓ (revisar con: dagu status)"
else
  log "DAG weekly-ingest: paso ya existía (o DAG no encontrado) ✓"
fi

# ── 7. Goal de empresa en Paperclip ────────────────────────────────────────
GOAL_EXISTS=$($DB_CMD \
  -c "SELECT count(*) FROM goals WHERE company_id = '$UUID' AND level = 'company';")
if [ "$GOAL_EXISTS" = "0" ]; then
  $DB_CMD -c "
    INSERT INTO goals (id, company_id, title, level, status, created_at, updated_at)
    VALUES (gen_random_uuid(), '$UUID',
      '[COMPLETAR: misión general de $NAME — qué hace, para quién, qué la diferencia]',
      'company', 'active', now(), now());" >/dev/null
  log "Goal de empresa creado (esqueleto) → COMPLETAR el título con la misión real ✓"
else
  log "Goal de empresa ya existe ✓"
fi

# ── 8. Convención Mem0 (documentar el namespace) ─────────────────────────────
NSDOC="$KNOWLEDGE/shared/templates/mem0-namespacing.md"
if [ -f "$NSDOC" ] && ! grep -q "company_$ID8" "$NSDOC"; then
  python3 - "$ID8" "$NAME" "$NSDOC" << 'PYEOF'
import sys
id8, name, path = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
anchor = "| `company_<id>` |"
s = s.replace(anchor, f"| `company_{id8}` | Todo agente trabajando para {name} |\n" + anchor, 1)
open(path, 'w').write(s)
PYEOF
  log "Mem0: namespace company_$ID8 documentado ✓"
fi

# ── 9.5 Plantilla S2 (company prompt) ────────────────────────────────────────
S2_DEST="$KNOWLEDGE/shared/templates/prompt-section2-${SLUG}.md"
if [ ! -f "$S2_DEST" ]; then
  sed -e "s/{{COMPANY_NAME}}/$NAME/g" -e "s/{{PREFIX}}/$PREFIX/g" \
    "$KNOWLEDGE/shared/templates/prompt-section2-template.md" > "$S2_DEST"
  log "S2 prompt: $S2_DEST creado → COMPLETAR descripción de la empresa ✓"
else
  log "S2 prompt: $S2_DEST ya existía ✓"
fi

# ── 9.6 Esqueletos S3 (agent prompts) ───────────────────────────────────────
S3_DIR="$KNOWLEDGE/shared/templates/prompt-section3"
while IFS='|' read -r aname aid; do
  [ -z "$aname" ] && continue
  aslug=$(echo "$aname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  s3file="$S3_DIR/${SLUG}-${aslug}.md"
  if [ ! -f "$s3file" ]; then
    cat > "$s3file" << S3EOF
Your role: $aname

Mission: [COMPLETAR: misión del agente en $NAME]

Additional output destinations (besides workspace):
- [COMPLETAR]

Operational instructions:
- [COMPLETAR]
S3EOF
    log "S3 prompt: ${SLUG}-${aslug}.md creado → COMPLETAR ✓"
  fi
done <<< "$AGENTS"

# ── 9. AGENTS.md esqueleto (completar a mano o con un agente) ────────────────
AGMD="$KNOWLEDGE/companies/$ID8/AGENTS.md"
if [ ! -f "$AGMD" ]; then
  cat > "$AGMD" << EOF
# $NAME — Contexto para Agentes

## Qué es
[COMPLETAR: propósito de la empresa, qué produce, principio rector — máx 500 palabras total]

## Agentes activos
$(echo "$AGENTS" | awk -F'|' '{print "- **" $1 "** — [rol]"}')
Prefijo de issues: \`$PREFIX\`.

## Memoria y conocimiento
- Contexto curado (este archivo, ro): /paperclip/knowledge/companies/$ID8/AGENTS.md
- Wiki de trabajo (rw, tools wiki_*): /paperclip/knowledge/companies/$ID8/wiki
- Mem0: user_id="company_$ID8" — buscar al arrancar, registrar decisiones al cerrar
- Deliverables finales: /paperclip/$SLUG-deliverables/

## Convenciones
- Todo en español. Commits como "Alma Creativa" sin co-author de IA.
- NUNCA credenciales en wiki, memorias ni deliverables.
- Aislamiento: prohibido leer/referenciar datos de otras empresas.
EOF
  log "AGENTS.md esqueleto creado → COMPLETAR la sección 'Qué es' ✓"
fi

# ── 10. Guía de pasos manuales restantes ─────────────────────────────────────
cat << EOF

═══════════════════════════════════════════════════════════════════
PASOS MANUALES RESTANTES (en orden):

A) Compose de Paperclip (~/ai-lab/repos/paperclip/docker/docker-compose.yml),
   agregar a volumes del server (curado ro ANTES del wiki rw):
      - \${HOME}/ai-lab/knowledge/companies/$ID8:/paperclip/knowledge/companies/$ID8:ro
      - \${HOME}/ai-lab/knowledge/companies/$ID8/wiki:/paperclip/knowledge/companies/$ID8/wiki
   Luego:
      cd ~/ai-lab/repos/paperclip/docker && docker compose up -d server
      docker exec paperclip-server-1 mkdir -p /paperclip/$SLUG-deliverables

B) sync-config: crear/editar ~/ai-lab/stacks/sync-config/$SLUG.json y registrar
   el dir compartido en extra_container_dirs:
      {"container_path": "/paperclip/$SLUG-deliverables", "output_name": "$SLUG-deliverables"}
   (sync-company.sh lo espejará a ~/ai-lab/knowledge/$SLUG/outputs/).

C) Plugin LLM Wiki (UI de Paperclip, panel de $NAME):
   Local wiki folder = /paperclip/knowledge/companies/$ID8/wiki
   → Health check: Configured/Readable/Writable = Yes

D) Instrucciones de los agentes de $NAME (UI): pegar el snippet de contexto
   (ver docs/ONBOARDING_EMPRESA.md §D) con company_$ID8.

E) Completar AGENTS.md: $AGMD

E2) Completar el goal de empresa en Paperclip (UI o DB):
    editar el título del goal con la misión real de $NAME.

F) Smoke test: tarea a un agente — leer AGENTS.md + wiki_write_page + Mem0.

G) (Cuando tenga contenido) Cuaderno NLM propio + push monitor en Kuma.

H) Deploy de promptTemplate a los agentes de $NAME:
   1. Completar $KNOWLEDGE/shared/templates/prompt-section2-${SLUG}.md (descripción de empresa)
   2. Completar cada archivo en $KNOWLEDGE/shared/templates/prompt-section3/${SLUG}-*.md (roles)
   3. Ejecutar: bash $SCRIPTS/deploy-agent-prompts.sh $SLUG
═══════════════════════════════════════════════════════════════════
EOF
log "Onboarding automático completo. Validar con los pasos A-G."
