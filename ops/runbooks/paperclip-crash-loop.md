# Paperclip Crash Loop — EAI_AGAIN y puertos vacíos

## EAI_AGAIN (DNS resolution failed)

**Síntoma:** Paperclip server logs muestran:
```
Error: getaddrinfo EAI_AGAIN paperclip-db-1
```

**Causa:** El endpoint de red del container se corrompió. Docker mantiene una referencia stale a la network, y el DNS interno no resuelve.

**Fix:**
```bash
cd ~/ai-lab/stacks/paperclip
docker compose up -d --force-recreate server
```

`docker start` NO funciona en este caso — se necesita `--force-recreate` para que Docker regenere el endpoint de red.

**Verificar:**
```bash
docker logs paperclip-server-1 --tail 20
docker exec paperclip-server-1 ping paperclip-db-1
```

## Puerto vacío (container "running" pero inaccesible)

**Síntoma:** `docker ps` muestra el container como running pero no hay port binding. `curl localhost:3100` rechaza conexión.

**Afecta:** Paperclip, Odysseus, Portainer (cualquier container)

**Causa:** El container se inició pero el proceso interno falló silenciosamente. Docker lo reporta como "running" porque el PID 1 sigue vivo (puede ser un shell wrapper).

**Diagnóstico:**
```bash
# Ver logs del container
docker logs paperclip-server-1 --tail 50

# Verificar que el proceso está escuchando
docker exec paperclip-server-1 ss -tlnp

# Verificar port mapping
docker port paperclip-server-1
```

**Fix:**
```bash
docker compose restart server
# o si persiste:
docker compose up -d --force-recreate server
```

## Paperclip DB connection refused al boot

**Síntoma:** Paperclip server falla inmediatamente después de boot del servidor porque la DB no está lista.

**Causa:** Race condition — `paperclip-server-1` inicia antes de que `paperclip-db-1` acepte conexiones.

**Fix:**
El servicio `paperclip-boot-cleanup.service` (systemd user) debería manejar esto. Si no:

```bash
# Esperar a que la DB esté lista
docker exec paperclip-db-1 pg_isready -U paperclip
# Luego reiniciar server
docker compose -f ~/ai-lab/stacks/paperclip/docker-compose.yml restart server
```

## Limpieza de containers huérfanos

Si hay containers con nombres duplicados o en estado conflictivo:

```bash
# Listar todos (incluyendo stopped)
docker ps -a --filter name=paperclip

# Eliminar huérfanos
docker compose -f ~/ai-lab/stacks/paperclip/docker-compose.yml down
docker compose -f ~/ai-lab/stacks/paperclip/docker-compose.yml up -d
```
