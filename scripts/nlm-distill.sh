#!/usr/bin/env bash
# Ciclo de destilación batch: cuaderno NLM → knowledge curado de una empresa.
#
# El caso de uso: una empresa llega con AÑOS de documentación. En vez de que los
# agentes la procesen en sesiones (semanas), se sube a un cuaderno de NLM (ingesta
# nativa de PDFs/docs) y este script lo "ordeña" con una batería de preguntas,
# sembrando el knowledge curado en minutos.
#
# Uso:
#   bash nlm-distill.sh <company_id8> <alias_cuaderno> [archivo_preguntas.txt]
#   bash nlm-distill.sh 0424a440 ecosistema
#
# Requiere: NLM Gateway corriendo (el cuaderno debe estar allowlisted para la
# empresa en notebooks.yaml). SIEMPRE gatillado por humano (cookies de NLM).
# Las preguntas: una por línea; línea "## slug" define el nombre del archivo de salida.

set -euo pipefail

COMPANY="${1:?Uso: nlm-distill.sh <company_id8> <alias_cuaderno> [preguntas.txt]}"
ALIAS="${2:?Falta el alias del cuaderno}"
QFILE="${3:-}"
GW="http://127.0.0.1:8770"
KEY=$(grep GATEWAY_API_KEY ~/ai-lab/stacks/nlm-gateway/.env | cut -d= -f2)
OUTDIR="$HOME/ai-lab/knowledge/companies/$COMPANY/research"
FECHA=$(date +%F)

log() { echo "[distill] $*"; }

# Batería default de onboarding si no se pasa archivo
if [ -z "$QFILE" ]; then
  QFILE=$(mktemp)
  cat > "$QFILE" << 'EOF'
## vision-y-valor
¿Qué es esta organización, cuál es su propuesta de valor central y qué problema resuelve? Incluye su filosofía o principios rectores.
## productos-servicios
Describe todos los productos, servicios y componentes del ecosistema: qué hace cada uno, cómo se relacionan, y su estado de madurez.
## clientes-mercado
¿Quiénes son los clientes e implementaciones (activas e históricas), en qué verticales, y qué resultados se obtuvieron en cada caso?
## metodologia-procesos
¿Qué metodologías y procesos de trabajo usa la organización (implementación, capacitación, ventas)? Detalla fases, tiempos y entregables.
## decisiones-y-lecciones
¿Qué decisiones estratégicas o técnicas importantes se tomaron, por qué, y qué lecciones o errores documentados existen?
## terminologia
Lista la terminología y conceptos propios de la organización con su definición (glosario para que un agente nuevo hable el idioma de la empresa).
EOF
  TEMP_Q=1
else
  TEMP_Q=0
fi

mkdir -p "$OUTDIR"
log "Empresa: $COMPANY | Cuaderno: $ALIAS | Salida: $OUTDIR"

# Verificar gateway y permiso
curl -sf "$GW/health" >/dev/null || { log "ERROR: gateway no responde — arrancarlo con ~/ai-lab/stacks/nlm-gateway/start.sh"; exit 1; }

SLUG=""; Q=""; OK=0; FAIL=0
process() {
  [ -z "$SLUG" ] || [ -z "$Q" ] && return 0
  local out="$OUTDIR/${ALIAS}-${SLUG}.md"
  log "→ $SLUG"
  RESP=$(curl -s -m 180 -X POST "$GW/companies/$COMPANY/query" \
    -H "X-API-Key: $KEY" -H "Content-Type: application/json" \
    --data "$(python3 -c "import json,sys; print(json.dumps({'notebook':'$ALIAS','question':sys.argv[1]}))" "$Q")")
  ANSWER=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('answer',''))" 2>/dev/null || true)
  if [ -z "$ANSWER" ]; then
    log "  ✗ falló: $(echo "$RESP" | head -c 150)"; FAIL=$((FAIL+1)); return 0
  fi
  {
    echo "---"
    echo "source: notebooklm"
    echo "notebook_alias: $ALIAS"
    echo "company_id: $COMPANY"
    echo "date: $FECHA"
    echo "question: \"$(echo "$Q" | head -c 150)\""
    echo "---"
    echo ""
    echo "$ANSWER"
  } > "$out"
  log "  ✓ $out ($(wc -w < "$out") palabras)"
  OK=$((OK+1))
  sleep 3   # respirar entre consultas (rate limit + cortesía con NLM)
}

while IFS= read -r line; do
  case "$line" in
    "## "*) process; SLUG="${line#\#\# }"; Q="" ;;
    "") ;;
    *) Q="$Q $line" ;;
  esac
done < "$QFILE"
process
[ "$TEMP_Q" = "1" ] && rm -f "$QFILE"

# Índice del research
{
  echo "# Research destilado de NLM — empresa $COMPANY"
  echo ""
  for f in "$OUTDIR"/*.md; do
    [ "$(basename "$f")" = "index.md" ] && continue
    echo "- [$(basename "$f" .md)]($(basename "$f"))"
  done
} > "$OUTDIR/index.md"

log "Completado: $OK ok, $FAIL fallidas. Índice: $OUTDIR/index.md"
log "Recordá: revisión humana de 15 min (es semilla de knowledge) y avisarle a los"
log "agentes vía AGENTS.md si el material es fundacional."
