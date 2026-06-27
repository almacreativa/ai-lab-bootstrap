# APT Sources — Restaurar repos de terceros

## El problema

`dpkg --set-selections` seguido de `apt-get dselect-upgrade` falla para paquetes de repositorios de terceros si esos repos no están configurados.

Paquetes afectados típicos:
- `docker-ce`, `docker-ce-cli`, `containerd.io` (repo Docker)
- `gh` (repo GitHub CLI)
- `tailscale` (repo Tailscale)
- `syncthing` (repo Syncthing)

**Síntoma:**
```
E: Unable to locate package docker-ce
E: Package 'gh' has no installation candidate
```

## Qué incluir en el backup

El script `lab-backup.sh` ya captura:

1. **`/etc/apt/sources.list.d/`** — archivos .list y .sources con las URLs de los repos
2. **`/etc/apt/keyrings/`** — claves GPG para verificar los repos

Ambos son necesarios. Sin la keyring, `apt update` rechaza el repo por firma no verificada.

## Procedimiento de restore

```bash
# 1. Copiar sources
sudo cp -r ~/restore-test/tmp/lab-backup-dumps/apt-sources.list.d/* /etc/apt/sources.list.d/

# 2. Copiar keyrings
sudo mkdir -p /etc/apt/keyrings
sudo cp -r ~/restore-test/tmp/lab-backup-dumps/apt-keyrings/* /etc/apt/keyrings/

# 3. Actualizar índices
sudo apt update

# 4. Ahora sí instalar paquetes
sudo dpkg --set-selections < ~/restore-test/tmp/lab-backup-dumps/apt-packages.selections
sudo apt-get dselect-upgrade -y
```

## Verificar que los sources fueron restaurados

```bash
ls /etc/apt/sources.list.d/
apt-cache policy docker-ce
apt-cache policy gh
```

Si `apt-cache policy` muestra `N/A` o no muestra candidatos, el source no fue restaurado correctamente.
