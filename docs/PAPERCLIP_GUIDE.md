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

## 5. Ajustes obligatorios en docker-compose.yml

Antes de levantar, verificar que `docker/docker-compose.yml` tenga estas secciones en el servicio `server`.
Son cambios que no están en el upstream y se aplican manualmente:

```yaml
name: paperclip      # ← línea 1 del archivo — fija el project name

services:
  server:
    restart: on-failure
    deploy:
      restart_policy:
        condition: on-failure
        delay: 30s        # da tiempo al watchdog de limpiar la DB antes de reiniciar
        max_attempts: 5   # evita crash loop infinito
        window: 120s
    mem_limit: 4g         # impide que zombies opencode consuman toda la RAM del host
    memswap_limit: 4g
    environment:
      OPENCODE_ALLOW_ALL_MODELS: "true"
    volumes:
      - ${HOME}/.opencode:/paperclip/.opencode:ro
      - ${HOME}/.config/opencode:/paperclip/.config/opencode:ro
      - ${HOME}/.local/share/opencode/auth.json:/paperclip/.local/share/opencode/auth.json:ro

volumes:
  pgdata:
    external: true
    name: paperclip_pgdata
  paperclip-data:
    external: true
    name: paperclip_paperclip-data
```

**Por qué el mem_limit:** los procesos opencode pueden quedar zombies acumulando contexto hasta
agotar la RAM del host y provocar un OOM en cascada que mata sesiones SSH y procesos del sistema.
4 GB es suficiente para operación normal (uso real ~1.6 GB) y contiene cualquier fuga.

**Por qué el restart_policy con delay:** al reiniciar inmediatamente después de un OOM, los zombies
de la sesión anterior siguen en la DB como `running` y se vuelven a ejecutar. El delay de 30 s
da tiempo al watchdog (cron) de marcarlos como `failed` antes de que Paperclip levante.

---

## 6. Levantar los contenedores

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

## 7. OPENCODE_ALLOW_ALL_MODELS

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

## 8. Modelos disponibles

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

Modelos de calidad equivalente a Go, sin costo. La lista puede cambiar — verificar disponibilidad
antes de asignar a un agente de producción:

```bash
docker exec paperclip-server-1 opencode models | grep ollama-cloud
```

**Modelos confirmados gratuitos (verificado 2026-06-06):**

| Modelo | Perfil de uso |
|--------|---------------|
| `ollama-cloud/minimax-m3` | Flagship multimodal, 1M context — estrategia y decisión |
| `ollama-cloud/gemma4:31b` | Razonamiento sólido — análisis y planificación |
| `ollama-cloud/nemotron-3-super` | Productividad general — entregables |
| `ollama-cloud/qwen3-coder-next` | Síntesis, narrativa, creación de contenido |
| `ollama-cloud/deepseek-v4-flash` | Misma calidad que Go, sin costo |
| `ollama-cloud/deepseek-v4-pro` | Misma calidad que Go, sin costo |
| `ollama-cloud/kimi-k2.6` | Misma calidad que Go, sin costo |
| `ollama-cloud/qwen3-coder:480b` | Modelo enorme para código |
| `ollama-cloud/kimi-k2:1t` | 1 trillón de parámetros |

---

## 9. Selección de modelo por tipo de agente

| Tipo de agente | Modelo recomendado | Razón |
|---|---|---|
| Estrategia y decisión | `opencode-go/kimi-k2.6` o `qwen3.7-plus` | Contexto largo, razonamiento complejo |
| Análisis y planificación | `opencode-go/deepseek-v4-pro` o `glm-5.1` | Análisis profundo, diseño de frameworks |
| Producción de entregables | `opencode-go/deepseek-v4-flash` | Alto volumen, mayor cuota de requests |
| Monitoreo / heartbeat liviano | `opencode/big-pickle` | Solo verifica estado — costo cero |
| Gran escala (ocasional) | `ollama-cloud/qwen3-coder:480b` | Máxima capacidad, disponibilidad variable |

---

## 10. Crear y configurar agentes

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

## 11. Configuración de heartbeat

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

## 12. Fallback cuando se agota el presupuesto de opencode-go

Hay dos niveles de fallback, en orden de preferencia.

### Fallback nivel 1 — ollama-cloud (gratuito, calidad comparable)

Antes de caer al Zen, probar ollama-cloud — ofrece modelos equivalentes a Go sin costo.

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip <<'SQL'
UPDATE agents SET adapter_config = jsonb_set(adapter_config, '{model}', '"ollama-cloud/minimax-m3"')
  WHERE name = 'Agente-estrategico';
