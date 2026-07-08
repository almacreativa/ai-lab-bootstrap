#!/usr/bin/env python3
"""index-knowledge.py — Indexa el knowledge base del lab en el ChromaDB de Odysseus.

Fase 2 del plan de integración de conocimientos (§6 del plan). Se ejecuta DENTRO
del contenedor (docker exec odysseus python /app/data/scripts/index-knowledge.py)
para reutilizar las clases VectorRAG de Odysseus — mismas colecciones y lanes de
embedding que usa el agente al buscar. NO escribe a ChromaDB crudo.

El archivo vive en el host (~/ai-lab/data/core/odysseus/data/scripts/) y es
visible en el contenedor vía el mount de /app/data — editable sin rebuild.

Modo por defecto: INCREMENTAL — solo procesa archivos nuevos/modificados (mtime
vs estado) y remueve del índice los eliminados. Con --full hace rebuild completo
(remove + re-embed de todo; la primera corrida tomó ~22 min para 1195 archivos).

Exclusiones (§5.4 del plan): .state/, .stfolder/, .stversions/ (versiones viejas
de Syncthing — indexarlas envenenaría el RAG), companies/ (UUIDs), y el patrón
*.sync-conflict-*. Solo prosa: .md y .txt.

Owner "admin": el RAG del chat filtra por owner de la sesión — sin esto, el
operador no vería los resultados.
"""

import fnmatch
import json
import os
import sys
import time

sys.path.insert(0, "/app")

from src.rag_vector import VectorRAG  # noqa: E402

ROOT = "/app/data/knowledge"
OWNER = "admin"
EXCLUDED_DIRS = {".state", ".stfolder", ".stversions", "companies", "__pycache__"}
CONFLICT_PATTERN = "*.sync-conflict-*"
EXTENSIONS = {".md", ".txt"}
STATE_FILE = "/app/data/scripts/.index-state.json"


def walk_files():
    for root, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for fname in sorted(files):
            if fnmatch.fnmatch(fname, CONFLICT_PATTERN):
                continue
            if os.path.splitext(fname)[1].lower() not in EXTENSIONS:
                continue
            yield os.path.join(root, fname)


def index_file(rag, fpath):
    """(re)indexa un archivo: remueve sus chunks previos y agrega los actuales."""
    try:
        with open(fpath, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception:
        return 0, 1
    rag.remove_directory(fpath)  # boundary match: source == fpath
    if not content.strip():
        return 0, 0
    meta = {
        "source": fpath,
        "filename": os.path.basename(fpath),
        "directory": os.path.dirname(fpath),
        "type": os.path.splitext(fpath)[1].lower(),
        "owner": OWNER,
    }
    chunks = failed = 0
    for i, chunk in enumerate(rag._split_into_chunks(content)):
        if rag.add_document(chunk, {**meta, "chunk_id": i}):
            chunks += 1
        else:
            failed += 1
    return chunks, failed


def main():
    full = "--full" in sys.argv
    t0 = time.time()
    rag = VectorRAG()
    if not rag.healthy:
        print(json.dumps({"success": False, "error": "ChromaDB no disponible"}))
        return 1

    try:
        state = json.loads(open(STATE_FILE).read())
    except Exception:
        state = {}

    if full:
        rag.remove_directory(ROOT)
        state = {}

    current = {}
    changed_files = removed_files = 0
    chunks_total = failed_total = 0

    for fpath in walk_files():
        try:
            mtime = os.path.getmtime(fpath)
        except OSError:
            continue
        current[fpath] = mtime
        if not full and state.get(fpath) == mtime:
            continue  # sin cambios — no se lee ni se embebe
        c, f = index_file(rag, fpath)
        chunks_total += c
        failed_total += f
        changed_files += 1

    # Archivos que desaparecieron desde la última corrida
    for stale in set(state) - set(current):
        rag.remove_directory(stale)
        removed_files += 1

    with open(STATE_FILE, "w") as f:
        json.dump(current, f)

    print(json.dumps({
        "success": True,
        "mode": "full" if full else "incremental",
        "root": ROOT,
        "owner": OWNER,
        "files_total": len(current),
        "files_indexed": changed_files,
        "files_removed": removed_files,
        "chunks_added": chunks_total,
        "failed": failed_total,
        "seconds": round(time.time() - t0, 1),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
