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
    }
  }
}
```

Cada provider tiene su API key separada. Obtenerlas en `https://opencode.ai` → Settings → API Keys:
- **opencode** (Zen) — tier gratuito
- **opencode-go** — suscripción mensual, mayor cuota de requests

> Este archivo se monta como read-only en el contenedor de Paperclip.
> Cualquier cambio en el host se refleja inmediatamente sin reiniciar el contenedor.

### Verificar providers desde el contenedor

```bash
docker exec paperclip-server-1 opencode providers list
# Debe listar los providers con sus credenciales
```

---

## 4. Volúmenes Docker

Paperclip usa volúmenes externos con nombres específicos. Crearlos antes del primer arranque:

```bash
docker volume create paperclip_pgdata
docker volume create paperclip_paperclip-data
```

> El prefijo `paperclip_` viene del campo `name: paperclip` al inicio del `docker-compose.yml`.
> Sin ese campo, Docker deriva el nombre del directorio (`docker_`) y los volúmenes no coinciden.

---

## 5. Levantar los contenedores

```bash
cd ~/ai-lab/repos/paperclip
docker compose -f docker/docker-compose.yml --env-file docker/.env up -d --build
```

Verificar que los contenedores están activos:
```bash
docker ps | grep paperclip
# paperclip-server-1   Up   :3100
# paperclip-db-1       Up   (healthy)
```

La UI queda disponible en `http://<ip-del-servidor>:3100`.

---

## 6. Configurar modelos — OPENCODE_ALLOW_ALL_MODELS

El `docker-compose.yml` debe tener esta variable en el servicio `server`:

```yaml
environment:
  OPENCODE_ALLOW_ALL_MODELS: "true"
```

Sin ella, el adapter `opencode_local` rechaza providers que no estén en su lista hardcodeada
(como `opencode-go`). Con la variable en `true`, acepta cualquier provider configurado en `auth.json`.

Verificar que está activa:
```bash
docker inspect paperclip-server-1 | grep OPENCODE_ALLOW
```

---

## 7. Crear y configurar agentes

### Desde la UI

1. Ir a la empresa → **New Agent**
2. Nombre, título, descripción del rol
3. **Adapter:** `OpenCode (local)`
4. **Model:** ID completo en formato `provider/modelo`
   - Ej: `opencode-go/deepseek-v4-flash`
   - Ej: `opencode/big-pickle`
5. Guardar

### Modelos disponibles

**opencode-go** (suscripción):

| Modelo | Perfil de uso |
|---|---|
| `opencode-go/kimi-k2.6` | Contexto largo, decisión estratégica |
| `opencode-go/deepseek-v4-pro` | Análisis profundo, código complejo |
| `opencode-go/deepseek-v4-flash` | Alto volumen, entregables — mejor relación costo/req |
| `opencode-go/qwen3.7-plus` | Razonamiento general |
| `opencode-go/mimo-v2.5` | Muy alto volumen |

**opencode** (Zen, gratuito):

| Modelo | Notas |
|---|---|
| `opencode/big-pickle` | Uso general gratuito |
| `opencode/deepseek-v4-flash-free` | Rápido, gratuito |
| `opencode/nemotron-3-ultra-free` | Gratuito, mayor capacidad |

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

## 8. Fallback cuando se agota el presupuesto

Cuando el presupuesto de `opencode-go` se agota, migrar todos los agentes al tier gratuito:

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip -c "
UPDATE agents
SET adapter_config = jsonb_set(adapter_config, '{model}', '\"opencode/big-pickle\"')
WHERE adapter_type = 'opencode_local';
"
```

Restaurar al inicio del siguiente periodo:

```bash
docker exec paperclip-db-1 psql -U paperclip -d paperclip <<'SQL'
UPDATE agents SET adapter_config = jsonb_set(adapter_config, '{model}', '"opencode-go/deepseek-v4-pro"')
WHERE name = 'NombreAgente';
SQL
```

---

## 9. Operaciones de mantenimiento

### Rebuild de imagen

Necesario cuando se modifica el código del adapter o el Dockerfile:

```bash
cd ~/ai-lab/repos/paperclip
docker compose -f docker/docker-compose.yml build server
docker compose -f docker/docker-compose.yml up -d server
# La DB no se toca — los volúmenes persisten
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

---

## 10. Bug conocido: ENOSPC en /tmp

OpenCode extrae una librería en `/tmp` en cada heartbeat y no la limpia.
Con el tiempo llena el disco y los agentes fallan con error `ENOSPC`.

**Mitigación (agregar al crontab del host):**

```bash
crontab -e
# Agregar:
0 * * * * find /tmp -name "*.so" -mmin +60 -not -lname "*.so" -delete 2>/dev/null
```

Es un bug upstream de OpenCode — no tiene solución definitiva aún.

---

## 11. Troubleshooting

### Contenedores se llaman `docker-*` en vez de `paperclip-*`

**Causa:** El `docker-compose.yml` no tiene `name: paperclip` como primera línea.  
**Fix:** Agregar `name: paperclip` al inicio del archivo y recrear los contenedores.

### Agentes sin modelos disponibles

Verificar que `OPENCODE_ALLOW_ALL_MODELS=true` está activo:
```bash
docker inspect paperclip-server-1 | grep OPENCODE_ALLOW
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

El `.env` no está en `docker/` o la variable no está definida:
```bash
cat ~/ai-lab/repos/paperclip/docker/.env
```

### Recuperar el secret de un contenedor detenido

```bash
docker inspect <nombre-contenedor> | grep BETTER_AUTH_SECRET
```
