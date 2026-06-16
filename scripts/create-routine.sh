#!/bin/bash
set -euo pipefail

# Create a Paperclip routine with trigger and revision via DB.
# Usage: create-routine.sh <company_prefix_or_uuid> <agent_name> <title> <cron_expr> [priority] [description]
#
# Example:
#   create-routine.sh ALM CEO "Informe semanal" "0 9 * * 1"
#   create-routine.sh KAT "Content Producer" "Producir módulo" "0 8 * * 1" high "Descripción larga"
#   create-routine.sh <uuid> CTO "Revisión técnica" "0 10 1 * *" medium "Revisión mensual"
#
# El prefijo de empresa se resuelve contra la DB. Si no coincide con ningún prefijo,
# se trata el valor directamente como UUID de empresa.

TIMEZONE="${PAPERCLIP_TIMEZONE:-America/Costa_Rica}"
DB_CMD="docker exec paperclip-db-1 psql -U paperclip -d paperclip -tA"

if [ $# -lt 4 ]; then
  echo "Usage: $0 <company_prefix_or_uuid> <agent_name> <title> <cron_expr> [priority] [description]"
  echo ""
  echo "Company prefix: issue_prefix de la empresa en DB (ej. ALM, KAT) o UUID completo"
  echo "Agent name: nombre exacto del agente en Paperclip"
  echo "Cron: expresión estándar de 5 campos (ej. '0 9 * * 1' = lunes 09:00)"
  echo "Priority: low, medium (default), high, critical"
  echo ""
  echo "Empresas disponibles:"
  $DB_CMD -c "SELECT issue_prefix, name, id FROM companies ORDER BY issue_prefix;" 2>/dev/null || true
  exit 1
fi

PREFIX="$1"
AGENT_NAME="$2"
TITLE="$3"
CRON_EXPR="$4"
PRIORITY="${5:-medium}"
DESCRIPTION="${6:-$TITLE}"

# Resolver empresa: primero buscar por issue_prefix en DB; si no hay match, usar como UUID directamente
COMPANY_ROW=$($DB_CMD -c "SELECT id FROM companies WHERE issue_prefix='${PREFIX}' LIMIT 1;" 2>/dev/null || true)
if [ -n "$COMPANY_ROW" ]; then
  COMPANY_ID="$COMPANY_ROW"
else
  # Asumir que PREFIX es un UUID directo
  COMPANY_ID="$PREFIX"
fi

# Resolver agente
AGENT_ID=$($DB_CMD -c "SELECT id FROM agents WHERE company_id='$COMPANY_ID' AND name='$AGENT_NAME' LIMIT 1;")
if [ -z "$AGENT_ID" ]; then
  echo "ERROR: Agent '$AGENT_NAME' not found in company $PREFIX ($COMPANY_ID)"
  echo "Available agents:"
  $DB_CMD -c "SELECT name FROM agents WHERE company_id='$COMPANY_ID' ORDER BY name;"
  exit 1
fi

# Calcular next_run_at
NEXT_RUN=$(python3 -c "
from datetime import datetime, timedelta, timezone as tz
from zoneinfo import ZoneInfo

cron = '$CRON_EXPR'.split()
minute, hour = int(cron[0]), int(cron[1])
dom, month_f, dow_f = cron[2], cron[3], cron[4]

local_tz = ZoneInfo('$TIMEZONE')
now = datetime.now(local_tz)

if dow_f != '*':
    dow = int(dow_f)
    target_py = (dow - 1) % 7
    days_ahead = (target_py - now.weekday()) % 7
    candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0) + timedelta(days=days_ahead)
    if candidate <= now:
        candidate += timedelta(days=7)
elif dom != '*':
    d = int(dom)
    candidate = now.replace(day=d, hour=hour, minute=minute, second=0, microsecond=0)
    if candidate <= now:
        m = candidate.month + 1
        y = candidate.year + (1 if m > 12 else 0)
        m = m if m <= 12 else 1
        candidate = candidate.replace(year=y, month=m)
else:
    candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if candidate <= now:
        candidate += timedelta(days=1)

print(candidate.astimezone(tz.utc).strftime('%Y-%m-%dT%H:%M:%S+00:00'))
")

echo "Creating routine..."
echo "  Company: $PREFIX ($COMPANY_ID)"
echo "  Agent:   $AGENT_NAME ($AGENT_ID)"
echo "  Title:   $TITLE"
echo "  Cron:    $CRON_EXPR ($TIMEZONE)"
echo "  Next:    $NEXT_RUN"
echo "  Priority: $PRIORITY"
echo ""

# Generar UUIDs
ROUTINE_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
TRIGGER_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
REVISION_ID=$(python3 -c "import uuid; print(uuid.uuid4())")

# Crear routine
$DB_CMD -c "
INSERT INTO routines (id, company_id, title, description, assignee_agent_id, priority, status, variables)
VALUES ('$ROUTINE_ID', '$COMPANY_ID', '$TITLE', '$DESCRIPTION', '$AGENT_ID', '$PRIORITY', 'active', '[]');
"

# Crear trigger con next_run_at
$DB_CMD -c "
INSERT INTO routine_triggers (id, company_id, routine_id, kind, label, enabled, cron_expression, timezone, next_run_at)
VALUES ('$TRIGGER_ID', '$COMPANY_ID', '$ROUTINE_ID', 'cron', '$CRON_EXPR ($TIMEZONE)', true, '$CRON_EXPR', '$TIMEZONE', '$NEXT_RUN');
"

# Crear revisión inicial
SNAPSHOT=$(python3 -c "
import json
print(json.dumps({'issue_template': {'title': '$TITLE', 'priority': '$PRIORITY', 'status': 'todo'}}))
")

$DB_CMD -c "
INSERT INTO routine_revisions (id, company_id, routine_id, revision_number, title, description, snapshot, change_summary)
VALUES ('$REVISION_ID', '$COMPANY_ID', '$ROUTINE_ID', 1, '$TITLE', '$DESCRIPTION', '$SNAPSHOT', 'Creación inicial');
"

# Vincular revisión
$DB_CMD -c "
UPDATE routines SET latest_revision_id = '$REVISION_ID' WHERE id = '$ROUTINE_ID';
"

echo "Routine created:"
echo "  routine_id:  $ROUTINE_ID"
echo "  trigger_id:  $TRIGGER_ID"
echo "  revision_id: $REVISION_ID"
echo "  next_run_at: $NEXT_RUN"
