# Hardening de Seguridad — Exposure Watchdog

**Parte del bootstrap.** Complementa a `scripts/security-apply-sudo.sh` monitoreando
que sus reglas se mantengan vigentes. Corre sin sudo cada 15 minutos vía Dagu.

## Qué monitorea

| Check | Qué detecta |
|---|---|
| Túneles no autorizados | `cloudflared`, `ngrok`, `frp`, `pagekite`, `localtunnel`, `serveo` |
| Firewall caído | UFW inactivo (las reglas de `security-apply-sudo.sh` pueden haberse perdido) |
| Fail2ban caído | Servicio fail2ban inactivo |
| Puertos nuevos | Cualquier puerto en `0.0.0.0` fuera del baseline |
| Docker expuesto | Contenedores con binds `0.0.0.0` (Docker puentea UFW) |

## Baseline de puertos

Definido por `scripts/security-apply-sudo.sh`:

| Puerto | Servicio | Acceso |
|---|---|---|
| 22 | SSH | Tailscale (100.64.0.0/10) + LAN (192.168.0.0/24) |
| 9119 | Hermes Dashboard | Tailscale |
| 22000 | Syncthing P2P | Tailscale + LAN |

Cualquier otro puerto en `0.0.0.0` dispara una alerta.

## Instalación

El watchdog se instala como parte de `setup-instance.sh`:

1. El script `exposure-watchdog.sh` se copia a `$LAB_DIR/scripts/`
2. El DAG `lab-exposure-watchdog.yaml` se copia a `~/.config/dagu/dags/`
3. Dagu lo ejecuta cada 15 minutos automáticamente

## Requisitos

- `$LAB_DIR` definido (default: `~/ai-lab`)
- `$LAB_DIR/scripts/telegram-notify.sh` (incluido en el bootstrap)
- UFW y fail2ban instalados y configurados (`security-apply-sudo.sh`)
- Dagu corriendo como servicio systemd

## Notificaciones

Las alertas se envían por Telegram usando `telegram-notify.sh`.
Solo se notifica cuando el conjunto de alertas **cambia** respecto a la ejecución anterior
(deduplicación por hash MD5), evitando spam.
