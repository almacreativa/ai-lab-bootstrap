# Paperclip — Guía de infraestructura y configuración

Paperclip es una plataforma de orquestación de agentes de IA, autoalojada vía Docker Compose.
En este stack, cada agente usa el adapter `opencode_local`, que ejecuta el binario OpenCode
del host como subproceso. Los providers de modelos se configuran en el host y se montan
en el contenedor como read-only.

```
┌─────────────────────────────────────────────────────────────┐
│  Host Ubuntu                                                 │
│                                                             │
│  ~/.opencode/bin/opencode           ← binario OpenCode     │
│  ~/.config/opencode/opencode.jsonc  ← config general       │
│  ~/.local/share/opencode/auth.json  ← credenciales         │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Docker Compose (project: paperclip)                  │  │
│  │                                                       │  │
│  │  paperclip-db-1    paperclip-server-1                 │  │
│  │  postgres:17       :3100  UI + API                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 1. Prerequisitos

El bootstrap instala OpenCode automáticamente. Verificar antes de levantar Paperclip:

```bash
~/.opencode/bin/opencode --version
```

Si no está instalado:
```bash
curl -fsSL https://opencode.ai/install | bash
```

---

## 2. Variables de entorno

**Ubicación:** `~/ai-lab/repos/paperclip/docker/.env`  
**No commitear este archivo.**

```bash
# Generar BETTER_AUTH_SECRET (una sola vez):
openssl rand -hex 32

# Contenido del .env:
BETTER_AUTH_SECRET=<resultado-de-openssl>
PAPERCLIP_PUBLIC_URL=http://<ip-del-servidor>:3100
```

El bootstrap crea este archivo interactivamente. Para regenerarlo manualmente,
usar el template: `templates/paperclip.env.example`.

---

## 3. Providers de OpenCode — auth.json

**Ubicación:** `~/.local/share/opencode/auth.json`  
**Permisos:** `chmod 600 ~/.local/share/opencode/auth.json`

```json
{
  "providers": {
    "opencode": {
      "type": "opencode",
      "apiKey": "zen_<clave-api-opencode-zen>"
    },
    "opencode-go": {
      "type": "opencode",
      "apiKey": "go_<clave-api-opencode-go>"
    },
    "ollama-cloud": {
      "type": "opencode",
      "apiKey": "<clave-api-ollama-cloud>"
    }
  }
}
```

Obtener API keys:
- **opencode / opencode-go:** `https://opencode.ai` → Settings → API Keys
- **ollama-cloud:** desde la UI de Ollama Cloud

> Este archivo se monta como read-only en el contenedor de Paperclip.
> Cualquier cambio en el host se refleja inmediatamente sin reiniciar el contenedor.

### Verificar providers desde el contenedor

```bash
docker exec paperclip-server-1 opencode providers list
```

---

## 4. Volúmenes Docker

Crear antes del primer arranque:

```bash
docker volume create paperclip_pgdata
docker volume create paperclip_paperclip-data
```

> El prefijo `paperclip_` viene del campo `name: paperclip` al inicio del `docker-compose.yml`.
> Sin ese campo, Docker deriva el nombre del directorio y los volúmenes no coinciden.

---

## 5. Levantar los contenedores

```bash
cd ~/ai-lab/repos/paperclip
docker compose -f docker/docker-compose.yml --env-file docker/.env up -d --build
```

Verificar:
```bash
docker ps | grep paperclip
# paperclip-server-1   Up   :3100
# paperclip-db-1       Up   (healthy)
```

---

## 6. OPENCODE_ALLOW_ALL_MODELS

El `docker-compose.yml` debe tener esta variable en el servicio `server`:

```yaml
environment:
  OPENCODE_ALLOW_ALL_MODELS: "true"
```

Sin ella, el adapter rechaza providers que no estén en su lista hardcodeada (`opencode-go`, `ollama-cloud`).

```bash
# Verificar que está activa:
docker inspect paperclip-server-1 | grep OPENCODE_ALLOW
```

---

## 7. Modelos disponibles

### opencode-go — suscripción (~$10/mes)

Límites: $12 cada 5h · $30/semana · $60/mes

