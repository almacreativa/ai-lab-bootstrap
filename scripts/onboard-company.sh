#!/usr/bin/env bash
# Onboarding de una empresa nueva del lab — automatiza lo seguro, guía lo manual.
# Mantiene la información saludable: aislamiento por empresa en TODAS las capas.
#
# Uso:    bash onboard-company.sh "<NombreEmpresa>"
#         (la empresa ya debe existir en Paperclip — crearla primero en la UI)
#
# Automatiza: detección de ID/prefijo, carpetas de knowledge, routing de espejos,
#             mapa del ingest, cron escalonado, colecciones de Outline, doc de Mem0,
#             AGENTS.md esqueleto.
# Imprime guía para lo manual: mounts del compose, plugin LLM Wiki, instrucciones
#             de agentes, limpieza de workspaces clonados.
#
# Doc completo: docs/ONBOARDING_EMPRESA.md

set -euo pipefail

NAME="${1:?Uso: onboard-company.sh \"<NombreEmpresa>\" (debe existir ya en Paperclip)}"
KNOWLEDGE="${HOME}/ai-lab/knowledge"
OPS="${HOME}/ai-lab/ops"
SCRIPTS="${HOME}/ai-lab/scripts"

log() { echo "[onboard] $*"; }

# ── 1. Detectar la empresa en Paperclip ──────────────────────────────────────
ROW=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA \
  -c "SELECT id, issue_prefix FROM companies WHERE name ILIKE '${NAME}';")
[ -z "$ROW" ] && { log "ERROR: empresa '$NAME' no existe en Paperclip. Crearla en la UI primero."; exit 1; }
UUID=$(echo "$ROW" | cut -d'|' -f1)
PREFIX=$(echo "$ROW" | cut -d'|' -f2)
ID8="${UUID:0:8}"
SLUG=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
log "Empresa: $NAME | UUID: $UUID | id8: $ID8 | prefijo: $PREFIX | slug: $SLUG"

# ── 2. ¿Workspaces clonados? (la portabilidad copia contenido de la origen) ──
AGENTS=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA \
  -c "SELECT name, id FROM agents WHERE company_id='${UUID}';")
if [ -n "$AGENTS" ]; then
  log "Agentes existentes:"
  echo "$AGENTS" | sed 's/^/    /'
  while IFS='|' read -r aname aid; do
    CNT=$(docker exec paperclip-server-1 sh -c \
      "ls -A /paperclip/instances/default/workspaces/$aid 2>/dev/null | wc -l" || echo 0)
    if [ "${CNT:-0}" -gt 0 ]; then
      log "⚠️  Workspace de '$aname' tiene $CNT items — si la empresa fue CLONADA, contiene datos de la origen."
      read -rp "    ¿Vaciar workspace de $aname? [s/N] " R
      [ "$R" = "s" ] && docker exec paperclip-server-1 \
        find "/paperclip/instances/default/workspaces/$aid" -mindepth 1 -delete \
        && log "    vaciado ✓"
    fi
  done <<< "$AGENTS"
fi

# ── 3. Carpetas de knowledge ─────────────────────────────────────────────────
mkdir -p "${KNOWLEDGE}/companies/${ID8}"/{deliverables,sessions,wiki}
log "Knowledge: ${KNOWLEDGE}/companies/${ID8}/{deliverables,sessions,wiki} ✓"

# ── 4. Routing del espejo de deliverables (backup-deliverables.sh) ───────────
if ! grep -q "    $PREFIX)" "${OPS}/backup-deliverables.sh"; then
  python3 - "$PREFIX" "$SLUG" "${OPS}/backup-deliverables.sh" << 'PYEOF'
import sys
prefix, slug, path = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
anchor = '    *)   company_dest='
nueva = f'    {prefix}) company_dest="${{HOME}}/ai-lab/ops/deliverables-{slug}" ;;\n'
s = s.replace(anchor, nueva + anchor, 1)
open(path, 'w').write(s)
PYEOF
  log "Routing de espejo: $PREFIX → deliverables-$SLUG ✓"
else
  log "Routing de espejo ya existía ✓"
fi

# ── 5. Mapa del ingest semanal (weekly-ingest.sh) ────────────────────────────
if ! grep -q "  $ID8)" "${SCRIPTS}/weekly-ingest.sh"; then
  python3 - "$ID8" "$SLUG" "${SCRIPTS}/weekly-ingest.sh" << 'PYEOF'
import sys
id8, slug, path = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
anchor = '  *)        DELIVERABLES_DIR='
nueva = f'  {id8}) DELIVERABLES_DIR="$HOME/ai-lab/ops/deliverables-{slug}" ;;\n'
s = s.replace(anchor, nueva + anchor, 1)
open(path, 'w').write(s)
PYEOF
  log "Mapa de ingest: $ID8 → deliverables-$SLUG ✓"
fi
bash -n "${SCRIPTS}/weekly-ingest.sh" && bash -n "${OPS}/backup-deliverables.sh"

