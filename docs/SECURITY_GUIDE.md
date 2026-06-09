# Seguridad del lab — Guía de referencia

Prácticas de seguridad para el stack AI Lab: Hermes, Paperclip y acceso SSH.
Sin secrets — toda credencial vive fuera del repositorio.

---

## 1. Hermes Gateway — Telegram

El gateway de Telegram es la superficie de mayor riesgo operativo. Cualquier
bot público es indexado por el directorio de Telegram y puede recibir mensajes
de usuarios no autorizados. Hermes bloquea el acceso por defecto si el allowlist
está configurado.

### Requisito crítico: allowlist obligatorio

```bash
# ~/.hermes/.env
TELEGRAM_BOT_TOKEN=<token-del-bot>
TELEGRAM_ALLOWED_USERS=<tu-user-id-de-telegram>
```

Para obtener tu User ID:
```
https://api.telegram.org/bot<TOKEN>/getUpdates
```
El ID aparece en el campo `message.from.id`.

**Nunca activar acceso irrestricto:**
```bash
# NUNCA poner esto en producción:
# GATEWAY_ALLOW_ALL_USERS=true
```

### Verificar configuración activa

```bash
grep "TELEGRAM_ALLOWED_USERS\|GATEWAY_ALLOW_ALL" ~/.hermes/.env
```

Debe mostrar `TELEGRAM_ALLOWED_USERS` con tu ID y NO debe aparecer
`GATEWAY_ALLOW_ALL_USERS=true`.

### Monitorear intentos no autorizados

```bash
grep "Unauthorized user" ~/.hermes/logs/gateway.log
```

Cada intento bloqueado genera una línea como:
```
WARNING gateway.run: Unauthorized user: 123456789 (username) on telegram
```

Cron opcional para reporte diario:
```bash
# Agregar a crontab -e:
0 8 * * * grep "Unauthorized user" ~/.hermes/logs/gateway.log | tail -20 >> ~/ai-lab/logs/security-daily.log
```

---

## 2. API Keys — higiene

| Regla | Motivo |
|---|---|
| Una key por perfil/servicio | Limitar el radio de impacto si una key se expone |
| Keys en `~/.hermes/.env`, nunca en config.yaml | config.yaml puede entrar al repo accidentalmente |
| Rotar si se sospecha exposición | Las keys de OpenCode se rotan desde el dashboard |
| No compartir keys entre perfiles de Hermes | Cada perfil tiene su propio `.env` |

### Verificar que no hay keys en el repo

```bash
cd ~/ai-lab/repos
git log --all --full-diff -p | grep -E "sk-|TELEGRAM_BOT_TOKEN" | head -5
```

Si aparece algo, la key está comprometida — rotar inmediatamente.

---

## 3. SSH hardening

El módulo `01-system.sh` aplica automáticamente:

```
PermitRootLogin no
PasswordAuthentication no
TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 3
```

Esto garantiza:
- Sin acceso root directo
- Solo autenticación por clave pública
- Detección de sesiones muertas en 90 segundos

**En el cliente (Mac) — agregar a `~/.ssh/config`:**
```
Host <nombre-servidor>
    HostName <ip-tailscale>
    User <usuario>
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

---

## 4. Docker — límites de memoria

Sin límite de memoria, un proceso zombie puede crecer hasta agotar la RAM
del servidor y matar la sesión SSH. El `docker-compose.yml` de Paperclip
debe incluir:

```yaml
services:
  server:
    mem_limit: 4g
    memswap_limit: 4g
    restart:
      condition: on-failure
      delay: 30s
      max_attempts: 5
      window: 120s
```

Ver `PAPERCLIP_GUIDE.md` para la configuración completa.

---

## 5. Redacción de secrets en logs

`redact_secrets` está activo por defecto en Hermes (`True` en código fuente).
No requiere configuración explícita, pero puede dejarse documentado en
`~/.hermes/config.yaml` para hacerlo auditable:

```yaml
security:
  redact_secrets: true
```

---

## 6. Checklist post-instalación

Ejecutar después de cada instalación nueva:

```bash
# 1. Verificar SSH hardening
sudo sshd -T | grep -E "permitrootlogin|passwordauthentication|clientalive"

# 2. Verificar Hermes Telegram allowlist
grep "TELEGRAM_ALLOWED_USERS" ~/.hermes/.env

# 3. Verificar que no hay GATEWAY_ALLOW_ALL
grep "GATEWAY_ALLOW_ALL" ~/.hermes/.env ~/.hermes/config.yaml 2>/dev/null

# 4. Verificar límite de memoria Docker
docker inspect paperclip-server-1 --format '{{.HostConfig.Memory}}' 2>/dev/null

# 5. Verificar watchdog activo
crontab -l | grep paperclip-watchdog
```

---

## Referencias

- `docs/HERMES_CONFIG_GUIDE.md` — configuración completa de Hermes
- `docs/PAPERCLIP_GUIDE.md` — configuración completa de Paperclip
- `templates/hermes.env.example` — template de `.env` con comentarios
- Hermes `SECURITY.md` — modelo de confianza y política de vulnerabilidades
