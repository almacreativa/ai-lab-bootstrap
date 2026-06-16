# Convención de namespacing — Mem0 (memoria episódica del lab)

**Endpoint:** `http://127.0.0.1:8765` (host) / `http://mem0:8765` (desde contenedores en la red de Paperclip)
**Auth:** header `X-API-Key` (valor en `~/ai-lab/stacks/mem0/.env` y `~/.hermes/.env`)

## Namespaces (user_id)

| user_id | Quién escribe/lee |
|---------|-------------------|
| `company_<COMPANY_A_UUID>` | Todo agente trabajando para Example Corp |
| `company_<COMPANY_B_UUID>` | Todo agente trabajando para Company B |
| `company_<id>` | Futuras empresas (aislamiento total entre sí) |
| `lab_admin` | Solo Hermes — administración del lab |

`agent_id` identifica quién escribió (`hermes`, `claude-code`, `opencode`, `paperclip-ceo`, ...). Audita, no aísla.

## Patrón de uso para agentes

```bash
# Al ARRANCAR una tarea: buscar contexto previo
curl -s -X POST http://127.0.0.1:8765/search \
  -H "Content-Type: application/json" -H "X-API-Key: $MEM0_API_KEY" \
  -d '{"query": "<tema de la tarea>", "user_id": "company_<COMPANY_A_UUID>", "limit": 5}'

# Al CERRAR una tarea: registrar decisiones tomadas
curl -s -X POST http://127.0.0.1:8765/memories \
  -H "Content-Type: application/json" -H "X-API-Key: $MEM0_API_KEY" \
  -d '{"text": "<decisión + por qué>", "user_id": "company_<COMPANY_A_UUID>", "agent_id": "<quien>"}'
```

## Reglas

- NUNCA escribir credenciales/tokens en memorias.
- Una memoria = un hecho o decisión con su porqué, no un transcript.
- Cross-empresa prohibido: jamás consultar un namespace de otra empresa.
