#!/usr/bin/env python3
"""odysseus-harvest-research.py — Cosecha los Deep Research de Odysseus al hub.

Pipeline del plan de integración de conocimientos (§6C): convierte
~/ai-lab/data/core/odysseus/data/deep_research/rp-*.json (memoria operativa de
la app) en markdown dentro de ~/ai-lab/knowledge/research/odysseus/ (hub),
para que todos los agentes — y el indexador RAG — los vean.

Reglas de la capa Syncthing (§5.4):
- Escritura ATÓMICA: se escribe a temp fuera del folder sincronizado y se hace
  os.replace() al destino — Syncthing nunca propaga archivos a medias.
- Aditiva: cada research es un archivo nuevo con fecha+slug; nunca se edita.

Incremental: los ids ya cosechados se registran en knowledge/.state/ (excluido
del sync y del RAG). Un research se cosecha solo cuando status == done.
"""

import datetime
import json
import os
import re
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
SOURCE_DIR = HOME / "ai-lab/data/core/odysseus/data/deep_research"
DEST_DIR = HOME / "ai-lab/knowledge/research/odysseus"
STATE_FILE = HOME / "ai-lab/knowledge/.state/odysseus-harvest.json"


def slugify(text, max_len=60):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:max_len].rstrip("-") or "research"


def main():
    if not SOURCE_DIR.is_dir():
        print(json.dumps({"success": False, "error": f"no existe {SOURCE_DIR}"}))
        return 1

    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    DEST_DIR.mkdir(parents=True, exist_ok=True)
    try:
        state = json.loads(STATE_FILE.read_text())
    except Exception:
        state = {"harvested": {}}

    harvested_now = []
    skipped = 0

    for src in sorted(SOURCE_DIR.glob("rp-*.json")):
        rid = src.stem
        if rid in state["harvested"]:
            skipped += 1
            continue
        try:
            d = json.loads(src.read_text())
        except Exception:
            continue
        if d.get("status") != "done":
            continue

        query = (d.get("query") or "").strip()
        report = d.get("raw_report") or d.get("result") or ""
        if not report.strip():
            continue

        completed = d.get("completed_at")
        try:
            date = datetime.datetime.fromtimestamp(float(completed)).strftime("%Y-%m-%d")
        except Exception:
            date = datetime.date.today().isoformat()

        fname = f"{date}_{slugify(query)}.md"
        dest = DEST_DIR / fname

        sources = d.get("sources") or []
        src_lines = []
        for s in sources[:30]:
            if isinstance(s, dict):
                title = s.get("title") or s.get("url") or "?"
                url = s.get("url") or ""
                src_lines.append(f"- [{title}]({url})" if url else f"- {title}")
            else:
                src_lines.append(f"- {s}")

        content = "\n".join([
            "---",
            f'query: "{query.replace(chr(34), chr(39))}"',
            f"fecha: {date}",
            f"origen: odysseus deep research ({rid})",
            f"owner: {d.get('owner', '?')}",
            "---",
            "",
            report.strip(),
            "",
            "## Fuentes",
            "",
        ] + (src_lines or ["- (sin fuentes registradas)"]) + [""])

        # Escritura atómica: temp en /tmp (fuera del folder Syncthing) + replace.
        # os.replace requiere mismo filesystem → temp junto al destino con
        # prefijo "." (Syncthing ignora dotfiles en escaneo por defecto no,
        # pero el rename es atómico igual — la ventana es el archivo oculto).
        fd, tmp_path = tempfile.mkstemp(prefix=".harvest-", suffix=".tmp", dir=DEST_DIR)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(content)
            os.replace(tmp_path, dest)
        except Exception:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise

        state["harvested"][rid] = {"file": fname, "harvested_at": datetime.datetime.now().isoformat(timespec="seconds")}
        harvested_now.append(fname)

    STATE_FILE.write_text(json.dumps(state, indent=1, ensure_ascii=False))
    print(json.dumps({
        "success": True,
        "harvested": harvested_now,
        "already_done": skipped,
        "dest": str(DEST_DIR),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
