# Handoff: Migrar Hermes de Docker a bare metal

**Destinatario:** Agente implementador
**Autor:** Claude Code (sesion de arquitectura — 2026-05-24)
**Estado actual:** Hermes v0.14.0 corriendo en Docker con gateway Telegram activo
**Objetivo:** Mover Hermes fuera del contenedor para que tenga acceso nativo a opencode CLI, claude CLI y git

---

## Por que esta migracion

Hermes en Docker no puede usar las herramientas CLI del host (opencode, claude, gh). Para un lab de agentes autonomos eso es un bloqueante. La solucion mas limpia, y la que usa la comunidad en labs personales, es correr Hermes directamente en el host.

**Lo que no cambia:**
- Todo el estado de Hermes (`~/.hermes/`) se queda donde esta — no se migra nada
- El bot de Telegram (`@<YOUR_BOT>`) sigue funcionando igual
- El dashboard queda en el mismo puerto 9119
- Memories, SOUL.md, config.yaml, API keys — todo intacto

**Lo que cambia:**
- Hermes pasa de proceso dentro de Docker a proceso systemd en el host
- Gana acceso nativo a todas las herramientas del host

---

## Estado del servidor al momento de esta migracion

| Item | Valor |
|---|---|
| OS | Ubuntu 24.04.4 LTS |
| Usuario | `<YOUR_USER>` (UID=1000) |
| IP Tailscale | `<SERVER_IP>` (hostname: `your-server`) |
| Hermes data | `~/.hermes/` (bind mount activo) |
| Hermes imagen | `hermes-agent` (ya buildeada, UID=1000 baked in) |
| Hermes container | `hermes` (en `~/ai-lab/repos/hermes-agent/`) |
| Gateway activo | Telegram (`@<YOUR_BOT>`) |
| Dashboard | `http://<SERVER_IP>:9119` via Tailscale |

---

## Paso 1 — Instalar Hermes en el host

```bash
python3 --version   # debe ser 3.11+
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
uv venv ~/.hermes-env --python 3.11
source ~/.hermes-env/bin/activate
pip install hermes-agent
```

**VERIFICACION 1:**
```bash
~/.hermes-env/bin/hermes --version
```

---

## Paso 2 — Probar Hermes bare metal antes de apagar Docker

```bash
HERMES_DATA_DIR=~/.hermes ~/.hermes-env/bin/hermes --version
~/.hermes-env/bin/hermes chat -q "responde solo con la palabra: ok"
```

---

## Paso 3 — Crear servicio systemd

```bash
sudo tee /etc/systemd/system/hermes.service << 'EOF'
[Unit]
Description=Hermes Agent — gateway Telegram + dashboard
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=<YOUR_USER>
Group=<YOUR_USER>
WorkingDirectory=$HOME/.hermes
EnvironmentFile=$HOME/.hermes/.env
ExecStart=$HOME/.hermes-env/bin/hermes gateway run --accept-hooks
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable hermes
```

---

## Paso 4 — Apagar Docker y arrancar bare metal

```bash
cd ~/ai-lab/repos/hermes-agent
docker compose down
ss -tlnp | grep 9119
sudo systemctl start hermes
journalctl -u hermes -f
```

**VERIFICACION 4:**
```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:9119
sudo systemctl status hermes
```

---

## Paso 5 — Test end-to-end por Telegram

> "ok hermes, respondeme solo con: migracion exitosa"

---

## Paso 6 — Actualizar config.yaml (cwd del terminal)

```yaml
terminal:
  backend: "local"
  cwd: "$HOME/ai-lab/workspace"
```

```bash
sudo systemctl restart hermes
```

---

## Paso 7 — Verificar acceso a herramientas del host

```
which opencode && opencode --version
which claude && claude --version
```

Si no encuentra los binarios:
```ini
Environment="PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"
```

---

## Paso 8 — Limpieza opcional del contenedor Docker

```bash
docker rm hermes
docker rmi hermes-agent
```

> **No borrar `~/.hermes/`** — ahi estan todos los datos.

---

## Rollback — volver a Docker si algo falla

```bash
sudo systemctl stop hermes
sudo systemctl disable hermes
cd ~/ai-lab/repos/hermes-agent
docker compose up -d
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:9119
```

---

## Resumen de verificaciones

| Paso | Verificacion | Resultado esperado |
|---|---|---|
| 1 | `hermes --version` | Version impresa |
| 2 | Chat `responde: ok` | Responde correctamente |
| 3 | `systemctl status hermes` | enabled, inactive |
| 4 | `curl localhost:9119` + status | HTTP 200, active running |
| 5 | Mensaje Telegram | Bot responde |
| 6 | Reinicio con nuevo cwd | Sin errores en logs |
| 7 | `which opencode` desde Hermes | Ruta encontrada |

---

## Reglas que aplican durante toda la sesion

- **NUNCA** tocar `~/dev/` — esta completamente fuera de alcance
- Las API keys (`~/.hermes/.env`) nunca van a ningun repositorio

---

*Documento generado 2026-05-24.*
*No contiene API keys reales.*
