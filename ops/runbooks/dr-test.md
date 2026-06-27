# DR Test — Procedimiento de Disaster Recovery

## Prerrequisitos

- Servidor limpio con Ubuntu 24.04+ (o la misma distribución)
- Docker instalado
- restic instalado (`sudo apt install restic`)
- Credenciales de B2 (B2_ACCOUNT_ID, B2_BACKUP_KEY, RESTIC_PASSWORD)
- Acceso a Tailscale (para servicios que bindean a IP de tailnet)

## Paso 1: Acceder al repo restic

```bash
export RESTIC_REPOSITORY="b2:lab-backpus"
export B2_ACCOUNT_ID="..."
export B2_ACCOUNT_KEY="..."
export RESTIC_PASSWORD="..."

restic snapshots --compact
```

## Paso 2: Restaurar a directorio temporal

```bash
mkdir -p ~/restore-test
restic restore latest --target ~/restore-test
```

O usar el script asistido:
```bash
~/ai-lab/ops/backup/dr-restore.sh ~/restore-test
```

## Paso 3: Restaurar APT sources (ANTES de instalar paquetes)

```bash
sudo cp -r ~/restore-test/tmp/lab-backup-dumps/apt-sources.list.d/* /etc/apt/sources.list.d/
sudo cp -r ~/restore-test/tmp/lab-backup-dumps/apt-keyrings/* /etc/apt/keyrings/ 2>/dev/null
sudo apt update
```

Sin este paso, `dpkg --set-selections` falla para paquetes de repos de terceros (docker-ce, gh, tailscale, syncthing).

## Paso 4: Restaurar paquetes apt

```bash
sudo dpkg --set-selections < ~/restore-test/tmp/lab-backup-dumps/apt-packages.selections
sudo apt-get dselect-upgrade -y
```

## Paso 5: Crear Docker networks

```bash
while read -r net; do
  docker network create "$net" 2>/dev/null || echo "Network $net ya existe"
done < ~/restore-test/tmp/lab-backup-dumps/docker-networks.txt
```

Las networks deben existir ANTES de levantar los stacks con docker compose.

## Paso 6: Restaurar archivos del lab

```bash
# Copiar ~/ai-lab/
cp -r ~/restore-test/home/*/ai-lab/ ~/ai-lab/

# Copiar configs
cp -r ~/restore-test/home/*/.config/systemd/user/* ~/.config/systemd/user/
cp -r ~/restore-test/home/*/.config/dagu/dags/* ~/.config/dagu/dags/
cp ~/restore-test/home/*/.gitconfig ~/.gitconfig

# Copiar binarios
cp ~/restore-test/home/*/.local/bin/* ~/.local/bin/

# Copiar Hermes
cp -r ~/restore-test/home/*/.hermes/ ~/.hermes/

# Copiar SSH keys
cp -r ~/restore-test/home/*/.ssh/ ~/.ssh/
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_* 2>/dev/null
```

## Paso 7: Restaurar PostgreSQL dumps

```bash
# Levantar containers de DB primero
cd ~/ai-lab/stacks/paperclip && docker compose up -d db
cd ~/ai-lab/stacks/outline && docker compose up -d outline-postgres

# Esperar a que estén listos
sleep 5

# Restaurar (sin -t en docker exec)
docker exec -i paperclip-db-1 psql -U paperclip < ~/restore-test/tmp/lab-backup-dumps/paperclip-db-1.sql
docker exec -i outline-postgres psql -U outline < ~/restore-test/tmp/lab-backup-dumps/outline-postgres.sql
```

## Paso 8: Rehome (solo si se restaura en OTRA máquina)

Si la IP de Tailscale o el hostname cambiaron, correr `rehome.sh` para adaptar
todas las configs automáticamente:

```bash
# Dry-run primero (muestra qué cambiaría sin tocar nada):
bash ~/ai-lab/ops/backup/rehome.sh --dry-run

# Aplicar:
bash ~/ai-lab/ops/backup/rehome.sh
```

El script auto-detecta la IP/hostname originales del manifest restaurado y
reemplaza en: Glance, Dagu, Paperclip .env, docker-compose de stacks,
y regenera CLAUDE.md + core-manifest.yaml.

Si no hay manifest (restore parcial), especificar manualmente:
```bash
bash ~/ai-lab/ops/backup/rehome.sh --old-ip 100.79.30.67 --old-hostname i7local
```

## Paso 9: Levantar stacks

```bash
for stack in ~/ai-lab/stacks/*/; do
  [ -f "$stack/docker-compose.yml" ] || [ -f "$stack/compose.yaml" ] || continue
  echo "Levantando $(basename $stack)..."
  cd "$stack" && docker compose up -d
done
```

## Paso 10: Restaurar servicios systemd

```bash
systemctl --user daemon-reload
systemctl --user enable --now dagu hermes moolmesh centro-de-comando
```

## Paso 11: Verificar

```bash
# Generar manifest y correr guards
~/ai-lab/ops/manifests/generate-core-manifest.sh
~/ai-lab/ops/guards/core-guard.sh
~/ai-lab/ops/guards/bootstrap-guard.sh
```

## Checklist de verificación

- [ ] Todos los containers corriendo (`docker ps`)
- [ ] Servicios systemd activos (`systemctl --user list-units`)
- [ ] Dagu accesible (`:8480`)
- [ ] Telegram notificaciones funcionando
- [ ] Backup funciona (correr `lab-backup.sh`)
- [ ] Core guard reporta 0 GAPs

## Errores conocidos

| Error | Causa | Fix |
|---|---|---|
| `dpkg: package X not available` | APT source no restaurado | Restaurar `/etc/apt/sources.list.d/` primero |
| `docker network not found` | Network no creada | Crear networks antes de `docker compose up` |
| SQL dump con `\r` | Generado con `docker exec -t` | Nunca usar `-t` en scripts |
| `compose.yaml not found` | Archivo se llama `docker-compose.yml` | Verificar nombre exacto en cada stack |
