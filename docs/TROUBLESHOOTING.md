# Troubleshooting — síntoma → causa → fix

Problemas reales encontrados en producción, con su diagnóstico y solución exacta.
Complementa a [`LESSONS.md`](LESSONS.md) (el porqué) — esto es el "qué hago AHORA".

---

## Plugins de Paperclip

### "Package ... does not appear to be a Paperclip plugin (no manifest found)" al instalar
**Causa:** el manifest del plugin es un artefacto de build (`dist/manifest.js`) y la
imagen Docker no compila plugins (son alpha).
**Fix:**
```bash
docker exec -w /app/packages/plugins/<plugin> <server-container> pnpm build
# reintentar Install en la UI
```
**Prevención:** persistir el `dist/` con un bind mount desde el host — si no, cada
recreate del contenedor lo borra.

### Plugin instalado pero "no ready plugins to load" / status=error
**Causa:** el contenedor arrancó alguna vez sin el `dist/` → activación falló → el
loader solo carga plugins en `status='ready'` y no reintenta los `error`.
**Fix:**
```bash
docker exec <db-container> psql -U <user> -d <db> \
  -c "UPDATE plugins SET status='ready', last_error=NULL WHERE plugin_key='<key>';"
docker compose restart server
docker logs <server-container> | grep "plugin activated successfully"
```

### El plugin de wiki no puede escribir (Writable: No)
**Causa:** wiki root apuntando a un mount read-only.
**Fix:** el plugin necesita escribir en SU root (crea raw/, wiki/, log.md...). Darle un
sub-árbol rw anidado dentro del knowledge ro: mount del padre `:ro` + mount del hijo
`wiki/` sin `:ro` (el orden en `volumes:` importa: padre antes que hijo).

---

## Outline (retirado — referencia histórica)

### Login con Google vuelve siempre a la pantalla de inicio (loop)
**Diagnóstico:** `docker logs outline | grep -i error` →
`Cannot create account using personal gmail address`
**Causa:** el plugin nativo de Google exige Google Workspace.
**Fix:** mismas credenciales como OIDC genérico — en el `.env`: quitar `GOOGLE_*`, poner
`OIDC_CLIENT_ID/SECRET`, `OIDC_AUTH_URI=https://accounts.google.com/o/oauth2/v2/auth`,
`OIDC_TOKEN_URI=https://oauth2.googleapis.com/token`,
`OIDC_USERINFO_URI=https://openidconnect.googleapis.com/v1/userinfo`.
Agregar en Google Console la redirect URI `https://<host>/auth/oidc.callback` (propaga en ~5 min).

### "Servidor no encontrado" al abrir la URL .ts.net desde otra máquina
**Causa:** esa máquina no usa el DNS de Tailscale (MagicDNS).
**Fix:** en el cliente Tailscale de esa máquina, activar "Use Tailscale DNS" (o
toggle off/on). Verificar el lado servidor con `curl https://<host>.ts.net` local.
**No** hacer el login OAuth por IP: el callback está registrado con el nombre.

### Error "Origen no válido: los URI no deben contener una ruta" en Google Console
**Causa:** se pegó la URI con ruta (`/auth/...`) en "Orígenes de JavaScript".
**Fix:** orígenes = solo `https://host` sin ruta; las URIs con ruta van en
"URIs de redireccionamiento autorizados".

---

## Red / Docker / UFW

### Un monitor (u otro contenedor) no llega a un servicio bare metal del host
**Síntoma:** `curl` desde el contenedor da timeout (código 000) hacia
`172.17.0.1:<puerto>` o la IP del host, pero desde otra máquina funciona.
**Causa:** UFW filtra contenedor→host: el tráfico sale con IP de origen 172.x y las
reglas solo permiten Tailscale/LAN.
**Fix:** `sudo ufw allow from 172.16.0.0/12 to any port <puerto> proto tcp`

