#!/usr/bin/env python3
"""Extractor de sesiones de OpenCode (SQLite) para el pipeline de knowledge management.

Lee ~/.local/share/opencode/opencode.db (tablas session, message, part) y produce
un markdown compacto por sesión con el frontmatter YAML estándar del pipeline,
mismo formato que claude_code_extract.py. Incremental vía .processed.yaml.

Uso:
  python3 opencode_extract.py --company-id <company-id> \\
      --output-dir ~/alma/knowledge/companies/<company-id>/sessions/ \\
      [--db ~/.local/share/opencode/opencode.db] [--since-days 30]

El estado vive en <output-dir>/.processed.yaml bajo la fuente "opencode".
"""

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

from km_common import (load_state, save_state, is_processed, mark_processed,
                       frontmatter, append_index_row, sha8)

SOURCE = "opencode"
MAX_MSG_PREVIEW = 600
MAX_USER_MSGS = 30


def epoch_to_iso(ms) -> str:
    if not ms:
        return ""
    ts = ms / 1000 if ms > 1e12 else ms  # la DB guarda milisegundos
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def extract_session(conn, session_row) -> dict:
    sid = session_row["id"]
    model = ""
    if session_row["model"]:
        try:
            m = json.loads(session_row["model"])
            model = f"{m.get('providerID', '?')}/{m.get('id', m.get('modelID', '?'))}"
        except (json.JSONDecodeError, AttributeError):
            model = str(session_row["model"])[:60]

    info = {
        "session_id": sid,
        "title": session_row["title"] or "",
        "cwd": session_row["directory"] or "",
        "start": epoch_to_iso(session_row["time_created"]),
        "end": epoch_to_iso(session_row["time_updated"]),
        "model": model,
        "user_msgs": [],
        "last_assistant": "",
        "tools": {},
    }

    messages = conn.execute(
        "SELECT id, data, time_created FROM message WHERE session_id = ? ORDER BY time_created",
        (sid,)).fetchall()

    for msg in messages:
        try:
            mdata = json.loads(msg["data"])
        except json.JSONDecodeError:
            continue
        role = mdata.get("role", "")
        parts = conn.execute(
            "SELECT data FROM part WHERE message_id = ? ORDER BY time_created",
            (msg["id"],)).fetchall()
        texts = []
        for p in parts:
            try:
                pdata = json.loads(p["data"])
            except json.JSONDecodeError:
                continue
            ptype = pdata.get("type", "")
            if ptype == "text" and pdata.get("text", "").strip():
                texts.append(pdata["text"].strip())
            elif ptype == "tool":
                tname = pdata.get("tool") or pdata.get("name") or "?"
                info["tools"][tname] = info["tools"].get(tname, 0) + 1
        if role == "user" and texts:
            for t in texts:
                info["user_msgs"].append(t[:MAX_MSG_PREVIEW])
        elif role == "assistant" and texts:
            info["last_assistant"] = texts[-1]

    return info


def render_markdown(info: dict, company_id: str) -> str:
    date = (info["start"] or "")[:10] or "sin-fecha"
    fm = frontmatter(SOURCE, company_id, date, model=info["model"],
                     topics=[info["title"][:80]] if info["title"] else [],
                     session_id=info["session_id"])
    lines = [fm,
             f"# Sesión OpenCode — {info['title'] or date}",
             "",
             f"- **Directorio de trabajo:** `{info['cwd']}`",
             f"- **Rango:** {info['start']} → {info['end']}",
             f"- **Modelo:** {info['model']}",
             f"- **Herramientas usadas:** " + ", ".join(
                 f"{k}×{v}" for k, v in sorted(info["tools"].items(), key=lambda x: -x[1])[:12]),
             "",
             "## Pedidos del usuario (en orden)"]
    for i, m in enumerate(info["user_msgs"][:MAX_USER_MSGS], 1):
        lines.append(f"{i}. {m}")
    lines.append("")
    lines.append("## Cierre de la sesión (última respuesta del agente)")
    lines.append(info["last_assistant"][:2000] or "_(sin respuesta final de texto)_")
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--company-id", required=True)
    ap.add_argument("--output-dir", required=True)
    ap.add_argument("--db", default=str(Path.home() / ".local/share/opencode/opencode.db"))
    ap.add_argument("--since-days", type=int, default=30)
    ap.add_argument("--min-user-messages", type=int, default=1)
    args = ap.parse_args()

    db_path = Path(args.db).expanduser()
    if not db_path.exists():
        print(f"ERROR: no existe {db_path}", file=sys.stderr)
        sys.exit(1)

    out_dir = Path(args.output_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)

    cutoff_ms = int((datetime.now(timezone.utc) - timedelta(days=args.since_days))
                    .timestamp() * 1000)

    # Modo solo lectura: nunca tocar la DB de OpenCode
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row

    state = load_state(out_dir)
    new, skipped = 0, 0

    sessions = conn.execute(
        """SELECT * FROM session
           WHERE parent_id IS NULL AND time_updated >= ?
           ORDER BY time_created""", (cutoff_ms,)).fetchall()

    for s in sessions:
        content_hash = sha8(f"{s['time_updated']}")
        if is_processed(state, SOURCE, s["id"], content_hash):
            skipped += 1
            continue
        info = extract_session(conn, s)
        if len(info["user_msgs"]) < args.min_user_messages:
            mark_processed(state, SOURCE, s["id"], content_hash, "(ignorada: ruido)")
            continue
        date = (info["start"] or "")[:10] or "sin-fecha"
        out_name = f"opencode-{date}_{s['id'][-8:]}.md"
        (out_dir / out_name).write_text(render_markdown(info, args.company_id),
                                        encoding="utf-8")
        append_index_row(out_dir, args.company_id, date, SOURCE, s["id"],
                         info["title"] or (info["user_msgs"][0] if info["user_msgs"] else ""),
                         out_name)
        mark_processed(state, SOURCE, s["id"], content_hash, out_name)
        new += 1
        print(f"  + {out_name}")

    conn.close()
    save_state(out_dir, state)
    print(f"opencode_extract: {new} sesiones nuevas, {skipped} ya procesadas")


if __name__ == "__main__":
    main()