UPDATE agents SET adapter_config = jsonb_set(adapter_config, '{model}', '"ollama-cloud/gemma4:31b"')
  WHERE name = 'Agente-analisis';
UPDATE agents SET adapter_config = jsonb_set(adapter_config, '{model}', '"ollama-cloud/nemotron-3-super"')
  WHERE name = 'Agente-entregables';
SQL
```

> Verificar disponibilidad primero: `docker exec paperclip-server-1 opencode models | grep ollama-cloud`

### Fallback nivel 2 — Zen gratuito garantizado

> **Síntoma típico de quota agotada:** error HTTP 429 en logs, heartbeats quedan en status
> `running` durante horas sin output (zombies). Limpiar zombies antes de activar el fallback
> — ver sección "Operaciones de emergencia".

```bash
# Migrar todos los agentes al tier gratuito
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE agents
SET adapter_config = jsonb_set(adapter_config, '{model}', '\"opencode/big-pickle\"')
WHERE adapter_type = 'opencode_local';
"
```

### Restaurar Go al inicio del siguiente periodo

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

## 13. Operaciones de mantenimiento

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

### Heartbeats zombies tras error 429 (quota agotada)

Cuando Go devuelve 429, los procesos pueden quedar colgados en status `running` sin output.
Limpiarlos antes de activar cualquier fallback:

```bash
# 1. Forzar fallo de todos los zombies (sin output, >30 min corriendo)
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE heartbeat_runs
SET status = 'failed',
    error = 'Zombie terminado manualmente tras error 429',
    finished_at = NOW()
WHERE status IN ('running','queued')
  AND started_at < NOW() - INTERVAL '30 minutes'
  AND stdout_excerpt IS NULL;
"

# 2. Cancelar issues falsos generados por el watchdog
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE issues SET status = 'cancelled'
WHERE status NOT IN ('done','cancelled')
  AND (title LIKE 'Review silent active run%'
    OR title LIKE 'Company idle%');
"

# 3. Matar procesos opencode huérfanos en el contenedor
docker exec paperclip-server-1 sh -c "pkill -f 'opencode run' 2>/dev/null; echo ok"
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

## 14. Watchdog automático de zombies

Cuando un provider no responde (ollama-cloud inestable, red, timeout), el proceso `opencode`
queda colgado indefinidamente. Paperclip no detecta esto — el heartbeat aparece como `running`
para siempre, bloqueando al agente y acumulando procesos en el contenedor.

**Instalar el watchdog** (corre cada 15 minutos, mata procesos colgados >10 min sin output):

```bash
# Crear el script
mkdir -p ~/ai-lab/scripts
cat > ~/ai-lab/scripts/paperclip-watchdog.sh << 'EOF'
#!/bin/bash
ZOMBIES=$(docker exec paperclip-db-1 psql -U paperclip -d paperclip -t -c "
SELECT COUNT(*) FROM heartbeat_runs
WHERE status = 'running'
  AND stdout_excerpt IS NULL
  AND started_at < NOW() - INTERVAL '10 minutes';
" 2>/dev/null | tr -d ' ')

if [ "$ZOMBIES" -gt "0" ] 2>/dev/null; then
  docker exec paperclip-server-1 sh -c \
    "kill \$(cat /proc/*/cmdline 2>/dev/null | tr '\0\n' '  ' | grep -o '[0-9]* /usr/local/bin/opencode' | awk '{print \$1}') 2>/dev/null" \
    2>/dev/null
  docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
    UPDATE heartbeat_runs
    SET status = 'failed',
        error = 'Watchdog: proceso colgado >10min sin output',
        finished_at = NOW()
    WHERE status = 'running'
      AND stdout_excerpt IS NULL
      AND started_at < NOW() - INTERVAL '10 minutes';
  " 2>/dev/null
  echo "\$(date): watchdog eliminó \$ZOMBIES zombie(s)"
fi
EOF
chmod +x ~/ai-lab/scripts/paperclip-watchdog.sh

# Agregar al crontab
(crontab -l 2>/dev/null; echo "*/15 * * * * ~/ai-lab/scripts/paperclip-watchdog.sh >> ~/ai-lab/scripts/watchdog.log 2>&1") | crontab -
```

**Regla de oro:** mantener los agentes en `opencode-go` siempre. Solo cambiar a `ollama-cloud`
manualmente cuando se agote el periodo de Go — nunca como fallback automático, porque
ollama-cloud puede no responder y genera zombies.

---

## 15. Bug conocido: ENOSPC en /tmp

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
