# Mem0 — Memoria episódica transversal del AI Lab

Implementa la **Fase 1** del plan (`~/shared/demos/knowledge-management-execution-plan.md`).
Wrapper FastAPI propio sobre la librería `mem0ai` — se eligió esto en vez del server
oficial de Mem0 porque el oficial no incluye el embedder de Ollama (habría que
rebuildear su imagen igual) y agrega un wizard/JWT que el lab no necesita.

## Arquitectura

```
Agente (Hermes / Paperclip / Claude Code / OpenCode)
    │  HTTP REST (puerto 8765, header X-API-Key)
    ▼
Mem0 wrapper (FastAPI, ~200-380MB)
    ├── LLM extracción → OpenCode Zen (deepseek-v4-flash-free, $0) — API OpenAI-compatible
    │                    alternativas: OpenCode Go (pago) u Ollama Cloud (ver .env.example)
    ├── Embeddings     → Ollama local (nomic-embed-text, 768 dims, 20-50ms CPU)
    └── Vector store   → Qdrant embebido (file-based, ./data/qdrant)
```

## Deploy

```bash
cd ~/ai-lab/stacks/mem0
cp .env.example .env        # [HUMANO] completar OPENAI_API_KEY y MEM0_API_KEY
docker compose up -d --build
docker exec ollama ollama pull nomic-embed-text   # una sola vez (~274MB)
```

**De dónde sale la API key:** las credenciales de opencode-zen / opencode-go /
ollama-cloud ya existen en el `credential_pool` de `~/.hermes/auth.json` (las usa
Hermes). Copiar la que corresponda al `.env` — no crear cuentas nuevas.

**Verificar el endpoint antes del deploy** (la key es la misma del .env):
```bash
curl -s https://opencode.ai/zen/v1/models -H "Authorization: Bearer $OPENAI_API_KEY" | head -c 300
```

## Smoke test

```bash
# Health
curl -s http://localhost:8765/health

# Agregar una memoria (namespace de <Empresa A>)
curl -s -X POST http://localhost:8765/memories \
  -H "Content-Type: application/json" -H "X-API-Key: $MEM0_API_KEY" \
  -d '{"text": "Decidimos usar opencode-zen como motor de destilación porque es gratis",
       "user_id": "company_<id>", "agent_id": "claude-code"}'

# Buscar (debe recuperar la memoria anterior)
curl -s -X POST http://localhost:8765/search \
  -H "Content-Type: application/json" -H "X-API-Key: $MEM0_API_KEY" \
  -d '{"query": "qué motor de destilación usamos", "user_id": "company_<id>"}'

# Verificar AISLAMIENTO: con otro user_id NO debe aparecer
curl -s -X POST http://localhost:8765/search \
  -H "Content-Type: application/json" -H "X-API-Key: $MEM0_API_KEY" \
  -d '{"query": "qué motor de destilación usamos", "user_id": "company_otra"}'
```

## Convención de namespaces (decisión cerrada del plan)

| user_id | Quién lo usa |
|---------|--------------|
| `company_<id>` | Agentes trabajando para <Empresa A> |
| `company_<id>` | Futuras empresas |
| `lab_admin` | Solo Hermes, administración del lab |

`agent_id` identifica al agente que escribió (`hermes`, `claude-code`, `opencode`,
`paperclip-<agente>`). Sirve para auditar, no para aislar.

## Integración por agente

- **Hermes:** tool HTTP o MCP apuntando a `http://localhost:8765` (config en
  `~/.hermes/config.yaml`). Patrón: `POST /search` al arrancar tarea, `POST /memories`
  al cerrar con las decisiones tomadas.
- **Paperclip:** el puerto 8765 está bindeado a 127.0.0.1 (seguridad), así que desde
  el contenedor de Paperclip se llega por red Docker, no por el host:
  `docker network connect ai-lab mem0` (una vez) → los agentes usan `http://mem0:8765`.
- **Claude Code / OpenCode:** MCP server `mem0-mcp` apuntando al endpoint, o curl
  directo desde Bash.

## Operación

- Datos en `./data/` (Qdrant + history.db). **Backup:** incluir `~/ai-lab/stacks/mem0/data/` en el backup del lab.
- Logs: `docker logs mem0 --tail 50`
- Si Ollama cambia de modelo de embeddings, hay que regenerar la colección (borrar
  `./data/qdrant` y re-poblar) — las dimensiones deben coincidir (768 para nomic).
