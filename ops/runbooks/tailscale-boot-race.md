# Tailscale Boot Race Condition

## El problema

Servicios que bindean a la IP de Tailscale (100.x.x.x) fallan al boot si Tailscale no está listo.

**Servicios afectados:**
- Dagu (si configurado con `--host 100.x.x.x`)
- Uptime Kuma (si configurado con bind a IP específica)
- Cualquier servicio con bind explícito a IP de tailnet

**Síntoma:**
```
Error: listen tcp 100.x.x.x:8480: bind: cannot assign requested address
```

## Solución 1: Bindear a 0.0.0.0 + UFW

La solución más robusta. El servicio escucha en todas las interfaces y UFW restringe el acceso.

```bash
# Servicio bindea a 0.0.0.0
ExecStart=/home/user/.local/bin/dagu start-all --host 0.0.0.0 --port 8480

# UFW permite solo desde tailnet
sudo ufw allow from 100.64.0.0/10 to any port 8480
sudo ufw deny 8480
```

## Solución 2: ExecStartPre wait loop

Para servicios que DEBEN bindear a la IP de Tailscale:

```ini
[Service]
ExecStartPre=/bin/bash -c 'for i in $(seq 1 30); do ip addr show tailscale0 2>/dev/null | grep -q "inet " && exit 0; sleep 2; done; exit 1'
ExecStart=...
```

Espera hasta 60 segundos a que la interfaz tailscale0 tenga IP.

## Solución 3: After=tailscaled.service

Menos confiable — `tailscaled.service` puede estar "active" antes de que la interfaz tenga IP asignada.

```ini
[Unit]
After=network.target tailscaled.service
Wants=tailscaled.service
```

Funciona en la mayoría de los casos pero no garantiza que la IP esté asignada.

## Solución 4: lab-post-reboot.service (implementada)

Servicio systemd user que espera a Tailscale y luego corre `post-reboot-check.sh` para
detectar y recuperar contenedores Docker que arrancaron sin port bindings.

```ini
[Unit]
Description=Post-reboot recovery — espera Tailscale y recupera servicios

[Service]
Type=oneshot
ExecStartPre=/bin/bash -c 'for i in $(seq 1 45); do ip addr show tailscale0 2>/dev/null | grep -q "inet " && exit 0; sleep 2; done; exit 1'
ExecStart=/home/user/ai-lab/scripts/post-reboot-check.sh
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

`post-reboot-check.sh` detecta el caso específico: contenedor "running" pero con
`NetworkSettings.Ports == {}` (Docker subió el contenedor antes de que la IP existiera).
Lo recrea con `docker compose down/up` para que bindee correctamente.

**Contenedores afectados** (bindean a IP Tailscale en compose):
- Portainer (`IP:9443:9443`)
- Uptime Kuma (`IP:3001:3001`)

Habilitar:
```bash
systemctl --user enable lab-post-reboot.service
```

## Diagnóstico

```bash
# Verificar si tailscale tiene IP
tailscale ip -4

# Verificar estado de la interfaz
ip addr show tailscale0

# Ver logs de un servicio que falló
journalctl --user -u dagu.service --since "1 hour ago"

# Ver si un contenedor tiene puertos bindeados
docker inspect portainer --format '{{json .NetworkSettings.Ports}}'
# {} = sin puertos (race condition), non-empty = OK

# Ver log del servicio post-reboot
journalctl --user -u lab-post-reboot.service
```
