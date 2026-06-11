"""Mem0 REST API — wrapper propio del AI Lab.

Expone la librería mem0ai como servicio REST, con la configuración del lab:
  - LLM de extracción: API OpenAI-compatible — OpenCode Zen/Go u Ollama Cloud (env OPENAI_*)
  - Embeddings: Ollama local (nomic-embed-text, 768 dims) — env OLLAMA_BASE_URL
  - Vector store: Qdrant embebido (file-based, sin servidor) — /data/qdrant

Namespacing multi-empresa: siempre pasar user_id (ej: "company_<id>").
Auth opcional: si MEM0_API_KEY está seteada, exigir header X-API-Key.
"""

import os

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from mem0 import Memory

DATA_DIR = os.environ.get("DATA_DIR", "/data")
EMBED_DIMS = int(os.environ.get("EMBED_DIMS", "768"))

CONFIG = {
    "llm": {
        "provider": "openai",
        "config": {
            "model": os.environ.get("LLM_MODEL", "opencode/deepseek-v4-flash-free"),
            "openai_base_url": os.environ.get("OPENAI_BASE_URL", "https://opencode.ai/zen/v1"),
            "api_key": os.environ["OPENAI_API_KEY"],
            "temperature": 0,
            "max_tokens": 2000,
        },
    },
    "embedder": {
        "provider": "ollama",
        "config": {
            "model": os.environ.get("EMBED_MODEL", "nomic-embed-text"),
            "ollama_base_url": os.environ.get("OLLAMA_BASE_URL", "http://ollama:11434"),
            "embedding_dims": EMBED_DIMS,
        },
    },
    "vector_store": {
        "provider": "qdrant",
        "config": {
            "collection_name": "lab_memories",
            "embedding_model_dims": EMBED_DIMS,
            "path": f"{DATA_DIR}/qdrant",
            "on_disk": True,
        },
    },
    "history_db_path": f"{DATA_DIR}/history.db",
}

app = FastAPI(title="AI Lab Mem0 API", version="1.0.0")
memory = Memory.from_config(CONFIG)
API_KEY = os.environ.get("MEM0_API_KEY", "")


def check_auth(x_api_key: str | None):
    if API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="X-API-Key inválida o ausente")


class AddRequest(BaseModel):
    messages: list[dict] | None = None   # [{"role": "user", "content": "..."}]
    text: str | None = None              # alternativa simple a messages
    user_id: str                         # namespace: "company_<id>", "lab_admin"
    agent_id: str | None = None
    metadata: dict | None = None


class SearchRequest(BaseModel):
    query: str
    user_id: str
    limit: int = 5


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/memories")
def add_memory(req: AddRequest, x_api_key: str | None = Header(default=None)):
    check_auth(x_api_key)
    msgs = req.messages or [{"role": "user", "content": req.text or ""}]
    if not (req.messages or req.text):
        raise HTTPException(status_code=422, detail="messages o text requerido")
    result = memory.add(msgs, user_id=req.user_id, agent_id=req.agent_id,
                        metadata=req.metadata or {})
    return result


@app.post("/search")
def search(req: SearchRequest, x_api_key: str | None = Header(default=None)):
    check_auth(x_api_key)
    # mem0 >= 1.x exige filters= para el namespace (user_id top-level fue removido)
    return memory.search(req.query, filters={"user_id": req.user_id}, limit=req.limit)


@app.get("/memories")
def get_all(user_id: str, x_api_key: str | None = Header(default=None)):
    check_auth(x_api_key)
    return memory.get_all(filters={"user_id": user_id})


@app.delete("/memories/{memory_id}")
def delete_memory(memory_id: str, x_api_key: str | None = Header(default=None)):
    check_auth(x_api_key)
    memory.delete(memory_id)
    return {"deleted": memory_id}
