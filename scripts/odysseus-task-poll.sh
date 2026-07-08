#!/usr/bin/env bash
# odysseus-task-poll.sh — Estado de tareas programadas + research activo de Odysseus.
# Reescrito 2026-07-08 con el plano de control v2 (la versión Bearer estaba rota: 403).
# Comandos: docker exec + internal token + X-Odysseus-Owner. Estado: filesystem.
#
# Uso: odysseus-task-poll.sh [--status <filtro>] [--quiet]
# Escribe ~/ai-lab/knowledge/.state/odysseus-poll.json (atómico) y reporta cambios
# respecto a la corrida anterior por stdout.

set -euo pipefail

CONTAINER="odysseus"
OWNER="${ODYSSEUS_OWNER:-admin}"
STATE_FILE="$HOME/ai-lab/knowledge/.state/odysseus-poll.json"
STATUS_FILTER=""
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) STATUS_FILTER="$2"; shift 2 ;;
    --quiet)  QUIET=true; shift ;;
    *) echo "arg desconocido: $1" >&2; exit 1 ;;
  esac
done

api() {
  local path="$1"
  docker exec -e P="$path" -e OWNER="$OWNER" "$CONTAINER" sh -c '
    curl -s -H "X-Odysseus-Internal-Token: $ODYSSEUS_INTERNAL_TOKEN" \
         -H "X-Odysseus-Owner: $OWNER" "http://localhost:7000$P"'
}

TASKS=$(api "/api/tasks${STATUS_FILTER:+?status=$STATUS_FILTER}")
RESEARCH=$(api "/api/research/active")

STATE_FILE="$STATE_FILE" QUIET="$QUIET" python3 - "$TASKS" "$RESEARCH" << 'PYEOF'
import json, os, sys, tempfile, datetime

state_file = os.environ["STATE_FILE"]
quiet = os.environ.get("QUIET") == "true"

def parse(raw):
    try:
        return json.loads(raw or "{}")
    except Exception:
        return {}

tasks_raw = parse(sys.argv[1])
research_raw = parse(sys.argv[2])

tasks = tasks_raw if isinstance(tasks_raw, list) else (tasks_raw.get("tasks") or [])
research = research_raw if isinstance(research_raw, list) else (research_raw.get("active") or research_raw.get("sessions") or [])

now = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "tasks": {str(t.get("id")): {"name": t.get("name") or t.get("title") or "?",
                                  "status": t.get("status") or ("enabled" if t.get("enabled") else "disabled")}
              for t in tasks if isinstance(t, dict)},
    "research_active": [r.get("session_id") or r.get("id") for r in research if isinstance(r, dict)],
}

try:
    prev = json.load(open(state_file))
except Exception:
    prev = {"tasks": {}, "research_active": []}

changes = []
for tid, t in now["tasks"].items():
    p = prev.get("tasks", {}).get(tid)
    if p is None:
        changes.append(f"+ tarea nueva: {t['name']} ({t['status']})")
    elif p.get("status") != t["status"]:
        changes.append(f"~ {t['name']}: {p.get('status')} → {t['status']}")
for tid, p in prev.get("tasks", {}).items():
    if tid not in now["tasks"]:
        changes.append(f"- tarea eliminada: {p.get('name')}")
for rid in now["research_active"]:
    if rid not in prev.get("research_active", []):
        changes.append(f"+ research activo: {rid}")

os.makedirs(os.path.dirname(state_file), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(state_file))
with os.fdopen(fd, "w") as f:
    json.dump(now, f, indent=1, ensure_ascii=False)
os.replace(tmp, state_file)

if not quiet:
    print(f"[odysseus-task-poll] {len(now['tasks'])} tarea(s), {len(now['research_active'])} research activo(s)")
    for c in changes:
        print(f"  {c}")
    if not changes:
        print("  sin cambios desde la última corrida")
PYEOF
