#!/usr/bin/env python3
"""Módulo común del pipeline de knowledge management del AI Lab.

Provee a todos los extractores (claude_code_extract.py, opencode_extract.py):
  - Estado incremental (.processed.yaml): qué sesiones ya se procesaron
  - Frontmatter YAML estándar para los archivos destilados
  - Actualización del index.md por empresa

Convención de estado (knowledge-management-execution-plan.md, sección Fase 3):
  version: 1
  last_run: ISO-8601
  sources:
    <source>:
      processed_count: N
      files:
        - id: <session_id>
          hash: <sha8>
          processed_at: ISO-8601
          output: <nombre de archivo generado>
"""

import hashlib
from datetime import datetime, timezone
from pathlib import Path

import yaml

STATE_VERSION = 1
STATE_FILENAME = ".processed.yaml"


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha8(data) -> str:
    if isinstance(data, str):
        data = data.encode("utf-8", errors="replace")
    return hashlib.sha256(data).hexdigest()[:8]


def load_state(state_dir: Path) -> dict:
    path = Path(state_dir) / STATE_FILENAME
    if path.exists():
        with open(path, "r", encoding="utf-8") as f:
            state = yaml.safe_load(f) or {}
        state.setdefault("version", STATE_VERSION)
        state.setdefault("sources", {})
        return state
    return {"version": STATE_VERSION, "last_run": None, "sources": {}}


def save_state(state_dir: Path, state: dict) -> None:
    state["last_run"] = now_iso()
    path = Path(state_dir) / STATE_FILENAME
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(state, f, allow_unicode=True, sort_keys=False)


def is_processed(state: dict, source: str, item_id: str, content_hash: str = None) -> bool:
    """True si el item ya se procesó (y, si se pasa hash, no cambió)."""
    files = state["sources"].get(source, {}).get("files", [])
    for entry in files:
        if entry.get("id") == item_id:
            if content_hash is None:
                return True
            return entry.get("hash") == content_hash
    return False


def mark_processed(state: dict, source: str, item_id: str, content_hash: str, output: str) -> None:
    src = state["sources"].setdefault(source, {"processed_count": 0, "files": []})
    # Reemplazar entrada previa del mismo id (sesión modificada y reprocesada)
    src["files"] = [e for e in src["files"] if e.get("id") != item_id]
    src["files"].append({
        "id": item_id,
        "hash": content_hash,
        "processed_at": now_iso(),
        "output": output,
    })
    src["processed_count"] = len(src["files"])


def frontmatter(source: str, company_id: str, date: str, model: str = "",
                topics: list = None, session_id: str = "") -> str:
    meta = {
        "source": source,
        "company_id": company_id,
        "date": date,
        "model": model or "desconocido",
        "session_id": session_id,
        "topics": topics or [],
    }
    return "---\n" + yaml.safe_dump(meta, allow_unicode=True, sort_keys=False) + "---\n\n"


INDEX_HEADER = """# Índice de sesiones — Empresa {company_id}

Punto de entrada para recuperación cruzada entre agentes: consultar esta tabla
antes de leer archivos completos. Cada fila apunta a un archivo en este directorio.

| Fecha | Fuente | Sesión | Temas clave | Archivo |
|-------|--------|--------|-------------|---------|
"""


def append_index_row(sessions_dir: Path, company_id: str, date: str, source: str,
                     session_id: str, topics: str, output_file: str) -> None:
    index_path = Path(sessions_dir) / "index.md"
    if not index_path.exists():
        index_path.parent.mkdir(parents=True, exist_ok=True)
        index_path.write_text(INDEX_HEADER.format(company_id=company_id), encoding="utf-8")
    topics = (topics or "").replace("|", "/").replace("\n", " ")[:120]
    row = f"| {date} | {source} | {session_id[:24]} | {topics} | {output_file} |\n"
    content = index_path.read_text(encoding="utf-8")
    if session_id[:24] in content:
        return  # ya indexada
    with open(index_path, "a", encoding="utf-8") as f:
        f.write(row)
