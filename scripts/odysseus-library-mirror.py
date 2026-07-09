#!/usr/bin/env python3
"""odysseus-library-mirror.py — Espeja el knowledge curado del hub en la Library de Odysseus.

Resuelve el gap de UX: la Library es el entorno natural de navegación del
operador, pero por diseño de la app solo muestra su SQLite interno — los
mounts de knowledge/ no aparecen ahí. Este espejo usa la PROPIA API de la
Library (POST/PUT /api/document, con versionamiento nativo) — cero cambios
al código de Odysseus.

Dirección hub → Library, con PROTECCIÓN DE EDICIONES LOCALES: si el operador
editó la copia en la Library, el espejo NUNCA la pisa — la marca como editada,
avisa por Telegram (con diff vs el hub) y espera la decisión humana:
`odysseus-library-promote.py` la promueve al hub o la descarta. La fuente de
verdad sigue siendo el hub; la vuelta existe como acto deliberado del humano.

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
          "Si editás este documento acá, el espejo lo protege (no lo pisa) y "
          "te llega un aviso para promover tus cambios al hub o descartarlos. "
          "También podés editar desde la Mac (Obsidian) o vía Hermes/agente.\n\n")

def lib_hashes(doc_ids):
    """sha256 del contenido actual de cada doc en la Library — UNA consulta a la
    DB de la app (read-only) en vez de 100+ llamadas HTTP."""
    if not doc_ids:
        return {}
    r = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "python", "-c",
         "import sqlite3, json, sys, hashlib\n"
         "ids = json.load(sys.stdin)\n"
         "c = sqlite3.connect('file:/app/data/app.db?mode=ro', uri=True)\n"
         "out = {}\n"
         "q = 'SELECT id, current_content FROM documents WHERE id IN (%s)' % ','.join('?'*len(ids))\n"
         "for i, content in c.execute(q, ids):\n"
         "    out[i] = hashlib.sha256((content or '').encode()).hexdigest()\n"
         "print(json.dumps(out))"],
        input=json.dumps(doc_ids).encode(), capture_output=True, timeout=60)
    try:
        return json.loads(r.stdout.decode() or "{}")
    except Exception:
        return {}


def sha(text):
    import hashlib
    return hashlib.sha256(text.encode()).hexdigest()


def notify(msg):
    subprocess.run([str(HOME / "ai-lab/scripts/telegram-notify.sh"), msg, "INFO"],
                   capture_output=True, timeout=30)


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


DATE_RE = __import__("re").compile(r"(20\d{2}-\d{2}-\d{2})")

def real_date(rel, f):
    """Fecha histórica del documento: la del nombre de archivo si la tiene,
    si no el mtime — para que la Library conserve la trazabilidad temporal."""
    m = DATE_RE.search(Path(rel).name)
    if m:
        return f"{m.group(1)} 12:00:00"
    import datetime
    return datetime.datetime.utcfromtimestamp(f.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")


def apply_dates(fixes):
    """Alinea created_at/updated_at en el SQLite de la app (la API no permite
    fijarlos). Un solo docker exec para todo el lote."""
    if not fixes:
        return
    payload = json.dumps(fixes)
    subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "python", "-c",
         "import sqlite3, json, sys\n"
         "fixes = json.load(sys.stdin)\n"
         "c = sqlite3.connect('/app/data/app.db')\n"
         "for doc_id, ts in fixes:\n"
         "    c.execute('UPDATE documents SET created_at=?, updated_at=? WHERE id=?', (ts, ts, doc_id))\n"
         "c.commit()"],
        input=payload.encode(), capture_output=True, timeout=60)


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
    protected = []
    seen = set()
    date_fixes = []

    # Detección de ediciones locales: comparar el contenido actual de la Library
    # contra el hash de lo último que ESTE espejo escribió.
    hashes = lib_hashes([e["doc_id"] for e in state.values() if e.get("doc_id")])
    for rel, entry in state.items():
        cur = hashes.get(entry.get("doc_id", ""))
        if cur and entry.get("sha") and cur != entry["sha"]:
            entry["edited"] = True

    for rel, f, label in iter_files():
        seen.add(rel)
        try:
            mtime = f.stat().st_mtime
        except OSError:
            continue
        entry = state.get(rel)

        # PROTECCIÓN: copia editada por el operador — no pisar jamás.
        if entry and entry.get("edited"):
            if not entry.get("notified"):
                hub_changed = entry.get("mtime") != mtime
                protected.append((rel, entry["doc_id"], hub_changed))
                entry["notified"] = True
            continue

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
                state[rel] = {"doc_id": entry["doc_id"], "mtime": mtime, "sha": sha(content)}
                date_fixes.append((entry["doc_id"], real_date(rel, f)))
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
                state[rel] = {"doc_id": doc_id, "mtime": mtime, "sha": sha(content)}
                date_fixes.append((doc_id, real_date(rel, f)))
                created += 1
            else:
                failed += 1

    # Aviso por Telegram de las ediciones nuevas (una vez por documento)
    if protected:
        lines = ["📚 Library: documento(s) editados por el operador — el espejo NO los pisó:"]
        for rel, doc_id, hub_changed in protected:
            extra = " ⚠️ el archivo del hub TAMBIÉN cambió" if hub_changed else ""
            lines.append(f"• {rel}{extra}")
        lines.append("Decidir con: odysseus-library-promote.py list | promote <rel> | discard <rel>")
        notify("\n".join(lines))

    # Archivos que desaparecieron del hub → soft-archive en Library
    for rel in [r for r in list(state) if r not in seen]:
        doc_id = state[rel].get("doc_id")
        if doc_id:
            api("POST", f"/api/document/{doc_id}/archive", {})
            archived += 1
        del state[rel]

    apply_dates(date_fixes)
    STATE_FILE.write_text(json.dumps(state, indent=1, ensure_ascii=False))
    print(json.dumps({
        "success": True, "created": created, "updated": updated,
        "unchanged": unchanged, "archived": archived, "failed": failed,
        "protected_edits": [r for r, e in state.items() if e.get("edited")],
        "total_mirrored": len(state),
    }, ensure_ascii=False))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