### Un servicio bindeado a 127.0.0.1 no es alcanzable desde otro contenedor
**Causa:** 127.0.0.1 del host no es visible entre contenedores.
**Fix:** conectar los contenedores a la misma red Docker y usar el nombre:
`docker network connect <red> <contenedor>` → `http://<servicio>:<puerto>`.

### Postgres no arranca / índices corruptos tras cambiar de imagen
**Causa:** cambio alpine↔debian (musl↔glibc) sobre el mismo volumen — collation.
**Fix:** volver a la imagen original (el volumen viejo es el rollback), luego migrar
bien: `pg_dumpall` → volumen NUEVO → init limpio con la imagen nueva → restore →
`CREATE EXTENSION` que falte → validar contadores de filas.

---

## Pipeline de conocimiento

### El ingest semanal no corrió / no llegó la notificación
1. El push monitor (dead-man's-switch) debería haber alertado por sí solo
2. `tail -50 ~/ai-lab/logs/ingest-<id>.log` — el script continúa ante fallos: buscar `ERROR:`
3. Lock huérfano: `ls /tmp/weekly-ingest-*.lock` → borrar si no hay proceso vivo
4. Orquestador caído: el script se auto-reprograma a +30 min (systemd-run); verificar el servicio

### El ingest reprocesa todo cada vez (lento/caro)
**Causa:** estado incremental ausente o borrado (`.processed.yaml`).
**Fix:** verificar que los extractores reciben `--output-dir` consistente (el estado
vive ahí). Para re-procesar UNA fuente a propósito: borrar solo su entrada del YAML.

### La destilación contiene errores sutiles (planes reportados como hechos, reglas invertidas)
**Causa:** LLM gratis destilando matices.
**Fix:** revisión humana de la PRIMERA destilación (es la semilla); correcciones con
nota de fecha. Las corridas incrementales siguientes solo agregan.

### Los comandos del orquestador fallan en cron con "command not found"
**Causa:** el binario no está en PATH de shells no interactivos.
**Fix:** ruta absoluta del venv en todos los scripts (ej: `$HOME/.hermes-env/bin/hermes`).

### El agente no encuentra archivos que "deberían estar" (rutas con ~)
**Causa:** el sandbox del orquestador resuelve `~` a un home interno propio.
**Fix:** rutas absolutas en TODO lo que se documente para agentes.

---

## Mem0

### `search()` da 500: "Top-level entity parameters ... not supported"
**Causa:** mem0 ≥1.x cambió la API: `user_id` top-level ya no va en search/get_all.
**Fix:** `memory.search(query, filters={"user_id": ...})` (el wrapper de
`stacks/mem0/app.py` ya lo hace).

### Las búsquedas devuelven vacío tras cambiar el modelo de embeddings
**Causa:** dimensiones distintas entre colección vieja y embedder nuevo.
**Fix:** borrar `stacks/mem0/data/qdrant` y re-poblar. Las dimensiones del embedder
y de la colección DEBEN coincidir (nomic-embed-text = 768).

---

## Multi-empresa

### Una empresa nueva (clonada) tiene archivos de otra empresa en sus workspaces
**Causa:** la portabilidad de Paperclip copia los workspaces CON contenido.
**Fix:** `docker exec <server> find /paperclip/instances/default/workspaces/<agent_id> -mindepth 1 -delete`
por cada agente clonado, ANTES de que operen. Verificar después que el espejo quede vacío.

### Espejos de dos empresas se pisan entre sí
**Causa:** dos empresas con agentes del mismo nombre (ej: "CEO") + espejo enrutado
solo por nombre — `rsync --delete` hace que el último gane.
**Fix:** enrutar por empresa (join `agents`→`companies.issue_prefix`), destino
separado por empresa. Los datos reales siguen intactos en el contenedor: re-sync tras el fix.

### OpenCode CLI da ENOSPC en /tmp
**Causa:** bug conocido — acumula `*.so` en /tmp.
**Fix (cron horario):** `find /tmp -name '*.so' -mmin +60 -not -lname '*.so' -delete`
