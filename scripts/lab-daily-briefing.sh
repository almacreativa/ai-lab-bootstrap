#!/usr/bin/env bash
# lab-daily-briefing.sh — Briefing diario de infraestructura del lab
# Modo no-agent: recolecta datos y los entrega como texto plano.
# Si detecta anomalías, dispara análisis agent via hermes chat -q.
# Cron Hermes: --no-agent --script lab-daily-briefing.sh

set -uo pipefail

DAGU_BIN="$HOME/.local/bin/dagu"
HERMES_BIN="$HOME/.hermes-env/bin/hermes"
NOTIFY="$HOME/ai-lab/scripts/telegram-notify.sh"
NOW=$(date '+%Y-%m-%d %H:%M')
ALERTS=""
ALERT_COUNT=0

add_alert() {
  ALERTS="${ALERTS}\n⚠️ $1"
  ALERT_COUNT=$((ALERT_COUNT + 1))
}

echo "📊 **Lab Daily Briefing** — $NOW"
echo ""

# ── 1. Dagu: resumen de las últimas 24h ──
echo "**Dagu — Últimas 24h**"

DAGU_JSON=$($DAGU_BIN history --last 24h --format json 2>/dev/null) || DAGU_JSON="[]"

DAGU_SUMMARY=$(DAGU_DATA="$DAGU_JSON" python3 << 'PYEOF'
import json, os
from collections import Counter, defaultdict

data = json.loads(os.environ.get('DAGU_DATA', '[]'))
if not data:
    print("Sin datos de ejecución")
else:
    total = len(data)
    statuses = Counter(d.get('status', 'unknown') for d in data)
    succeeded = statuses.get('succeeded', 0)
    failed = statuses.get('failed', 0)
    other = total - succeeded - failed

    print(f"Total runs: {total} — ✅ {succeeded} ok, ❌ {failed} fallos", end="")
    if other > 0:
        print(f", ⏳ {other} otros", end="")
    print()

    by_dag = defaultdict(lambda: {"ok": 0, "fail": 0, "last": ""})
    for d in data:
        name = d.get('name', '?')
        status = d.get('status', '')
        by_dag[name]["ok" if status == "succeeded" else "fail"] += 1
        started = d.get('startedAt', '')
        if started > by_dag[name]["last"]:
            by_dag[name]["last"] = started

    for name in sorted(by_dag):
        s = by_dag[name]
        marker = "✅" if s["fail"] == 0 else "❌"
        last_short = s["last"][:16].replace("T", " ") if s["last"] else "—"
        line = f"  {marker} {name}: {s['ok']} ok"
        if s["fail"] > 0:
            line += f", {s['fail']} fallos"
        line += f" (último: {last_short})"
        print(line)

    failed_dags = [name for name, s in by_dag.items() if s["fail"] > 0]
    if failed_dags:
        print(f"FAILED_DAGS:{','.join(failed_dags)}")
PYEOF
)

echo "$DAGU_SUMMARY" | grep -v '^FAILED_DAGS:'
FAILED_DAGS=$(echo "$DAGU_SUMMARY" | grep '^FAILED_DAGS:' | cut -d: -f2)

if [ -n "$FAILED_DAGS" ]; then
  add_alert "DAGs con fallos: $FAILED_DAGS"
fi

echo ""

# ── 2. Servicios systemd ──
echo "**Servicios systemd**"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

for svc in dagu nlm-gateway; do
  STATUS=$(systemctl --user is-active "$svc" 2>/dev/null) || STATUS="unknown"
  if [ "$STATUS" = "active" ]; then
    echo "  ✅ $svc (systemd user)"
  else
    echo "  ❌ $svc: $STATUS"
    add_alert "Servicio $svc: $STATUS"
  fi
done

for svc in hermes; do
  STATUS=$(systemctl is-active "$svc" 2>/dev/null) || STATUS="unknown"
  if [ "$STATUS" = "active" ]; then
    echo "  ✅ $svc (systemd)"
  else
    echo "  ❌ $svc: $STATUS"
    add_alert "Servicio $svc: $STATUS"
  fi
done

PCP_STATUS=$(docker inspect -f '{{.State.Status}}' paperclip-server-1 2>/dev/null) || PCP_STATUS="not found"
if [ "$PCP_STATUS" = "running" ]; then
  echo "  ✅ paperclip (docker)"
else
  echo "  ❌ paperclip: $PCP_STATUS"
  add_alert "Paperclip container: $PCP_STATUS"
fi

# Docker containers
DOCKER_DOWN=$(docker ps --filter "status=exited" --format '{{.Names}}' 2>/dev/null | grep -E 'paperclip|outline|kuma|mem0|ollama' || true)
if [ -n "$DOCKER_DOWN" ]; then
  echo "  ❌ Contenedores caídos: $DOCKER_DOWN"
  add_alert "Contenedores caídos: $DOCKER_DOWN"
else
  CONTAINER_COUNT=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)
  echo "  ✅ Docker: $CONTAINER_COUNT contenedores activos"
fi

echo ""

# ── 3. Sistema ──
echo "**Sistema**"

DISK_USAGE=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
RAM_USAGE=$(free -m | awk 'NR==2{printf "%.0f", $3/$2*100}')
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //')

echo "  Disco: ${DISK_USAGE}% | RAM: ${RAM_USAGE}% | Uptime: $UPTIME"

if [ "$DISK_USAGE" -gt 85 ]; then
  add_alert "Disco al ${DISK_USAGE}%"
fi
if [ "$RAM_USAGE" -gt 90 ]; then
  add_alert "RAM al ${RAM_USAGE}%"
fi

echo ""

# ── 4. Hermes crons ──
echo "**Hermes crons**"
HERMES_CRON_STATUS=$($HERMES_BIN cron status 2>&1 | head -3) || HERMES_CRON_STATUS="No disponible"
echo "  $HERMES_CRON_STATUS"

echo ""

# ── 5. Alertas ──
if [ "$ALERT_COUNT" -gt 0 ]; then
  echo "**⚠️ ${ALERT_COUNT} alerta(s) detectada(s):**"
  echo -e "$ALERTS"
  echo ""

  ALERT_PROMPT="Analizá las siguientes alertas del lab y decime qué acción tomar para cada una. Sé breve y directo. Usá la herramienta mcp_dagu_read si necesitás más detalle de algún DAG fallido.

Alertas:
$(echo -e "$ALERTS")

Contexto: los DAGs corren en Dagu, los servicios son systemd user-level. Los scripts están en ~/ai-lab/scripts/."

  $HERMES_BIN chat -q "$ALERT_PROMPT" --deliver origin 2>/dev/null &
  echo "_Análisis con agente disparado._"
else
  echo "✅ **Todo operativo.** Sin alertas."
fi
