#!/usr/bin/env python3
"""Extractor de sesiones de Claude Code para el pipeline de knowledge management.

A diferencia de process_sessions.py (herramienta de reporting completa, con
integración Codex/Qwen), este extractor produce UN markdown compacto por sesión,
con el frontmatter YAML estándar del pipeline, listo para la destilación con
opencode-zen. Incremental: solo procesa sesiones nuevas o modificadas.

Uso:
  python3 claude_code_extract.py --company-id <company-id> \\
      --output-dir ~/alma/knowledge/companies/<company-id>/sessions/ \\
      [--projects-dir ~/.claude/projects] [--since-days 30] [--min-user-messages 2]

El estado vive en <output-dir>/.processed.yaml bajo la fuente "claude_code".
"""

import argparse
import json
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

from km_common import (load_state, save_state, is_processed, mark_processed,
                       frontmatter, append_index_row, sha8)

SOURCE = "claude_code"
MAX_MSG_PREVIEW = 600
MAX_USER_MSGS = 30


def extract_session(jsonl_path: Path) -> dict:
    """Extrae lo esencial de una sesión JSONL de Claude Code."""
    info = {
        "session_id": jsonl_path.stem,
        "cwd": "",
        "start": None,
        "end": None,
        "models": set(),
        "user_msgs": [],
        "last_assistant": "",
        "tools": {},
        "files_touched": set(),
    }
    seen_msg_ids = set()
    with open(jsonl_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = data.get("timestamp", "")
            if ts:
                info["start"] = min(info["start"] or ts, ts)
                info["end"] = max(info["end"] or ts, ts)
            if not info["cwd"] and data.get("cwd"):
                info["cwd"] = data["cwd"]

            mtype = data.get("type", "")
            msg = data.get("message", {}) or {}
            content = msg.get("content", "")

            if mtype == "user":
                texts = []
                if isinstance(content, str):
                    texts = [content]
                elif isinstance(content, list):
                    texts = [c.get("text", "") for c in content
                             if isinstance(c, dict) and c.get("type") == "text"]
                for t in texts:
                    t = t.strip()
                    if t and not t.startswith(("[Request interrupted", "<command-name>",
                                               "<local-command", "<system-reminder")):
                        info["user_msgs"].append(t[:MAX_MSG_PREVIEW])

            elif mtype == "assistant":
                mid = msg.get("id", "")
                model = msg.get("model", "")
                if model and mid not in seen_msg_ids:
                    seen_msg_ids.add(mid)
                    info["models"].add(model)
                if isinstance(content, list):
                    for item in content:
                        if not isinstance(item, dict):
                            continue
                        if item.get("type") == "text" and item.get("text", "").strip():
                            info["last_assistant"] = item["text"].strip()
                        elif item.get("type") == "tool_use":
                            name = item.get("name", "?")
                            info["tools"][name] = info["tools"].get(name, 0) + 1
                            ti = item.get("input", {}) or {}
                            fp = ti.get("file_path") or ti.get("filePath") or ti.get("path")
                            if fp:
                                info["files_touched"].add(str(fp))
    return info


def render_markdown(info: dict, company_id: str) -> str:
    date = (info["start"] or "")[:10] or "sin-fecha"
    topics = []
    if info["user_msgs"]:
        topics.append(info["user_msgs"][0][:80])
    fm = frontmatter(SOURCE, company_id, date,
                     model=", ".join(sorted(info["models"])),
                     topics=topics, session_id=info["session_id"])
    lines = [fm,
             f"# Sesión Claude Code — {date}",
             "",
             f"- **Directorio de trabajo:** `{info['cwd']}`",
             f"- **Rango:** {info['start']} → {info['end']}",
             f"- **Herramientas usadas:** " + ", ".join(
                 f"{k}×{v}" for k, v in sorted(info["tools"].items(), key=lambda x: -x[1])[:12]),
             ""]
    if info["files_touched"]:
        lines.append("## Archivos tocados")
        lines.extend(f"- `{p}`" for p in sorted(info["files_touched"])[:30])
        lines.append("")
    lines.append("## Pedidos del usuario (en orden)")
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
    ap.add_argument("--projects-dir", default=str(Path.home() / ".claude" / "projects"))
    ap.add_argument("--since-days", type=int, default=30)
    ap.add_argument("--min-user-messages", type=int, default=2,
                    help="Sesiones con menos mensajes de usuario se ignoran (ruido)")
    args = ap.parse_args()

    out_dir = Path(args.output_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    projects = Path(args.projects_dir).expanduser()
    if not projects.exists():
        print(f"ERROR: no existe {projects}", file=sys.stderr)
        sys.exit(1)

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.since_days)
    state = load_state(out_dir)
    new, skipped = 0, 0

    for jsonl in sorted(projects.glob("*/*.jsonl")):
        mtime = datetime.fromtimestamp(jsonl.stat().st_mtime, tz=timezone.utc)
        if mtime < cutoff:
            continue
        # Hash barato: tamaño + mtime (suficiente para detectar cambios)
        content_hash = sha8(f"{jsonl.stat().st_size}:{int(jsonl.stat().st_mtime)}")
        if is_processed(state, SOURCE, jsonl.stem, content_hash):
            skipped += 1
            continue

        info = extract_session(jsonl)
        if len(info["user_msgs"]) < args.min_user_messages:
            mark_processed(state, SOURCE, jsonl.stem, content_hash, "(ignorada: ruido)")
            continue

        date = (info["start"] or "")[:10] or "sin-fecha"
        out_name = f"claude-code-{date}_{jsonl.stem[:8]}.md"
        (out_dir / out_name).write_text(render_markdown(info, args.company_id),
                                        encoding="utf-8")
        append_index_row(out_dir, args.company_id, date, SOURCE, jsonl.stem,
                         info["user_msgs"][0] if info["user_msgs"] else "",
                         out_name)
        mark_processed(state, SOURCE, jsonl.stem, content_hash, out_name)
        new += 1
        print(f"  + {out_name}")

    save_state(out_dir, state)
    print(f"claude_code_extract: {new} sesiones nuevas, {skipped} ya procesadas")


if __name__ == "__main__":
    main()
