# Migración de lab entre servidores

Procedimiento para migrar un lab completo de un servidor (origen) a otro (destino),
sin reinstalar el sistema operativo en ninguno de los dos.

## Prerrequisitos

| | Origen | Destino |
|---|---|---|
| OS | Ubuntu 24.04+ | Ubuntu 24.04+ |
| Tailscale | activo | activo |
| Docker | instalado | instalado |
| restic | instalado | instalado |
| Usuario | mismo username | mismo username |
| Backup B2 | configurado y funcional | acceso a las mismas credenciales B2 |

## Fase 1 — Backup fresco del origen (5-15 min)

En el servidor **origen**:

```bash
# 1. Backup completo a B2
~/ai-lab/ops/backup/lab-backup.sh

# 2. Verificar que completó (último snapshot)
source ~/ai-lab/scripts/.env
export RESTIC_REPOSITORY B2_ACCOUNT_ID RESTIC_PASSWORD
export B2_ACCOUNT_KEY="$B2_BACKUP_KEY"
restic snapshots --compact --last 1
```

Anotar el snapshot ID y la fecha para confirmar que es fresco.

## Fase 2 — Preparar destino (10 min)

Si el destino tiene una instalación previa del lab (ej: un DR test anterior),
limpiarla primero:

```bash
# 2.1 Parar todo lo que esté corriendo
systemctl --user stop dagu moolmesh centro-de-comando hermes 2>/dev/null
for stack in ~/ai-lab/stacks/*/; do
  [ -f "$stack/docker-compose.yml" ] || continue
  cd "$stack" && docker compose down 2>/dev/null
done

# 2.2 Limpiar Docker (images, volumes huérfanos, networks)
docker system prune -af --volumes 2>/dev/null

# 2.3 Borrar lab anterior
rm -rf ~/ai-lab
rm -rf ~/restore-test

# 2.4 Limpiar configs de sesión anterior
rm -rf ~/.config/systemd/user/dagu.service
rm -rf ~/.config/systemd/user/moolmesh.service
rm -rf ~/.config/systemd/user/centro-de-comando.service
rm -rf ~/.config/systemd/user/hermes.service
rm -rf ~/.config/dagu
rm -rf ~/.hermes
```

## Fase 3 — Bootstrap base en destino (15-20 min)

```bash
# 3.1 Clonar bootstrap
cd ~ && git clone https://github.com/almacreativa/ai-lab-bootstrap.git

# 3.2 Correr bootstrap (instala dependencias base)
cd ai-lab-bootstrap && bash bootstrap.sh

# 3.3 Configurar instancia (crea estructura, genera stacks de infra)
bash setup-instance.sh
```

Esto crea la estructura `~/ai-lab/` con ops/, stacks/, scripts/, etc.

## Fase 4 — Restaurar backup (10-30 min según tamaño)

```bash
# 4.1 Configurar credenciales de B2 (si no las tiene del bootstrap)
# Copiar el .env del origen o crearlas manualmente:
cat >> ~/ai-lab/scripts/.env << 'ENVEOF'
RESTIC_REPOSITORY=b2:<nombre-bucket>
B2_ACCOUNT_ID=<account-id>
B2_BACKUP_KEY=<backup-key>
RESTIC_PASSWORD=<password>
ENVEOF
chmod 600 ~/ai-lab/scripts/.env

# 4.2 Restaurar
bash ~/ai-lab/ops/backup/dr-restore.sh ~/restore-test
# Seleccionar el snapshot fresco de Fase 1
```

## Fase 5 — Copiar archivos restaurados (5 min)

```bash
# 5.1 Copiar lab (sobreescribe lo que generó setup-instance.sh)
cp -r ~/restore-test/home/*/ai-lab/* ~/ai-lab/

# 5.2 Copiar configs de usuario
cp -r ~/restore-test/home/*/.config/systemd/user/* ~/.config/systemd/user/ 2>/dev/null
mkdir -p ~/.config/dagu
cp -r ~/restore-test/home/*/.config/dagu/* ~/.config/dagu/ 2>/dev/null
cp ~/restore-test/home/*/.gitconfig ~/.gitconfig 2>/dev/null

# 5.3 Copiar Hermes
cp -r ~/restore-test/home/*/.hermes/ ~/.hermes/ 2>/dev/null

# 5.4 Copiar binarios locales (engram, etc.)
cp ~/restore-test/home/*/.local/bin/* ~/.local/bin/ 2>/dev/null

# 5.5 SSH keys (si quieres mantener las mismas)
cp -r ~/restore-test/home/*/.ssh/ ~/.ssh/ 2>/dev/null
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_* 2>/dev/null
```

## Fase 6 — Rehome (5 min)

Adaptar todas las configs a la nueva IP de Tailscale y hostname:

```bash
# 6.1 Dry-run primero
bash ~/ai-lab/ops/backup/rehome.sh --dry-run

# 6.2 Revisar los cambios propuestos y aplicar
bash ~/ai-lab/ops/backup/rehome.sh
```

El script reemplaza automáticamente:
- IP de Tailscale vieja → nueva
- Hostname viejo → nuevo
- Home path viejo → nuevo (si difiere)
- Regenera CLAUDE.md y core-manifest.yaml

## Fase 7 — Docker networks + stacks (10-15 min)

```bash
# 7.1 Crear networks
if [ -f ~/restore-test/tmp/lab-backup-dumps/docker-networks.txt ]; then
  while read -r net; do
    docker network create "$net" 2>/dev/null && echo "✓ $net" || echo "· $net ya existe"
  done < ~/restore-test/tmp/lab-backup-dumps/docker-networks.txt
fi

# 7.2 Levantar stacks (los que necesitan build tardan más)
for stack in ~/ai-lab/stacks/*/; do
  [ -f "$stack/docker-compose.yml" ] || continue
  STACK_NAME=$(basename "$stack")
  echo "── Levantando $STACK_NAME..."
  cd "$stack" && docker compose up -d --build 2>&1 | tail -3
done
```

