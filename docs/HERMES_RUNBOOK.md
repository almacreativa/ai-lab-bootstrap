# Hermes Agent — Runbook bare metal (desde v1.1.0)

**Actualizado:** 2026-05-24
**Estado:** Corriendo como servicio systemd en el host

---

## Cómo saber si Hermes está corriendo correctamente

### Método rápido
```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:9119
# → HTTP 200 = OK | HTTP 000 = no responde
```

### Estado detallado
```bash
sudo systemctl status hermes
```
Buscá `Active: active (running)` en verde.

### Ver desde qué runtime está corriendo
```bash
cat ~/.hermes/gateway_state.json
```
Si ves `"argv": ["$HOME/.hermes-env/bin/hermes", ...]` → **bare metal**
Si ves `"argv": ["/opt/hermes/.venv/bin/hermes", ...]` → **Docker** (no debería pasar)

También con `hermes --version`:
```bash
~/.hermes-env/bin/hermes --version
```

---

## Cómo hablar con Hermes desde la terminal del servidor

### Sesión de chat directa (sin Docker, sin Telegram)
```bash
~/.hermes-env/bin/hermes chat
```
Abre una sesión interactiva. Ctrl+C para salir.

### Pregunta rápida (sin sesión interactiva)
```bash
~/.hermes-env/bin/hermes chat -q "tu pregunta acá"
```

### Retomar la última sesión
```bash
~/.hermes-env/bin/hermes chat --resume
```

### Ver historial de sesiones
```bash
~/.hermes-env/bin/hermes sessions
```

> **Tip:** Podés agregar un alias en `~/.bashrc`:
> ```bash
> alias hermes='~/.hermes-env/bin/hermes'
> ```

---

## Operaciones del día a día

### Reiniciar el servicio (después de cambiar config.yaml o .env)
```bash
sudo systemctl restart hermes
```

### Ver logs en tiempo real
```bash
journalctl -u hermes -f
```

### Ver últimas 50 líneas de log
```bash
journalctl -u hermes -n 50 --no-pager
```

### Estado de las plataformas (Telegram, Discord, etc.)
```bash
python3 -c "
import json
d = json.load(open('$HOME/.hermes/gateway_state.json'))
print(f'Gateway: {d[\"gateway_state\"]}')
for p, v in d['platforms'].items():
    print(f'  {p}: {v[\"state\"]}')
"
```

---

## Estructura del setup bare metal

```
~/.hermes-env/              ← venv Python con hermes-agent instalado
    bin/hermes              ← el binario que usás desde la terminal

/usr/local/bin/hermes-start.sh   ← launcher del servicio systemd
/etc/systemd/system/hermes.service  ← unidad systemd

~/.hermes/                  ← estado del agente (NO tocar)
    .env                    ← API keys (permisos 600)
    config.yaml             ← configuración del agente
    SOUL.md                 ← personalidad
    memories/               ← memoria persistente
    sessions/               ← historial de sesiones
    skills/                 ← habilidades aprendidas
    workspace/              ← directorio de trabajo del agente
```

---

## Rollback a Docker (si algo falla)

```bash
# 1. Detener bare metal
sudo systemctl stop hermes
sudo systemctl disable hermes

# 2. Volver a Docker
cd ~/ai-lab/repos/hermes-agent
docker compose up -d

# 3. Verificar
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:9119
```

El estado (`~/.hermes/`) no se toca — el rollback es limpio en < 2 minutos.

---

## Acceso al dashboard

**URL:** `http://<SERVER_IP>:9119` (solo desde Tailscale)

Desde el dashboard podés:
- Ver el estado del gateway y las plataformas conectadas
- Revisar el historial de conversaciones
- Iniciar una sesión de chat directamente en el browser

---

*Para el historial completo de la migración: `docs/CHANGELOG.md`*