| Modelo | Req/5h | Perfil de uso |
|--------|--------|---------------|
| `opencode-go/deepseek-v4-flash` | ~31.650 | Alto volumen, entregables repetitivos |
| `opencode-go/mimo-v2.5` | ~30.100 | Muy alto volumen, tareas simples |
| `opencode-go/qwen3.7-plus` | ~4.300 | Razonamiento general, decisión estratégica |
| `opencode-go/deepseek-v4-pro` | ~3.450 | Análisis profundo, planificación |
| `opencode-go/mimo-v2.5-pro` | ~3.250 | Depuración, refactorización |
| `opencode-go/qwen3.6-plus` | ~3.300 | Alternativa a qwen3.7-plus |
| `opencode-go/minimax-m2.7` | ~3.400 | Latencia baja |
| `opencode-go/minimax-m2.5` | ~6.300 | Latencia muy baja, máximo volumen |
| `opencode-go/minimax-m3` | ~1.400 | Latencia baja, tareas repetitivas |
| `opencode-go/kimi-k2.5` | ~1.850 | Contexto largo, alternativa a k2.6 |
| `opencode-go/kimi-k2.6` | ~1.150 | Contexto muy largo, decisión estratégica |
| `opencode-go/glm-5` | ~1.150 | Lógica compleja |
| `opencode-go/glm-5.1` | ~880 | Análisis de dependencias |
| `opencode-go/qwen3.7-max` | ~950 | Razonamiento general fuerte |

### opencode — Zen (gratuito garantizado)

| Modelo | Notas |
|--------|-------|
| `opencode/big-pickle` | Uso general gratuito |
| `opencode/deepseek-v4-flash-free` | Rápido, gratuito |
| `opencode/mimo-v2.5-free` | Gratuito |
| `opencode/minimax-m3-free` | Gratuito |
| `opencode/nemotron-3-ultra-free` | Mayor capacidad del tier gratuito |

### ollama-cloud — tier gratuito (disponibilidad variable)

La lista puede cambiar. Verificar antes de asignar a un agente de producción:

```bash
docker exec paperclip-server-1 opencode models | grep ollama-cloud
```

Modelos notables cuando están disponibles:
- `ollama-cloud/deepseek-v4-flash` — misma calidad que Go, sin costo
- `ollama-cloud/deepseek-v4-pro` — misma calidad que Go, sin costo
- `ollama-cloud/kimi-k2.6` — misma calidad que Go, sin costo
- `ollama-cloud/qwen3-coder:480b` — modelo enorme para código
- `ollama-cloud/kimi-k2:1t` — 1 trillón de parámetros

---

## 8. Selección de modelo por tipo de agente

| Tipo de agente | Modelo recomendado | Razón |
|---|---|---|
| Estrategia y decisión | `opencode-go/kimi-k2.6` o `qwen3.7-plus` | Contexto largo, razonamiento complejo |
| Análisis y planificación | `opencode-go/deepseek-v4-pro` o `glm-5.1` | Análisis profundo, diseño de frameworks |
| Producción de entregables | `opencode-go/deepseek-v4-flash` | Alto volumen, mayor cuota de requests |
| Monitoreo / heartbeat liviano | `opencode/big-pickle` | Solo verifica estado — costo cero |
| Gran escala (ocasional) | `ollama-cloud/qwen3-coder:480b` | Máxima capacidad, disponibilidad variable |

---

## 9. Crear y configurar agentes

### Desde la UI

1. Ir a la empresa → **New Agent**
2. Nombre, título, descripción del rol
3. **Adapter:** `OpenCode (local)`
4. **Model:** ID completo en formato `provider/modelo`
5. Guardar

### Verificar modelo de un agente via DB

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip \
  -c "SELECT name, adapter_config->>'model' AS model FROM agents ORDER BY name;"
```

### Cambiar modelo de un agente via DB

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip \
  -c "UPDATE agents
      SET adapter_config = jsonb_set(adapter_config, '{model}', '\"opencode-go/deepseek-v4-flash\"')
      WHERE name = 'NombreAgente';"
```

---

## 10. Configuración de heartbeat

El heartbeat es el pulso periódico de cada agente — aunque no haya tareas pendientes, el agente
invoca el LLM en cada ciclo. Con el intervalo por defecto de 5 minutos y varios agentes,
el consumo en idle es significativo.

**Referencia observada:** con `intervalSec=300` (5 min) y 3 agentes → ~706 llamadas/día en idle.
Con intervalos de 15-20 min → ~180 llamadas/día. Reducción del 75% sin impacto operativo.

### Intervalos recomendados

| Tipo de agente | intervalSec | Justificación |
|----------------|-------------|---------------|
| Estratégico / directivo | 1200 (20 min) | No requiere respuesta inmediata |
| Operativo / de entregables | 900 (15 min) | Recibe tareas con más frecuencia |
| Monitoreo activo | 300 (5 min) | Solo si la latencia de respuesta importa |