## Fase 8 — Restaurar PostgreSQL (5 min)

```bash
DUMP_DIR=~/restore-test/tmp/lab-backup-dumps

# 8.1 Esperar a que los containers de DB estén healthy
sleep 10

# 8.2 Restaurar cada dump
for sql in "$DUMP_DIR"/*.sql; do
  [ -f "$sql" ] || continue
  DB_NAME=$(basename "$sql" .sql)
  echo "── Restaurando $DB_NAME..."

  # Detectar container de DB
  case "$DB_NAME" in
    paperclip*) CTR="paperclip-db-1" ; DB_USER="paperclip" ;;
    outline*)   CTR="outline-postgres" ; DB_USER="outline" ;;
    *)          echo "   ⚠ dump no reconocido: $DB_NAME — restaurar manualmente" ; continue ;;
  esac

  docker exec -i "$CTR" psql -U "$DB_USER" < "$sql" 2>&1 | tail -1
done
```

## Fase 9 — Servicios systemd (2 min)

```bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

systemctl --user daemon-reload

for svc in dagu moolmesh centro-de-comando; do
  systemctl --user enable "$svc.service" 2>/dev/null
  systemctl --user start "$svc.service" 2>/dev/null && echo "✓ $svc" || echo "✗ $svc"
done

# Hermes (puede ser systemd user o system, verificar)
systemctl --user start hermes 2>/dev/null || sudo systemctl start hermes 2>/dev/null
```

## Fase 10 — Secrets y tokens (5 min)

Revisar y actualizar secrets que contengan la IP vieja:

```bash
# 10.1 Buscar referencias a la IP vieja en secrets
OLD_IP=$(grep tailscale_ip ~/ai-lab/ops/core-manifest.yaml 2>/dev/null | awk '{print $2}')
grep -r "$OLD_IP" ~/ai-lab/scripts/.env ~/.hermes/.env 2>/dev/null

# 10.2 Push URLs de Uptime Kuma (apuntan a la IP vieja)
# Editar ~/ai-lab/scripts/.env y reemplazar IP en:
#   CENTRO_KUMA_PUSH_URL
#   CPU_TEMP_KUMA_PUSH_URL
#   BACKUP_KUMA_PUSH_URL
# NOTA: los push tokens también cambian si es una instancia nueva de Kuma

# 10.3 Telegram bot token — es el MISMO (no cambia por servidor)
# Pero verificar que solo UN servidor esté enviando notificaciones
```

## Fase 11 — Verificar (5 min)

```bash
# 11.1 Regenerar manifest
~/ai-lab/ops/manifests/generate-core-manifest.sh

# 11.2 Guards
~/ai-lab/ops/guards/core-guard.sh
~/ai-lab/ops/guards/bootstrap-guard.sh

# 11.3 Docker
docker ps --format "table {{.Names}}\t{{.Status}}" | sort

# 11.4 Test de backup
~/ai-lab/ops/backup/lab-backup.sh
```

### Checklist

- [ ] Guards: 0 GAPs
- [ ] Todos los containers corriendo
- [ ] Servicios systemd activos
- [ ] Dagu UI accesible (`:8480`)
- [ ] Paperclip UI accesible (`:3100`)
- [ ] Uptime Kuma verde (`:3001`)
- [ ] Telegram: notificación de prueba recibida
- [ ] Backup completado sin error
- [ ] Glance muestra métricas correctas

## Fase 12 — Cutover: apagar origen

Una vez verificado todo en el destino:

```bash
# En el ORIGEN — parar servicios para evitar alertas duplicadas
systemctl --user stop dagu moolmesh centro-de-comando hermes 2>/dev/null
sudo systemctl stop hermes 2>/dev/null
for stack in ~/ai-lab/stacks/*/; do
  [ -f "$stack/docker-compose.yml" ] || continue
  cd "$stack" && docker compose down 2>/dev/null
done
```

## Fase 13 — Limpiar origen como sandbox (opcional)

Si el servidor origen se reutiliza como sandbox/test:

```bash
# Ver: ops/runbooks/lab-cleanup.md
bash ~/ai-lab/repos/ai-lab-bootstrap/ops/lab-cleanup.sh
```

Esto deja el servidor con: Ubuntu + Tailscale + SSH + usuario.
Sin Docker containers, sin lab, sin crons, sin servicios.

## Tiempo estimado total

| Fase | Tiempo |
|------|--------|
| Backup fresco | 5-15 min |
| Preparar destino | 10 min |
| Bootstrap | 15-20 min |
| Restore + copiar | 15-35 min |
| Rehome + stacks | 15-20 min |
| DBs + servicios + secrets | 10 min |
| Verificación | 5 min |
| **Total** | **~75-115 min** |

## Errores conocidos

| Error | Causa | Fix |
|---|---|---|
| `Network X not found` | Network no creada antes de compose up | Crear networks (Fase 7.1) |
| Kuma monitors DOWN | Push URLs apuntan a IP/tokens viejos | Reconfigurar en Kuma UI |
| Telegram duplicado | Ambos servidores enviando | Parar servicios en origen primero |
| `permission denied` en data/core/ | Archivos root-owned del restore | `sudo chown -R $USER:$USER ~/ai-lab/data/` |
| rehome no detecta IP vieja | Manifest no restaurado aún | Usar `--old-ip` manualmente |
