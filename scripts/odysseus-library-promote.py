#!/usr/bin/env python3
"""odysseus-library-promote.py — La vuelta Library → hub, como acto humano deliberado.

Complemento del espejo (odysseus-library-mirror.py): cuando el operador edita
una copia espejada en la Library de Odysseus, el espejo la protege (no la pisa)
y avisa por Telegram. Este script ejecuta la decisión:

  list                    — documentos editados en Library + diff resumido vs hub
  diff <rel>              — diff completo de un documento editado
  promote <rel>           — escribe la versión de Library al archivo del hub
                            (atómico) y re-sincroniza el estado del espejo
  promote-new <doc_id> <carpeta> — promueve un doc NUEVO de Library (no espejado)
                            al hub como archivo aditivo (fecha+slug) en
                            projects|research|daily|shared
  discard <rel>           — descarta la edición local: re-impone la versión del hub

La fuente de verdad sigue siendo el hub; el humano es quien consolida.
Pensado para invocarse a mano o vía Hermes ("promové el documento X").
"""

import datetime
import difflib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
KNOWLEDGE = HOME / "ai-lab/knowledge"
STATE_FILE = KNOWLEDGE / ".state/odysseus-library-mirror.json"
CONTAINER = "odysseus"
PROMOTE_DIRS = {"projects", "research", "daily", "shared"}


def load_state():
    return json.loads(STATE_FILE.read_text())


def save_state(state):
    STATE_FILE.write_text(json.dumps(state, indent=1, ensure_ascii=False))


def get_doc(doc_id):
    r = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "python", "-c",
         "import sqlite3, json, sys\n"
         "c = sqlite3.connect('file:/app/data/app.db?mode=ro', uri=True)\n"
         "row = c.execute('SELECT title, current_content FROM documents WHERE id=?', (sys.argv[1],)).fetchone()\n"
         "print(json.dumps({'title': row[0], 'content': row[1]} if row else {}))",
         doc_id],
        capture_output=True, timeout=30)
    return json.loads(r.stdout.decode() or "{}")


def strip_banner(content):
    lines = content.split("\n")
    if lines and lines[0].startswith("> 🔄"):
        lines = lines[1:]
        while lines and not lines[0].strip():
            lines.pop(0)
    return "\n".join(lines)


def sha(text):
    import hashlib
    return hashlib.sha256(text.encode()).hexdigest()


def atomic_write(dest: Path, content: str):
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".harvest-", dir=dest.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, dest)


def edited_entries(state):
    return {rel: e for rel, e in state.items() if e.get("edited")}


def diff_summary(rel, entry):
    doc = get_doc(entry["doc_id"])
    lib = strip_banner(doc.get("content") or "")
    hub = (KNOWLEDGE / rel).read_text(encoding="utf-8") if (KNOWLEDGE / rel).exists() else ""
    d = list(difflib.unified_diff(hub.splitlines(), lib.splitlines(), lineterm=""))
    plus = sum(1 for l in d if l.startswith("+") and not l.startswith("+++"))
    minus = sum(1 for l in d if l.startswith("-") and not l.startswith("---"))
    return doc, d, plus, minus


def cmd_list(state):
    ed = edited_entries(state)
    if not ed:
        print("Sin ediciones locales pendientes en la Library.")
        return
    print(f"{len(ed)} documento(s) editados en la Library (protegidos por el espejo):\n")
    for rel, e in ed.items():
        _, _, plus, minus = diff_summary(rel, e)
        print(f"• {rel}  (+{plus}/-{minus} líneas vs hub)")
    print("\npromote <rel> para llevar al hub · discard <rel> para descartar · diff <rel> para el detalle")


def cmd_diff(state, rel):
    e = state.get(rel) or sys.exit(f"'{rel}' no está en el espejo")
    _, d, plus, minus = diff_summary(rel, e)
    print(f"--- hub | +++ library  (+{plus}/-{minus})\n")
    print("\n".join(d[:200]) or "(sin diferencias)")


def cmd_promote(state, rel):
    e = state.get(rel) or sys.exit(f"'{rel}' no está en el espejo")
    doc = get_doc(e["doc_id"])
    content = strip_banner(doc.get("content") or "")
    if not content.strip():
        sys.exit("La copia de Library está vacía — no se promueve.")
    dest = KNOWLEDGE / rel
    atomic_write(dest, content)
    # re-sincronizar estado: lo que hay en Library ES ahora el hub (sin eco)
    e["mtime"] = dest.stat().st_mtime
    e["sha"] = sha(doc.get("content") or "")
    e.pop("edited", None)
    e.pop("notified", None)
    save_state(state)
    print(f"✓ Promovido: Library → knowledge/{rel} (Syncthing lo distribuye; el RAG lo re-indexa en ≤6h)")


def cmd_discard(state, rel):
    e = state.get(rel) or sys.exit(f"'{rel}' no está en el espejo")
    e.pop("edited", None)
    e.pop("notified", None)
    e["mtime"] = 0  # fuerza re-sync desde el hub en la próxima corrida
    save_state(state)
    r = subprocess.run([sys.executable, str(HOME / "ai-lab/scripts/odysseus-library-mirror.py")],
                       capture_output=True, text=True, timeout=600)
    print(f"✓ Descartado: la versión del hub fue re-impuesta en la Library "
          f"(tu edición queda en el historial de versiones del documento).")


def cmd_promote_new(state, doc_id, folder):
    if folder not in PROMOTE_DIRS:
        sys.exit(f"Carpeta inválida '{folder}' — usar: {', '.join(sorted(PROMOTE_DIRS))}")
    doc = get_doc(doc_id)
    if not doc:
        sys.exit(f"Documento '{doc_id}' no existe en la Library")
    content = strip_banner(doc.get("content") or "")
    title = doc.get("title") or "documento"
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:60] or "documento"
    fname = f"{datetime.date.today().isoformat()}_{slug}.md"
    dest = KNOWLEDGE / folder / fname
    if dest.exists():
        fname = f"{datetime.date.today().isoformat()}_{slug}_{doc_id[:6]}.md"
        dest = KNOWLEDGE / folder / fname
    atomic_write(dest, content)
    rel = f"{folder}/{fname}"
    state[rel] = {"doc_id": doc_id, "mtime": dest.stat().st_mtime,
                  "sha": sha(doc.get("content") or "")}
    save_state(state)
    print(f"✓ Promovido documento nuevo: '{title}' → knowledge/{rel} "
          f"(ahora es un doc espejado — futuras ediciones siguen el flujo protegido)")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    state = load_state()
    cmd = sys.argv[1]
    if cmd == "list":
        cmd_list(state)
    elif cmd == "diff" and len(sys.argv) == 3:
        cmd_diff(state, sys.argv[2])
    elif cmd == "promote" and len(sys.argv) == 3:
        cmd_promote(state, sys.argv[2])
    elif cmd == "discard" and len(sys.argv) == 3:
        cmd_discard(state, sys.argv[2])
    elif cmd == "promote-new" and len(sys.argv) == 4:
        cmd_promote_new(state, sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
