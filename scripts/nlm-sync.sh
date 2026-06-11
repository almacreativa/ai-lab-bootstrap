#!/usr/bin/env bash
# Sync semi-manual del knowledge de una empresa a su cuaderno de NotebookLM (Fase 5).
#
# SIEMPRE gatillado por un humano (las cookies de NLM expiran ~14 días — este
# script NUNCA va en cron, decisión cerrada del plan).
#
# Uso:   bash nlm-sync.sh <company_id> <notebook_id>
# Alma:  bash nlm-sync.sh <company-id> <id del cuaderno "<Empresa A> — Conocimiento Acumulado">
#
# Estrategia: borra las fuentes file-* previas del cuaderno y resube las actuales
# (NLM no actualiza fuentes in-place; resubir evita duplicados).

set -euo pipefail

COMPANY_ID="${1:?Uso: nlm-sync.sh <company_id> <notebook_id>}"
NOTEBOOK_ID="${2:?Falta notebook_id}"
KNOWLEDGE_DIR="$HOME/ai-lab/knowledge/companies/${COMPANY_ID}"
NLM="$HOME/.local/bin/nlm"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── Verificación de auth (falla elegante, no se cuelga) ──────────────────────
if ! timeout 30 "$NLM" notebook list >/dev/null 2>&1; then
  log "ERROR: NLM no responde — cookies probablemente expiradas."
  log "Solución: ejecutá 'nlm login' y volvé a correr este script."
  exit 1
fi

# ── Archivos a sincronizar (los de mayor densidad; nunca transcripts raw) ────
FILES=()
for f in \
  "$KNOWLEDGE_DIR/AGENTS.md" \
  "$KNOWLEDGE_DIR/patterns.md" \
  "$KNOWLEDGE_DIR/sessions/index.md" \
  "$KNOWLEDGE_DIR/sessions/insights.md"; do
  [ -f "$f" ] && FILES+=("$f") || log "WARN: no existe $f — se omite"
done

if [ ${#FILES[@]} -eq 0 ]; then
  log "ERROR: no hay archivos para sincronizar en $KNOWLEDGE_DIR. ¿Corrió el ingest (Fase 3)?"
  exit 1
fi

# ── Limpiar versiones anteriores de estos archivos en el cuaderno ────────────
log "Buscando fuentes previas a reemplazar..."
EXISTING=$("$NLM" source list "$NOTEBOOK_ID" 2>/dev/null || true)
for f in "${FILES[@]}"; do
  base=$(basename "$f")
  # IDs de fuentes cuyo título coincide con el archivo (formato tabla del CLI)
  ids=$(echo "$EXISTING" | grep -F "$base" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' || true)
  for id in $ids; do
    log "  Borrando fuente previa: $base ($id)"
    "$NLM" source delete "$id" --confirm || log "  WARN: no se pudo borrar $id"
  done
done

# ── Subir versiones actuales ─────────────────────────────────────────────────
OK=0; FAIL=0
for f in "${FILES[@]}"; do
  log "Subiendo: $f"
  if timeout 120 "$NLM" source add "$NOTEBOOK_ID" --file "$f" --title "$(basename "$f") [${COMPANY_ID}]"; then
    OK=$((OK+1))
  else
    FAIL=$((FAIL+1)); log "  WARN: fallo la subida de $f — continuando"
  fi
done

log "Sync completado: $OK subidos, $FAIL fallidos."
log "Validación: hacé 2-3 preguntas de prueba en el cuaderno (notebook_query o web UI)."
[ "$FAIL" -eq 0 ]
