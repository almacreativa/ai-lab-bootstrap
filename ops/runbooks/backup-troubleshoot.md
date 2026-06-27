# Backup Troubleshooting

## B2 bandwidth cap (403 errors)

**Síntoma:** `restic backup` falla con `403 Forbidden` o `cap exceeded`.

**Causa:** Backblaze B2 tiene un cap diario de descarga gratuita (2.5 GB). Los uploads no tienen cap, pero los check/restore sí consumen bandwidth de descarga.

**Fix:**
- Para backups: no afecta (solo upload)
- Para restore: esperar 24h o pagar el excedente
- Para `restic check --read-data`: reducir el subset (`--read-data-subset=1%`)

## Wrong RESTIC_PASSWORD

**Síntoma:** `Fatal: wrong password or no key found`

**Causa:** La password no coincide con la que se usó para `restic init`.

**Fix:**
1. Verificar en `~/ai-lab/scripts/.env` que `RESTIC_PASSWORD` es correcto
2. Si se perdió: los backups son irrecuperables. Crear nuevo repo con `restic init`
3. Guardar siempre la password en un password manager

## sudo restic pierde env vars

**Síntoma:** `restic` con `sudo` no encuentra credenciales B2.

**Causa:** `sudo` limpia las variables de entorno por seguridad.

**Fix:** Usar `sudo -E` para preservar el environment:
```bash
sudo -E restic snapshots
```

O exportar explícitamente:
```bash
sudo RESTIC_REPOSITORY="$RESTIC_REPOSITORY" \
     B2_ACCOUNT_KEY="$B2_ACCOUNT_KEY" \
     RESTIC_PASSWORD="$RESTIC_PASSWORD" \
     restic snapshots
```

## S3 gateway vs native B2 backend

**Síntoma:** `restic init` o `restic backup` falla con errores de S3 endpoint.

**Causa:** Hay dos formas de conectar restic a B2:
- S3 gateway: `s3:s3.us-west-004.backblazeb2.com/bucket`
- B2 nativo: `b2:bucket`

**Fix:** Usar siempre el backend nativo `b2:`. Es más rápido y soporta todas las features de B2 (lifecycle rules, object lock).

```bash
export RESTIC_REPOSITORY="b2:mi-bucket"
# NO: export RESTIC_REPOSITORY="s3:s3.us-west-004.backblazeb2.com/mi-bucket"
```

## Uptime Kuma heartbeat timing

**Síntoma:** Uptime Kuma marca el backup como "down" aunque completó.

**Causa:** El heartbeat interval en Uptime Kuma es más corto que el tiempo del backup. Si el backup tarda 20 min y el heartbeat espera 15 min, se marca como fallo.

**Fix:**
1. En Uptime Kuma: configurar heartbeat interval >= 2x el tiempo esperado del backup
2. Recomendado: 3600s (1 hora) para backups diarios
3. El push se envía DESPUÉS de que el backup completa (no antes)

## restic check es lento

**Síntoma:** `restic check --read-data` tarda horas.

**Causa:** Descarga y verifica todos los packs del repo. Con repos grandes, puede ser GB de descarga.

**Fix:** Usar subset:
```bash
restic check --read-data-subset=5%
```

Verifica un 5% aleatorio. En un año de backups diarios, cada pack se verifica estadísticamente ~18 veces.

## Backup corre como Dagu pero falla

**Síntoma:** `lab-backup.sh` funciona manual pero falla en Dagu.

**Causa:** Dagu no carga `~/.bashrc` ni `~/.profile` → `restic`, `sqlite3`, etc. no están en PATH.

**Fix:** El script ya incluye `export PATH="$HOME/.local/bin:$PATH"` al inicio. Si aún falla, verificar que el binario está en `~/.local/bin/`:
```bash
which restic
ls -la ~/.local/bin/restic
```