# ── 6. Cron escalonado (último ingest + 30 min, mismo domingo) ───────────────
if ! crontab -l 2>/dev/null | grep -q "weekly-ingest.sh $ID8"; then
  LAST_MIN=$(crontab -l | grep "weekly-ingest.sh" | awk '{print $2*60+$1}' | sort -n | tail -1)
  NEW_TOTAL=$(( ${LAST_MIN:-120} + 90 ))
  NH=$((NEW_TOTAL / 60)); NM=$((NEW_TOTAL % 60))
  (crontab -l 2>/dev/null; echo "$NM $NH * * 0 ${SCRIPTS}/weekly-ingest.sh $ID8 >> ${HOME}/ai-lab/logs/ingest-$ID8.log 2>&1") | crontab -
  log "Cron: domingo ${NH}:$(printf '%02d' $NM) ✓"
fi

# ── 7. Colecciones de Outline ────────────────────────────────────────────────
if [ -f "${HOME}/ai-lab/stacks/outline/.apikey" ]; then
  python3 - "$NAME" "$ID8" << 'PYEOF'
import json, sys, urllib.request
name, id8 = sys.argv[1], sys.argv[2]
key = open(f"{__import__('os').environ['HOME']}/ai-lab/stacks/outline/.apikey").read().strip()
def api(path, payload):
    req = urllib.request.Request(f'http://127.0.0.1:3010/api/{path}',
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))['data']
existing = {c['name']: c['id'] for c in api('collections.list', {"limit": 50})}
cname = name
desc = f"Documentación publicada de {name} ({id8})."
if cname not in existing:
    c = api('collections.create', {"name": cname, "description": desc})
    coll_id = c['id']
    print(f"[onboard] Outline: colección '{cname}' → {coll_id}")
else:
    coll_id = existing[cname]
    print(f"[onboard] Outline: '{cname}' ya existía → {coll_id}")
import os
env_file = os.path.expanduser("~/ai-lab/knowledge/.outline-collections.env")
entry = f"OUTLINE_{id8}={coll_id}"
if os.path.exists(env_file):
    content = open(env_file).read()
    if f"OUTLINE_{id8}=" not in content:
        open(env_file, 'a').write(f"\n{entry}\n")
        print(f"[onboard] .outline-collections.env: {entry} agregado")
    else:
        print(f"[onboard] .outline-collections.env: OUTLINE_{id8} ya existía")
else:
    open(env_file, 'w').write(f"{entry}\n")
    print(f"[onboard] .outline-collections.env creado con {entry}")
PYEOF
else
  log "⚠️  Outline .apikey no encontrada — crear colección '$NAME' a mano y registrar UUID en .outline-collections.env"
fi

# ── 7.5 Goal de empresa en Paperclip ─────────────────────────────────────────
GOAL_EXISTS=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA \
  -c "SELECT count(*) FROM goals WHERE company_id = '$UUID' AND level = 'company';")
if [ "$GOAL_EXISTS" = "0" ]; then
  docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
    INSERT INTO goals (id, company_id, title, level, status, created_at, updated_at)
    VALUES (gen_random_uuid(), '$UUID',
      '[COMPLETAR: misión general de $NAME — qué hace, para quién, qué la diferencia]',
      'company', 'active', now(), now());" >/dev/null
  log "Goal de empresa creado (esqueleto) → COMPLETAR el título con la misión real ✓"
else
  log "Goal de empresa ya existe ✓"
fi

# ── 8. Convención Mem0 (documentar el namespace) ─────────────────────────────
NSDOC="${KNOWLEDGE}/shared/templates/mem0-namespacing.md"
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
S2_DEST="${KNOWLEDGE}/shared/templates/prompt-section2-${SLUG}.md"
if [ ! -f "$S2_DEST" ]; then
  sed -e "s/{{COMPANY_NAME}}/$NAME/g" -e "s/{{PREFIX}}/$PREFIX/g" \
    "${KNOWLEDGE}/shared/templates/prompt-section2-template.md" > "$S2_DEST"
  log "S2 prompt: $S2_DEST creado → COMPLETAR descripción de la empresa ✓"
else
  log "S2 prompt: $S2_DEST ya existía ✓"
fi

# ── 9.6 Esqueletos S3 (agent prompts) ───────────────────────────────────────
S3_DIR="${KNOWLEDGE}/shared/templates/prompt-section3"
while IFS='|' read -r aname aid; do
  [ -z "$aname" ] && continue
  aslug=$(echo "$aname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  s3file="${S3_DIR}/${SLUG}-${aslug}.md"
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
AGMD="${KNOWLEDGE}/companies/${ID8}/AGENTS.md"
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
- Todo en español. Commits firmados solo por el equipo, sin co-author de IA.
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

B) backup-deliverables.sh: agregar bloque de sync del dir compartido (copiar el
   bloque de <empresa>-deliverables existente, cambiando $SLUG).

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
   1. Completar ${KNOWLEDGE}/shared/templates/prompt-section2-${SLUG}.md (descripción de empresa)
   2. Completar cada archivo en ${KNOWLEDGE}/shared/templates/prompt-section3/${SLUG}-*.md (roles)
   3. Ejecutar: bash ${SCRIPTS}/deploy-agent-prompts.sh $SLUG
═══════════════════════════════════════════════════════════════════
EOF
log "Onboarding automático completo. Validar con los pasos A-G."