### Cambiar intervalo

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE agents
SET runtime_config = jsonb_set(runtime_config, '{heartbeat,intervalSec}', '1200')
WHERE name = 'NombreAgente';
"
```

### Ver intervalos actuales

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
SELECT name,
  (runtime_config->'heartbeat'->>'intervalSec')::int AS seg,
  (runtime_config->'heartbeat'->>'intervalSec')::int / 60 AS min
FROM agents ORDER BY name;
"
```

---

## 11. Fallback cuando se agota el presupuesto

Migrar todos los agentes al tier gratuito:

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE agents
SET adapter_config = jsonb_set(adapter_config, '{model}', '\"opencode/big-pickle\"')
WHERE adapter_type = 'opencode_local';
"
```

Restaurar al inicio del siguiente periodo (ajustar nombres y modelos según tu config):

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip <<'SQL'
UPDATE agents SET adapter_config = jsonb_set(adapter_config, '{model}', '"opencode-go/qwen3.7-plus"')
  WHERE name = 'Agente1';
UPDATE agents SET adapter_config = jsonb_set(adapter_config, '{model}', '"opencode-go/deepseek-v4-pro"')
  WHERE name = 'Agente2';
UPDATE agents SET adapter_config = jsonb_set(adapter_config, '{model}', '"opencode-go/deepseek-v4-flash"')
  WHERE name = 'Agente3';
SQL
```

---

## 12. Operaciones de mantenimiento

### Rebuild de imagen

```bash
cd ~/ai-lab/repos/paperclip
docker compose -f docker/docker-compose.yml build server
docker compose -f docker/docker-compose.yml up -d server
```

### Reiniciar solo el servidor

```bash
docker compose -f ~/ai-lab/repos/paperclip/docker/docker-compose.yml restart server
```

### Logs en tiempo real

```bash
docker compose -f ~/ai-lab/repos/paperclip/docker/docker-compose.yml logs -f server
```

### Agente bloqueado por desbordamiento de contexto

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
DELETE FROM agent_task_sessions
WHERE agent_id = (SELECT id FROM agents WHERE name = 'NombreAgente');

UPDATE agent_runtime_state
SET session_id = NULL, state_json = '{}'
WHERE agent_id = (SELECT id FROM agents WHERE name = 'NombreAgente');
"
```

### Ver modelos disponibles en tiempo real

```bash
docker exec paperclip-server-1 opencode models | grep "opencode-go\|ollama-cloud\|^opencode/" | sort
```

---

## 13. Bug conocido: ENOSPC en /tmp

OpenCode extrae una librería en `/tmp` en cada heartbeat y no la limpia.
Con el tiempo llena el disco y los agentes fallan con `ENOSPC`.

**Mitigación (agregar al crontab del host):**

```bash
crontab -e
# Agregar:
0 * * * * find /tmp -name "*.so" -mmin +60 -not -lname "*.so" -delete 2>/dev/null
```

Bug upstream de OpenCode — sin solución definitiva aún.

---

## 14. Troubleshooting

### Contenedores se llaman `docker-*` en vez de `paperclip-*`

**Causa:** El `docker-compose.yml` no tiene `name: paperclip` como primera línea.  
**Fix:** Agregar `name: paperclip` al inicio y recrear los contenedores.

### Agentes sin modelos disponibles

```bash
docker inspect paperclip-server-1 | grep OPENCODE_ALLOW
# Debe mostrar OPENCODE_ALLOW_ALL_MODELS=true
```

### OpenCode no ve los providers desde el contenedor

```bash
docker exec paperclip-server-1 opencode providers list
```

Si muestra "0 credentials", verificar que el volumen apunta correctamente:
```yaml
# Correcto (HOME del contenedor es /paperclip, no /root):
- ${HOME}/.local/share/opencode/auth.json:/paperclip/.local/share/opencode/auth.json:ro
```

### Error: `BETTER_AUTH_SECRET must be set`

```bash
cat ~/ai-lab/repos/paperclip/docker/.env
# Debe tener BETTER_AUTH_SECRET=<valor>
```

### Recuperar el secret de un contenedor detenido

```bash
docker inspect <nombre-contenedor> | grep BETTER_AUTH_SECRET
```

---

## 15. Adapter HTTP (pendiente)

El adapter `opencode_http` está en desarrollo upstream. Cuando llegue al branch main,
los agentes podrán migrar de `opencode_local` a `opencode_http` sin pérdida de datos.

**No construir una implementación propia** — riesgo de obsolescencia.

Migración cuando esté disponible:
- Cambiar `adapter_type` de `opencode_local` a `opencode_http` en la DB
- Agregar un contenedor OpenCode server al compose (puerto 4096)
