#!/usr/bin/env bash
# odysseus-email-check.sh — Consulta emails vía Odysseus y exporta un triage MD.
# Reescrito 2026-07-08 con el plano de control v2 (la versión Bearer estaba rota:
# los endpoints de email exigen usuario y rechazan API tokens con 403).
# Comandos: docker exec + internal token + X-Odysseus-Owner. Salida: filesystem.
#
# Uso: odysseus-email-check.sh [--filter unread|all|unanswered] [--limit 20]
#                              [--folder INBOX] [--out <dir>]
# Sin cuentas de email configuradas en Odysseus, sale limpio con aviso (cron-safe).

set -euo pipefail

CONTAINER="odysseus"
OWNER="${ODYSSEUS_OWNER:-admin}"
FILTER="unread"
LIMIT=20
FOLDER="INBOX"
OUT_DIR="$HOME/ai-lab/knowledge/daily"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) FILTER="$2"; shift 2 ;;
    --limit)  LIMIT="$2"; shift 2 ;;
    --folder) FOLDER="$2"; shift 2 ;;
    --out)    OUT_DIR="$2"; shift 2 ;;
    *) echo "arg desconocido: $1" >&2; exit 1 ;;
  esac
done

api() {
  local path="$1"
  docker exec -e P="$path" -e OWNER="$OWNER" "$CONTAINER" sh -c '
    curl -s -H "X-Odysseus-Internal-Token: $ODYSSEUS_INTERNAL_TOKEN" \
         -H "X-Odysseus-Owner: $OWNER" "http://localhost:7000$P"'
}

# ¿Hay cuentas configuradas?
N_ACCOUNTS=$(api "/api/email/accounts" | python3 -c "
import json, sys
try:
    print(len(json.load(sys.stdin).get('accounts', [])))
except Exception:
    print(0)")
if [ "${N_ACCOUNTS:-0}" = "0" ]; then
  echo "[odysseus-email-check] Sin cuentas de email configuradas en Odysseus — nada que consultar."
  exit 0
fi

RESP=$(api "/api/email/list?folder=${FOLDER}&filter=${FILTER}&limit=${LIMIT}")
mkdir -p "$OUT_DIR"
TMP=$(mktemp -p "$OUT_DIR" .harvest-XXXXXX)  # mismo FS que el destino → mv atómico (§5.4)
FILTER="$FILTER" FOLDER="$FOLDER" python3 -c "
import json, sys, os, datetime
d = json.loads(sys.stdin.read() or '{}')
emails = d.get('emails') or d.get('messages') or []
now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
print(f'# Email triage — {now}')
print(f\"\nFiltro: {os.environ['FILTER']} | Folder: {os.environ['FOLDER']} | {len(emails)} mensaje(s)\n\")
for e in emails:
    frm = e.get('from') or e.get('from_addr') or '?'
    subj = e.get('subject') or '(sin asunto)'
    date = (e.get('date') or '')[:16]
    print(f'- **{subj}** — {frm} ({date})')
" <<< "$RESP" > "$TMP"

mkdir -p "$OUT_DIR"
DEST="$OUT_DIR/$(date +%Y-%m-%d)_email-triage.md"
mv "$TMP" "$DEST"
echo "[odysseus-email-check] Triage en $DEST"
