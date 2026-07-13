#!/usr/bin/env bash
set -euo pipefail

# manifest-guard.sh — Audita que todo archivo de lab-private este clasificado
# en perfil-manifest.yaml (zonas: perfil / instancia / historico / repo).
#
# El modelo lab-seed (manifiesto + extractor) depende de que la clasificacion
# no derive: un archivo nuevo sin zona hace que el proximo seed lo omita (si
# era perfil) o lo arrastre (si era de instancia y cae en un patron amplio).
# Este guard convierte esa deriva en GAP visible:
#
#   1. perfil-manifest.yaml existe en el repo
#   2. Todo archivo trackeado (git ls-files) matchea al menos una zona
#      (comm -23 entre el listado completo y el resolvido por los patrones)
#
# Corre en el DAG lab-guards (domingo) y a mano. Mismo formato que docs-guard.
# Diseno: ~/ai-lab/knowledge/projects/laboratorios-operativos/LAB-SEED-EXTRACCION-PERFIL.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard-lib.sh"

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
REPO="${MANIFEST_GUARD_REPO:-$LAB_DIR/repos/lab-private}"
MANIFEST="$REPO/perfil-manifest.yaml"

guard_init "manifest"

echo "[manifest-guard] $(date -Iseconds) Inicio de auditoria del manifiesto de perfil"

if [ ! -f "$MANIFEST" ]; then
  report_gap "manifiesto" "perfil-manifest.yaml" "no existe en $REPO"
  emit_json >/dev/null
  emit_telegram
  guard_exit_code
  exit 1
fi
report_ok "manifiesto" "perfil-manifest.yaml"

cd "$REPO"

# Patrones de TODAS las zonas (perfil, instancia, historico, repo con y sin seed).
# El manifiesto es deliberadamente plano: listas de strings + bloques path/seed;
# se extrae solo el contenido entre comillas (tolera comentarios inline).
mapfile -t ALL_PATTERNS < <(awk '
  /^  - "/ || /path:/ {
    if (match($0, /"[^"]*"/)) print substr($0, RSTART+1, RLENGTH-2)
  }
' "$MANIFEST")

if [ "${#ALL_PATTERNS[@]}" -eq 0 ]; then
  report_gap "manifiesto" "patrones" "el manifiesto no tiene patrones parseables"
else
  report_ok "manifiesto" "patrones (${#ALL_PATTERNS[@]})"
fi

# Archivos sin clasificar = ls-files completo - ls-files resuelto por los patrones
GAPS="$(comm -23 <(git ls-files | sort) \
                 <(git ls-files -- "${ALL_PATTERNS[@]}" | sort))"

if [ -n "$GAPS" ]; then
  while IFS= read -r f; do
    report_gap "sin-clasificar" "$f" "no matchea ninguna zona de perfil-manifest.yaml — clasificarlo (regla de oro: peligroso en otro servidor=instancia, ya no corre=historico, sirve identico=perfil)"
  done <<< "$GAPS"
else
  TOTAL="$(git ls-files | wc -l)"
  report_ok "clasificacion" "todos los archivos ($TOTAL) matchean una zona"
fi

echo ""
echo "[manifest-guard] Resultados:"
JSON_FILE=$(emit_json)
emit_telegram
echo "[manifest-guard] Reporte JSON: $JSON_FILE"

guard_exit_code
