#!/usr/bin/env python3
"""paperclip-harvest-documents.py — Cosecha los documents de la DB de Paperclip al hub.

Cierra el gap detectado en el plan de integración (§5.3): los agentes de
Paperclip guardan algunos entregables en la tabla `documents` (PostgreSQL),
que a diferencia de los workspaces NO tenía pipeline de cosecha. Los
"Continuation Summary" y "routine description" son memoria operativa y se
excluyen (como los issues); el resto es conocimiento del lab y va al hub:

    knowledge/<empresa>/outputs/db-documents/<fecha>_<slug>.md

Incremental por updated_at (re-cosecha si el doc cambió). Escritura atómica
(temp + os.replace) por la regla §5.4 de Syncthing.
"""

import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

HOME = Path.home()
KNOWLEDGE = HOME / "ai-lab/knowledge"
STATE_FILE = KNOWLEDGE / ".state/paperclip-doc-harvest.json"

# Memoria operativa — nunca cosechar
EXCLUDED_TITLES = {"Continuation Summary", "routine description", "Plan"}

SQL = """
SELECT COALESCE(json_agg(json_build_object(
  'id', d.id, 'company', c.name, 'title', d.title,
  'body', d.latest_body, 'updated', d.updated_at::text
)), '[]'::json)
FROM documents d JOIN companies c ON d.company_id = c.id
WHERE d.title NOT IN ('Continuation Summary', 'routine description', 'Plan')
  AND length(COALESCE(d.latest_body, '')) > 200;
"""


def slugify(text, max_len=60):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:max_len].rstrip("-") or "documento"


def company_dir(name):
    slug = slugify(name, 30)
    d = KNOWLEDGE / slug / "outputs" / "db-documents"
    return d


def main():
    r = subprocess.run(
        ["docker", "exec", "paperclip-db-1", "psql", "-U", "paperclip", "-d", "paperclip", "-tA", "-c", SQL],
        capture_output=True, text=True, timeout=60,
    )
    if r.returncode != 0:
        print(json.dumps({"success": False, "error": r.stderr[:200]}))
        return 1
    docs = json.loads(r.stdout.strip() or "[]")

    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        state = json.loads(STATE_FILE.read_text())
    except Exception:
        state = {"harvested": {}}

    harvested, unchanged = [], 0
    for d in docs:
        did = str(d["id"])
        if state["harvested"].get(did, {}).get("updated") == d["updated"]:
            unchanged += 1
            continue

        dest_dir = company_dir(d["company"])
        dest_dir.mkdir(parents=True, exist_ok=True)
        date = (d["updated"] or "")[:10] or datetime.date.today().isoformat()
        fname = f"{date}_{slugify(d['title'], 52)}_{did[-6:]}.md"  # sufijo id: evita colisión de slugs
        dest = dest_dir / fname

        content = "\n".join([
            "---",
            f'titulo: "{d["title"].replace(chr(34), chr(39))}"',
            f"empresa: {d['company']}",
            f"actualizado: {d['updated']}",
            f"origen: paperclip db documents (id {did})",
            "---",
            "",
            (d["body"] or "").strip(),
            "",
        ])

        fd, tmp = tempfile.mkstemp(prefix=".harvest-", suffix=".tmp", dir=dest_dir)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(content)
            os.replace(tmp, dest)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

        state["harvested"][did] = {"file": fname, "updated": d["updated"]}
        harvested.append(f"{d['company']}: {fname}")

    STATE_FILE.write_text(json.dumps(state, indent=1, ensure_ascii=False))
    print(json.dumps({"success": True, "harvested": harvested, "unchanged": unchanged},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
