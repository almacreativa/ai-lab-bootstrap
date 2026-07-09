#!/usr/bin/env python3
"""odysseus-library-mirror.py — Espeja el knowledge curado del hub en la Library de Odysseus.

Resuelve el gap de UX: la Library es el entorno natural de navegación del
operador, pero por diseño de la app solo muestra su SQLite interno — los
mounts de knowledge/ no aparecen ahí. Este espejo usa la PROPIA API de la
Library (POST/PUT /api/document, con versionamiento nativo) — cero cambios
al código de Odysseus.

Dirección ÚNICA: hub → Library (la Library es una lente, no fuente de verdad).
Cada documento lleva un banner que lo aclara. Si alguien edita la copia en
Library, el próximo cambio del archivo del hub la pisa — pero el versionamiento
de la Library conserva esa edición como versión anterior (recuperable).

Alcance curado (configurable en SCOPE): el conocimiento del lab navegable,
no el bulk de outputs/wikis (eso lo cubre el RAG + modo agente).

Incremental por mtime; update salta si el contenido es idéntico (dedup de la
propia API). Archivos eliminados del hub → soft-archive en Library.
Corre como paso del DAG knowledge-harvest.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
KNOWLEDGE = HOME / "ai-lab/knowledge"
STATE_FILE = KNOWLEDGE / ".state/odysseus-library-mirror.json"
CONTAINER = "odysseus"
OWNER = "admin"

# (carpeta_relativa, recursivo, etiqueta)
SCOPE = [
    ("projects", True, "projects"),
    ("research", True, "research"),
    ("daily", True, "daily"),
    ("shared", False, "shared"),               # solo nivel superior — las mesas de trabajo no
    ("alma/outputs/db-documents", True, "alma"),
    ("katun/outputs/db-documents", True, "katun"),
    ("expansia/outputs/db-documents", True, "expansia"),
]

BANNER = ("> 🔄 **Espejo del hub** — fuente de verdad: `knowledge/{rel}`. "
          "Editá desde la Mac (Obsidian) o pidiéndoselo a Hermes/al agente. "
          "Los cambios hechos aquí en la Library NO vuelven al hub "
          "(quedan como versión recuperable si el archivo cambia).\n\n")


def api(method, path, payload=None):
    """Llama a la API de Odysseus dentro del contenedor (internal token)."""
    cmd = ["docker", "exec", "-e", f"P={path}", "-e", f"M={method}",
           "-e", f"OWNER={OWNER}", "-i", CONTAINER, "sh", "-c",
           'curl -s -X "$M" -H "X-Odysseus-Internal-Token: $ODYSSEUS_INTERNAL_TOKEN" '
           '-H "X-Odysseus-Owner: $OWNER" -H "Content-Type: application/json" '
           '--data-binary @- "http://localhost:7000$P"']
    data = json.dumps(payload or {}).encode()
    r = subprocess.run(cmd, input=data, capture_output=True, timeout=60)
    try:
        return json.loads(r.stdout.decode() or "{}")
    except Exception:
        return {"_raw": r.stdout.decode()[:200]}


def iter_files():
    for rel_dir, recursive, label in SCOPE:
        base = KNOWLEDGE / rel_dir
        if not base.is_dir():
            continue
        pattern = "**/*.md" if recursive else "*.md"
        for f in sorted(base.glob(pattern)):
            if ".sync-conflict-" in f.name or "/templates/" in str(f):
                continue
            rel = str(f.relative_to(KNOWLEDGE))
            yield rel, f, label


def title_for(rel, label):
    name = Path(rel).stem.replace("-", " ").replace("_", " · ", 1)
    return f"[{label}] {name}"


def main():
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        state = json.loads(STATE_FILE.read_text())
    except Exception:
        state = {}

    created = updated = archived = unchanged = failed = 0
    seen = set()

    for rel, f, label in iter_files():
        seen.add(rel)
        try:
            mtime = f.stat().st_mtime
        except OSError:
            continue
        entry = state.get(rel)
        if entry and entry.get("mtime") == mtime:
            unchanged += 1
            continue
        try:
            content = BANNER.format(rel=rel) + f.read_text(encoding="utf-8")
        except Exception:
            failed += 1
            continue

        if entry and entry.get("doc_id"):
            resp = api("PUT", f"/api/document/{entry['doc_id']}",
                       {"content": content, "summary": "sync del hub"})
            if resp.get("id"):
                state[rel] = {"doc_id": entry["doc_id"], "mtime": mtime}
                updated += 1
            else:
                # el doc pudo haber sido borrado en la UI — recrear
                entry = None
        if not entry:
            resp = api("POST", "/api/document",
                       {"title": title_for(rel, label), "content": content,
                        "language": "markdown"})
            doc_id = resp.get("id")
            if doc_id:
                state[rel] = {"doc_id": doc_id, "mtime": mtime}
                created += 1
            else:
                failed += 1

    # Archivos que desaparecieron del hub → soft-archive en Library
    for rel in [r for r in list(state) if r not in seen]:
        doc_id = state[rel].get("doc_id")
        if doc_id:
            api("POST", f"/api/document/{doc_id}/archive", {})
            archived += 1
        del state[rel]

    STATE_FILE.write_text(json.dumps(state, indent=1, ensure_ascii=False))
    print(json.dumps({
        "success": True, "created": created, "updated": updated,
        "unchanged": unchanged, "archived": archived, "failed": failed,
        "total_mirrored": len(state),
    }, ensure_ascii=False))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
