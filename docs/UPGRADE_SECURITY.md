# Guía de upgrade — Seguridad para instancias existentes

Esta guía es para quien **ya tiene el lab instalado** y hace `git pull` del
bootstrap para incorporar el modelo de seguridad de 3 capas.

**Para instalaciones nuevas**, seguir `docs/POST-BOOTSTRAP.md` (Fase 3).

---

## Modelo de 3 capas

```
INTERNET
  └─ CAPA 1: Tailscale VPN (perímetro primario)
       └─ CAPA 2: UFW per-port desde manifiesto (segunda barrera)
            └─ CAPA 3: fail2ban SSH (tercera barrera)

DOCKER (independiente):
  UFW NO protege Docker — la protección es el bind address en el compose
  Patrón: 127.0.0.1:PORT + ${TAILSCALE_IP}:PORT, nunca 0.0.0.0
```

---

## Paso 1 — Actualizar el bootstrap

```bash
cd ~/ai-lab/repos/ai-lab-bootstrap
git pull origin main
```

Esto trae los scripts de seguridad actualizados:
- `ops/manifests/generate-core-manifest.sh` — genera `network{}` y `security{}`
- `scripts/security-apply-sudo.sh` — aplica UFW + fail2ban desde el manifiesto
- `scripts/exposure-watchdog.sh` — verifica binds Docker

## Paso 2 — Variables de red en scripts/.env

Agregar las variables de red al archivo de secrets del lab:

```bash
# Obtener valores:
tailscale ip -4                    # → TAILSCALE_IP
ip -o link show | grep tailscale   # → TAILSCALE_IFACE
ip route | grep "src"              # → LAN_SUBNET (la red local)

# Editar ~/ai-lab/scripts/.env y agregar:
# TAILSCALE_IP=100.125.x.x
# TAILSCALE_IFACE=tailscale0
# LAN_SUBNET=192.168.x.0/24
```

Verificar:

```bash
grep -E "TAILSCALE_IP|TAILSCALE_IFACE|LAN_SUBNET" ~/ai-lab/scripts/.env
```

## Paso 3 — Variables en los stacks Docker

Cada stack que usa binds parametrizados necesita `TAILSCALE_IP` en su `.env`.

Stacks que requieren la variable:

| Stack | Archivo .env |
|-------|-------------|
| paperclip | `~/ai-lab/stacks/paperclip/.env` |
| odysseus | `~/ai-lab/stacks/odysseus/.env` |
| uptime-kuma | `~/ai-lab/stacks/uptime-kuma/.env` |
| portainer | `~/ai-lab/stacks/portainer/.env` |

Para cada uno:

```bash
# Agregar al .env del stack:
# TAILSCALE_IP=100.125.x.x   ← la misma IP del paso 2
```

**Verificar que los compose files usan `${TAILSCALE_IP}`** y no IPs literales:

```bash
for stack in paperclip odysseus uptime-kuma portainer; do
  echo "=== $stack ==="
  grep -n "ports:" -A5 ~/ai-lab/stacks/$stack/docker-compose.yml
done
```

Si algún compose tiene una IP literal (ej: `100.125.155.102:3100:3100`),
reemplazar por `${TAILSCALE_IP}:3100:3100` para que sea portable entre
instancias y redes.

Después de cambiar las variables, recrear los containers:

```bash
for stack in paperclip odysseus uptime-kuma portainer; do
  cd ~/ai-lab/stacks/$stack && docker compose up -d
done
```

## Paso 4 — Regenerar el manifiesto

```bash
bash ~/ai-lab/ops/manifests/generate-core-manifest.sh

# Verificar las secciones nuevas:
grep -A5 "network:" ~/ai-lab/ops/core-manifest.yaml
grep -A10 "security:" ~/ai-lab/ops/core-manifest.yaml
```

## Paso 5 — Aplicar seguridad

```bash
sudo bash ~/ai-lab/scripts/security-apply-sudo.sh
```

Este script:
- Genera 10+ reglas UFW per-port desde el manifiesto (no per-interface)
- Elimina la regla vieja `allow in on tailscale0` si existe
- Instala fail2ban con jail SSH (maxretry=5, bantime=3600, findtime=600)

## Paso 6 — Verificar

```bash
# UFW — reglas per-port, NO "allow in on tailscale0":
sudo ufw status numbered

# fail2ban — jail SSH activa:
sudo fail2ban-client status sshd

# Docker — ningún container en 0.0.0.0:
bash ~/ai-lab/scripts/exposure-watchdog.sh
```

## Paso 7 — Verificar binds en compose files

```bash
# Confirmar que ningún compose usa IPs literales:
grep -rn "[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+:" ~/ai-lab/stacks/*/docker-compose.yml \
  | grep -v "127.0.0.1" | grep "ports" -A2

# Confirmar que todos usan ${TAILSCALE_IP}:
grep -rn "TAILSCALE_IP" ~/ai-lab/stacks/*/docker-compose.yml
```

---

## Resumen de archivos modificados

| Archivo | Cambio |
|---------|--------|
| `~/ai-lab/scripts/.env` | +TAILSCALE_IP, TAILSCALE_IFACE, LAN_SUBNET |
| `~/ai-lab/stacks/<stack>/.env` | +TAILSCALE_IP (4 stacks) |
| `~/ai-lab/stacks/<stack>/docker-compose.yml` | IP literal → `${TAILSCALE_IP}` si aplica |
| `~/ai-lab/ops/core-manifest.yaml` | regenerado (network{} + security{}) |

---

## Troubleshooting

### Me quedé sin acceso SSH después de aplicar UFW

UFW permite SSH por defecto desde la LAN. Si la LAN_SUBNET es incorrecta,
puede bloquear el acceso. Desde la consola del servidor:

```bash
sudo ufw status numbered
sudo ufw delete <numero-de-regla>  # eliminar regla incorrecta
sudo ufw allow from <LAN_SUBNET_correcta> to any port 22
```

### fail2ban me bloqueó

```bash
sudo fail2ban-client set sshd unbanip <tu-ip>
```

### Un contenedor sigue en 0.0.0.0

```bash
# Ver cuál:
bash ~/ai-lab/scripts/exposure-watchdog.sh

# Corregir el compose, luego:
cd ~/ai-lab/stacks/<stack> && docker compose up -d
```

---

## Referencias

- `docs/SECURITY_GUIDE.md` — detalle del modelo de 3 capas
- `docs/POST-BOOTSTRAP.md` — Fase 3 para instalaciones nuevas
- `ops/guards/core-guard.sh` — verifica estado esperado del lab
