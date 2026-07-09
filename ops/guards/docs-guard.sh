#!/usr/bin/env bash
set -euo pipefail

# docs-guard.sh — Audita que la documentación esté enlazada en su índice.
#
# La documentación es la estructura viva del sistema: un doc que existe pero
# no está enlazado en el README de su repo es conocimiento huérfano — nadie
# lo encuentra, nadie lo mantiene, y se degrada en silencio. Este guard hace
# determinista esa disciplina:
#
#   1. Todo docs/*.md de cada repo debe estar referenciado en su README.md
#   2. Todo enlace a docs/*.md en el README debe apuntar a un archivo existente
#      (sin enlaces rotos)
#
# Corre en el DAG lab-guards (domingo) y a mano. Mismo formato que core-guard.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard-lib.sh"

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
# Repos propios con docs/ — los de terceros (odysseus, paperclip) no se auditan
REPOS="${DOCS_GUARD_REPOS:-$LAB_DIR/repos/ai-lab-bootstrap $LAB_DIR/repos/lab-private}"

guard_init "docs"

echo "[docs-guard] $(date -Iseconds) Inicio de auditoría documental"

for REPO in $REPOS; do
  [ -d "$REPO/docs" ] || continue
  RNAME=$(basename "$REPO")
  README="$REPO/README.md"

  if [ ! -f "$README" ]; then
    report_gap "docs-index" "$RNAME" "no tiene README.md"
    continue
  fi

  # 1. Docs sin enlace en el índice
  for f in "$REPO"/docs/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if grep -q "$name" "$README"; then
      report_ok "doc-enlazado" "$RNAME/$name"
    else
      report_gap "doc-enlazado" "$RNAME/$name" "existe pero no está en el README — enlazarlo en la tabla de documentación"
    fi
  done

  # 2. Enlaces del README a docs/ que apuntan a archivos inexistentes
  while IFS= read -r linked; do
    [ -z "$linked" ] && continue
    if [ -f "$REPO/docs/$linked" ]; then
      report_ok "enlace-valido" "$RNAME/$linked"
    else
      report_gap "enlace-valido" "$RNAME/$linked" "el README lo enlaza pero el archivo no existe en docs/"
    fi
  done < <(grep -oE 'docs/[A-Za-z0-9_.-]+\.md' "$README" | sed 's|^docs/||' | sort -u)
done

echo ""
echo "[docs-guard] Resultados:"
JSON_FILE=$(emit_json)
emit_telegram
echo "[docs-guard] Reporte JSON: $JSON_FILE"

guard_exit_code
