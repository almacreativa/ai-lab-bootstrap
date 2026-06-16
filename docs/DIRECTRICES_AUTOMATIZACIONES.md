# Directrices para crear automatizaciones
**Actualizado:** 2026-06-11 · Aplica a: crons (de Hermes y del sistema), skills,
integraciones, scripts, agentes nuevos y cualquier cosa que consuma servicios del lab.

Cada regla nació de un incidente real (referencia entre paréntesis al runbook/lecciones).

## Las 8 reglas

1. **Credenciales: NUNCA embebidas.** Ni en prompts de cron, ni en skills, ni en
   scripts, ni en outputs. Viven en `~/.hermes/.env` (o el `.env` del stack que
   corresponda, 600) y se referencian:
   `grep <NOMBRE_KEY> $HOME/.hermes/.env`
   El prompt debe incluir "NUNCA incluyas la key en tu respuesta" — los outputs se
   destilan al knowledge. *(Incidente: key del board en el prompt del Paperclip Monitor.)*

2. **Rutas SIEMPRE absolutas** (`$HOME/...`). El sandbox de Hermes
   resuelve `~` a `~/.hermes/home/`; el cron del sistema no tiene el PATH del shell.
   Binario de Hermes: `$HOME/.hermes-env/bin/hermes`. *(Lecciones #4 y #5.)*

3. **Endpoints reales, no localhost por costumbre.** Los binds del lab (post-hardening):
   - Paperclip → `http://<PAPERCLIP_HOST>:3100`
   - Mem0 → `http://127.0.0.1:8765` (desde contenedores: `http://mem0:8765`)
   - Outline → `https://<HOSTNAME>.<TAILSCALE_DOMAIN>` (API local: `http://127.0.0.1:3010/api`)
   - Hermes dashboard → `http://localhost:9119` (bare metal, este sí)
   - Kuma → `http://<SERVER_IP>:3001`
   La lista viva está en `SERVICIOS.md`. *(Incidente: falsas alarmas del monitor por localhost:3100.)*

4. **Registrar el consumidor — nada de consumidores invisibles.** Al crear la
   automatización, en el mismo momento:
   - Agregarla a la tabla **"Cadencias automáticas"** de `KM_RUNBOOK.md`
   - Si usa una key: agregarla a la columna **"Lo consume"** de `SECRETS_INVENTORY.md`
   - Commit al repo (`sync-from-live.sh` + push)
   Antes de cambiar infra (binds, keys, rutas): revisar crontab + `hermes cron list`
   + esas dos tablas. *(Incidente: el cron de Hermes era invisible a los barridos.)*

5. **Multi-empresa desde el diseño.** Nada hardcodeado a una sola empresa: o se
   parametriza (`--company-id`, `case` por empresa) o se listan TODAS las empresas
   activas explícitamente. Aislamiento: una automatización de empresa no lee datos
   de otra. *(El monitor solo veía una empresa; los espejos colisionaban por nombre.)*

6. **Resiliencia estándar** (lo que ya cumple `weekly-ingest.sh`): lock contra
   ejecución concurrente, timeout por paso, ante fallo → log + notificar + continuar,
   y healthcheck de dependencias con reintento antes de reportar caído. Un monitor
   debe verificar con el endpoint CORRECTO antes de declarar "no responde".

7. **Notificar y monitorear por los canales existentes.** Salida humana → Telegram
   (patrón `telegram-notify.sh` o deliver de Hermes). Si es crítico que corra →
   push monitor (dead-man's-switch) en Kuma. No inventar canales nuevos.

8. **Todo en español, conciso, y los datos al knowledge por la vía correcta:**
   los outputs valiosos van a la wiki/deliverables/Borrador según el flujo
   (`WORKFLOWS.md` del bootstrap) — nunca escribir directo al knowledge curado.

## Checklist de alta (copiar al crear)

```
[ ] ¿Keys fuera del prompt/código, referenciadas desde .env con ruta absoluta?
[ ] ¿Rutas absolutas en todo? ¿Binario de hermes con ruta completa?
[ ] ¿Endpoints verificados contra SERVICIOS.md (no localhost asumido)?
[ ] ¿Contempla todas las empresas o está parametrizado?
[ ] ¿Lock/timeout/continuar-ante-fallo si es recurrente?
[ ] ¿Registrado en KM_RUNBOOK (cadencias) y SECRETS_INVENTORY (si usa key)?
[ ] ¿Notifica por Telegram / push monitor si corresponde?
[ ] ¿Probado una vez manualmente antes de dejarlo en cadencia?
```
