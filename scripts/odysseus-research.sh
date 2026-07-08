#!/usr/bin/env bash
# odysseus-research.sh — Lanza Deep Research en Odysseus y lee resultados.
# Arquitectura v2 (plan integración §6C): comandos entran por docker exec +
# internal token (Bearer NO funciona: require_user() rechaza API tokens con 403);
# resultados salen por filesystem (deep_research/rp-*.json montado en el host).
#
# Uso:
#   odysseus-research.sh start "<query>" [max_time_seg]   → imprime session_id
#   odysseus-research.sh status <rp-id>                   → imprime status
#   odysseus-research.sh wait <rp-id> [timeout_seg]       → poll hasta done/error
#   odysseus-research.sh report <rp-id>                   → imprime el informe MD
#
# Requiere: ODYSSEUS_INTERNAL_TOKEN fijado en ~/ai-lab/stacks/odysseus/.env
# (compose lo inyecta al contenedor). La atribución X-Odysseus-Owner: admin hace
# que el research aparezca en la UI del operador como propio.

set -euo pipefail

CONTAINER="odysseus"
DATA_DIR="$HOME/ai-lab/data/core/odysseus/data/deep_research"
OWNER="${ODYSSEUS_OWNER:-admin}"

die() { echo "[odysseus-research] ERROR: $*" >&2; exit 1; }

api() {
  # api <método> <ruta> [json_body] — curl dentro del contenedor con internal token
  local method="$1" path="$2" body="${3:-}"
  docker exec -e M="$method" -e P="$path" -e B="$body" -e OWNER="$OWNER" "$CONTAINER" sh -c '
    curl -s -X "$M" \
      -H "X-Odysseus-Internal-Token: $ODYSSEUS_INTERNAL_TOKEN" \
      -H "X-Odysseus-Owner: $OWNER" \
      -H "Content-Type: application/json" \
      ${B:+-d "$B"} \
      "http://localhost:7000$P"'
}

cmd="${1:?Uso: odysseus-research.sh start|status|wait|report ...}"
shift

case "$cmd" in
  start)
    QUERY="${1:?falta la query}"
    MAX_TIME="${2:-600}"
    BODY=$(python3 -c "import json,sys; print(json.dumps({'query': sys.argv[1], 'max_time': int(sys.argv[2])}))" "$QUERY" "$MAX_TIME")
    RESP=$(api POST /api/research/start "$BODY")
    SID=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)
    [ -n "$SID" ] || die "no se obtuvo session_id — respuesta: $(echo "$RESP" | head -c 300)"
    echo "$SID"
    ;;

  status)
    SID="${1:?falta el rp-id}"
    F="$DATA_DIR/$SID.json"
    if [ -f "$F" ]; then
      python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status','?'))" "$F"
    else
      # Aún no persistió a disco — consultar la API
      api GET "/api/research/status/$SID" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','pending'))" 2>/dev/null || echo "pending"
    fi
    ;;

  wait)
    SID="${1:?falta el rp-id}"
    TIMEOUT="${2:-1200}"
    ELAPSED=0
    while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
      ST=$("$0" status "$SID")
      case "$ST" in
        done|error|cancelled) echo "$ST"; exit 0 ;;
      esac
      sleep 15; ELAPSED=$((ELAPSED + 15))
    done
    echo "timeout"; exit 1
    ;;

  report)
    SID="${1:?falta el rp-id}"
    F="$DATA_DIR/$SID.json"
    [ -f "$F" ] || die "no existe $F"
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get('raw_report') or d.get('result') or '(sin informe)')" "$F"
    ;;

  *) die "comando desconocido: $cmd" ;;
esac
