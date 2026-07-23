# Observabilidad — contrato de status JSON

Los scripts operativos del lab publican su estado en archivos JSON bajo
`~/ai-lab/ops-local/status/`. Ese directorio es la **interfaz estable** que
las personalizaciones de cada instancia (dashboards tipo Glance, widgets,
guards locales, notificadores) consumen para saber si el core esta sano,
sin acoplarse a los logs ni a los scripts internos.

Regla: los scripts del core **escriben**; las personalizaciones **solo leen**.
Cambiar el formato o la ruta de estos archivos es un cambio de contrato y debe
documentarse aca.

## Los tres archivos

| Archivo | Quien lo escribe | Cadencia de escritura | Frescura esperada (umbral de alarma) |
|---|---|---|---|
| `status/health.json` | `lab-health-check.sh` (DAG `health-check`) | Cada corrida del health check (~minutos/horas) | **24 h** — mas viejo que eso = el health check dejo de correr |
| `status/watchdog.json` | `paperclip-watchdog.sh` (DAG `paperclip-watchdog`) | Cada corrida del watchdog (~minutos) | **24 h** — mas viejo que eso = el watchdog dejo de correr |
| `status/maintenance.json` | `maintenance-check.sh` (DAG `maintenance-check`) | **SEMANAL** | **192 h (8 dias)** — es normal que tenga hasta una semana |

**IMPORTANTE — frescura POR ARCHIVO, no un umbral global.** `maintenance.json`
se regenera una vez por semana: un consumidor que exija frescura de 3 dias
(72 h) sobre los tres archivos por igual genera **falsas alarmas** cada semana
sobre maintenance. Usar 24 h para health/watchdog y 192 h para maintenance.

## Esquema de cada archivo

Todos comparten el campo `timestamp` (ISO 8601 con zona horaria), que es lo
que los consumidores deben usar para evaluar frescura.

### health.json — salud de contenedores y redes

Escrito por `lab-health-check.sh` al final de cada corrida.

```json
{
  "timestamp": "2026-01-01T02:00:00-06:00",
  "checks": [
    { "type": "container", "name": "mem0", "status": "running", "action": null },
    { "type": "network", "name": "mem0:mem0_default", "status": "connected", "action": null },
    { "type": "endpoint", "name": "mem0", "status": "ok", "action": null }
  ]
}
```

- `type`: `container` | `network` | `endpoint`
- `status`: estado observado (`running`, `connected`, `ok`, ...)
- `action`: `null` si no hubo que intervenir; si no, la accion correctiva
  que el script ejecuto (reinicio, reconexion de red, etc.)

### watchdog.json — watchdog de Paperclip

Escrito por `paperclip-watchdog.sh` en cada corrida.

```json
{
  "timestamp": "2026-01-01T02:00:01-06:00",
  "zombies_killed": 0,
  "memory_pressure": false,
  "oom_action": false,
  "memory_pct": 39
}
```

### maintenance.json — chequeo semanal de mantenimiento

Escrito por `maintenance-check.sh` (una vez por semana).

```json
{
  "timestamp": "2026-01-01T01:58:17-06:00",
  "updates_available": [
    {
      "tool": "ejemplo-tool",
      "installed": "1.0.0",
      "available": "1.1.0",
      "update_pending": true,
      "days_since_release": 5,
      "stable": true
    }
  ]
}
```

## Como consumir (patron recomendado)

```bash
STATUS_DIR="$HOME/ai-lab/ops-local/status"

# Frescura por archivo — umbrales distintos:
fresh() {  # $1=archivo  $2=umbral en horas
  local f="$STATUS_DIR/$1" max_s=$(( $2 * 3600 ))
  [ -f "$f" ] || return 1
  local age=$(( $(date +%s) - $(stat -c %Y "$f") ))
  [ "$age" -le "$max_s" ]
}

fresh health.json 24       || echo "GAP: health.json vencido"
fresh watchdog.json 24     || echo "GAP: watchdog.json vencido"
fresh maintenance.json 192 || echo "GAP: maintenance.json vencido"
```

## Notas

- `ops-local/` es territorio de la instancia (no del bootstrap): los scripts
  que escriben estos archivos pueden estar extendidos localmente, pero el
  contrato de rutas, nombres y umbrales de frescura es el de esta tabla.
- Si una instancia agrega archivos de status propios, van en el mismo
  directorio y deben declarar su cadencia aca o en la doc de la instancia.
- DAGs relacionados: `configs/dagu-dags/health-check.yaml`,
  `configs/dagu-dags/paperclip-watchdog.yaml`,
  `configs/dagu-dags/maintenance-check.yaml`.

## clawhip — monitoreo de sesiones tmux en tiempo real

Clawhip es un daemon Rust que complementa (no reemplaza) el DAG
`session-watchdog`. Mientras el watchdog corre periodicamente (DAG),
clawhip opera en continuo con latencia de ~15 segundos desde deteccion
hasta notificacion.

### Que monitorea

| Deteccion | Mecanismo | Relacion con session-watchdog |
|---|---|---|
| **Keywords** en output tmux | Substring match en ventana temporal (`keyword_window_secs=5`) | Equivale a deteccion de `Error`, `FAILED`, `fatal`, etc. |
| **Stale/idle** | Pane sin cambios por N minutos (`stale_minutes=15`) | Equivale a `WD_UMBRAL_BASH=900s` y `WD_UMBRAL_FIN` |
| **Espera-permiso** | NO cubierto | Requiere MoolMesh (session chain) |

### Pipeline

```
clawhip daemon (:25294)
  → localfile JSONL (~/ai-lab/logs/clawhip/events.jsonl)
    → clawhip-dispatch.sh (tail -F + jq)
      → telegram-notify.sh (push a Telegram)
```

### Relacion con MoolMesh

- **clawhip**: push en tiempo real — detecta keywords y stale, notifica
  inmediatamente via Telegram. Es el "sistema nervioso" de deteccion rapida.
- **MoolMesh**: archivo historico — registra todas las sesiones de agentes
  para consulta posterior, dashboards y chain analysis. Es la "memoria
  episodica" del laboratorio.

Ambos son complementarios: clawhip alerta, MoolMesh documenta.

### Configuracion

- Config: `~/.clawhip/config.toml`
- Service: `systemctl --user status clawhip clawhip-dispatch`
- Health: `curl -sf http://127.0.0.1:25294/health`
- Logs: `~/ai-lab/logs/clawhip/events.jsonl`
