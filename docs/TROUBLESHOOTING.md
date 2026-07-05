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

---

## Windows nativo (Servy + Scoop)

Problemas especificos de la variante Windows nativa (sin WSL2, sin Docker).

### Bootstrap: "Running the installer as administrator is disabled by default" (Scoop)
**Causa:** Scoop detecta PowerShell elevado y aborta por defecto.
**Fix:** el bootstrap pasa `-RunAsAdmin` al instalador. Si falla igualmente:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
iex "& {$(irm get.scoop.sh)} -RunAsAdmin"
```

### Bootstrap: Invoke-WebRequest devuelve `System.Byte[]` en vez de string
**Causa:** PowerShell 5.1 devuelve `System.Byte[]` para `-UseBasicParsing`, no string.
`Invoke-Expression (Invoke-WebRequest ...).Content` falla porque recibe bytes.
**Fix:** ya corregido en el bootstrap. Todos los instaladores descargan a temp file
con `-OutFile` y se ejecutan con `&`. Si aparece en scripts propios, usar el mismo patron:
```powershell
$installer = Join-Path $env:TEMP "script.ps1"
Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
& $installer
Remove-Item $installer -Force
```

### Paperclip PG: exit code 3221225781
**Causa:** `0xC0000135` = DLL faltante (`vcruntime140_1.dll`). El PG embebido de
Paperclip necesita el Visual C++ Redistributable.
**Fix:** el modulo 01 lo instala automaticamente. Si fallo:
```powershell
Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile vc_redist.exe
.\vc_redist.exe /install /quiet /norestart
# Reintentar Paperclip:
npx paperclipai onboard --yes
```

### uv venv: "Do you want to replace it? [y/n]" (prompt interactivo)
**Causa:** ya existe un `.venv` en el directorio y uv pregunta antes de sobreescribir.
**Fix:** ya corregido en el bootstrap. Usar `uv venv --clear` para evitar el prompt:
```powershell
uv venv --clear --python 3.12
```

### Output rojo en consola durante instalacion (uv, pip, npm)
**Causa:** PowerShell 5.1 con `$ErrorActionPreference = "Stop"` trata stderr como
error terminating. uv, pip y npm escriben progreso/warnings a stderr.
**Fix:** ya corregido en los modulos (`$ErrorActionPreference = "Continue"`). Si aparece
en scripts propios, poner `$ErrorActionPreference = "Continue"` al inicio del bloque.

### `nlm` / `mool` no encontrado despues de `uv tool install`
**Causa:** `uv tool install` pone binarios en `~/.local/bin`, que puede no estar en PATH.
**Fix:**
```powershell
# Verificar:
$env:PATH -split ";" | Select-String ".local.bin"
# Si no aparece, agregar:
$p = [Environment]::GetEnvironmentVariable("PATH","User")
[Environment]::SetEnvironmentVariable("PATH","$p;$env:USERPROFILE\.local\bin","User")
# Cerrar y reabrir PowerShell
```

### Servy: "command not found"
**Causa:** Servy se instala via Scoop extras. Puede faltar el bucket o la dependencia `innounp`.
**Fix:**
```powershell
scoop bucket add extras
scoop install innounp
scoop install servy
```

### Servy: servicio no arranca / se detiene inmediatamente
**Diagnostico:**
```powershell
servy logs <nombre>
```
**Causas comunes:**
- El ejecutable no existe en la ruta registrada (se movio o no se instalo)
- Puerto ocupado por otro proceso: `netstat -ano | findstr :<puerto>`
- Dependencia faltante (Node.js, Python, etc.)

### Dagu: descarga fallo / no encontro asset
**Causa:** el repo es `dagucloud/dagu` (no `dagu-org/dagu`). La API de GitHub puede
no devolver el asset esperado si cambiaron el naming.
**Fix manual:**
1. Ir a https://github.com/dagucloud/dagu/releases
2. Descargar el `.zip` que contenga `windows` y `amd64`
3. Extraer `dagu.exe` a `%USERPROFILE%\.local\bin\`

### Tailscale: descarga fallo
**Causa:** Tailscale no esta en Scoop. Se descarga directo del CDN oficial.
**Fix:** descargar manualmente desde https://tailscale.com/download/windows

### Firewall: servicios no accesibles desde Tailscale
**Causa:** las reglas de firewall se crean para la interfaz "Tailscale". Si Tailscale
no estaba configurado al correr el bootstrap, las reglas se crean sin filtro de interfaz
(con warning).
**Fix:** verificar y recrear reglas despues de conectar Tailscale:
```powershell
# Ver reglas existentes:
Get-NetFirewallRule -DisplayName "AI-Lab-*" | Format-Table DisplayName,Enabled
# Borrar y recrear (volver a correr el bootstrap, es idempotente):
.\bootstrap-windows.ps1
```

### Hermes: clone fallo / "Repository not found"
**Causa:** el repo es `NousResearch/hermes-agent` (publico).
**Fix:**
```powershell
git ls-remote https://github.com/NousResearch/hermes-agent.git
# Si falla, verificar conectividad y autenticacion:
gh auth status
```

### Caracteres raros en la consola (mojibake)
**Causa:** PowerShell 5.1 lee archivos UTF-8 como Windows-1252. Caracteres
no-ASCII (em-dash, flechas, box-drawing) se corrompen.
**Fix:** los scripts del bootstrap usan solo caracteres ASCII. Si ves mojibake,
verificar que no se editaron los `.ps1` con un editor que inserte Unicode.

### Windows Defender bloquea un binario descargado
**Causa:** SmartScreen o real-time protection bloquea ejecutables sin firma.
**Fix:** el modulo 01 agrega exclusiones para `~/ai-lab` y `~/.local/bin`.
Si un binario especifico es bloqueado:
```powershell
Add-MpPreference -ExclusionPath "C:\ruta\al\binario.exe"
```
