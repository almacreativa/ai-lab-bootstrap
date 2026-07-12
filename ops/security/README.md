# Hardening de Seguridad — Fase 1

**Fecha:** 2026-07-06
**Fase:** 1 — Línea base

## Cambios aplicados

### UFW (Firewall)
- Política: deny incoming, allow outgoing
- Reglas: solo Tailscale (tailscale0) y SSH (22/tcp)
- Archivo de referencia: `ufw-rules.txt`

### Fail2ban
- Jail activo: sshd
- Archivo de referencia: `fail2ban-status.txt`

### Exposure Watchdog
- Script: `exposure-watchdog.sh`
- Schedule: cada 15 minutos via crontab
- Monitorea: túneles no autorizados (cloudflared, ngrok, etc.), UFW/fail2ban vivos, puertos wildcard nuevos, contenedores Docker expuestos
- Baseline de puertos aprobados: 22, 631, 4321, 5200, 22000
- Requisitos: `hermes` CLI en `$PATH` para notificaciones Telegram

### Crontab
- `exposure-watchdog.sh` cada 15 min
- `sync-upstream.sh` diario 8am
- Archivo de referencia: `crontab.txt`

## Instalación

```bash
# 1. Copiar scripts
cp exposure-watchdog.sh ~/scripts/
chmod +x ~/scripts/exposure-watchdog.sh

# 2. Instalar crontab (ajustar paths)
crontab -l | { cat; cat crontab.txt; } | crontab -

# 3. Crear directorios
mkdir -p ~/logs ~/.local/state
```
