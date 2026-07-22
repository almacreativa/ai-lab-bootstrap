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

## 6. Modelo de seguridad: tres capas

El lab usa un modelo de defensa en profundidad con tres capas para servicios bare
metal, más una capa independiente para Docker:

```
INTERNET
  └─ CAPA 1: Tailscale VPN (perímetro primario)
       Solo dispositivos autorizados en la red
       └─ CAPA 2: UFW por puerto (segunda barrera)
            deny incoming por defecto
            allow por puerto desde 100.64.0.0/10 (Tailscale)
            allow SSH desde LAN (anti-lockout)
            └─ CAPA 3: fail2ban (SSH)
                 Rate-limiting en SSH desde LAN

DOCKER (capa independiente):
  UFW NO protege Docker (bypassea INPUT vía FORWARD chain)
  Protección = bind address en compose files
  Patrón: 127.0.0.1:PORT + ${TAILSCALE_IP}:PORT (dual bind)
  Nunca 0.0.0.0
```

---

## 7. UFW — reglas por puerto desde el manifiesto

`security-apply-sudo.sh` lee la sección `security.allowed_ports[]` del manifiesto
(`core-manifest.yaml`) y genera reglas UFW dinámicamente. No hay IPs ni puertos
hardcodeados en el script.

**Flujo para agregar un servicio nuevo:**

1. Declarar el puerto y servicio en `core-manifest.yaml` → sección `security.allowed_ports[]`
2. Regenerar el manifiesto: `generate-core-manifest.sh`
3. Aplicar reglas: `security-apply-sudo.sh` (genera reglas UFW desde el manifiesto)

El manifiesto es la fuente de verdad. Los scripts lo consumen automáticamente.

**Flujo para migrar a otra red:**

1. Correr `rehome.sh` — detecta nueva LAN y nueva IP de Tailscale
2. Actualiza `~/ai-lab/scripts/.env` (TAILSCALE_IP, LAN_SUBNET, LAB_IP)
3. Regenera manifiesto con las nuevas IPs
4. Regenera reglas UFW

---

## 8. Docker y UFW

**Corrección técnica importante:** UFW **no** protege contenedores Docker. Docker
escribe sus propias reglas iptables y bypassea la cadena `INPUT` de UFW vía la
cadena `FORWARD`.

La protección real de los puertos Docker es el **bind address** en el compose file:

```yaml
# Patrón dual bind (recomendado):
ports:
  - "127.0.0.1:${PORT}:${PORT}"       # solo localhost
  - "${TAILSCALE_IP}:${PORT}:${PORT}" # solo Tailscale

# Nunca:
ports:
  - "${PORT}:${PORT}"                  # ❌ expone en 0.0.0.0
```

El dual bind (`127.0.0.1` + IP de Tailscale) es necesario cuando hay consumidores
locales (scripts que usan `localhost:PORT`) y consumidores remotos (vía Tailscale).

El watchdog v2 (`exposure-watchdog.sh`) verifica que ningún contenedor bindee a
`0.0.0.0` y alerta si encuentra una desviación.

---

## 9. fail2ban

fail2ban protege SSH contra brute-force. Instalado automáticamente por
`security-apply-sudo.sh` si el manifiesto lo requiere.

### Configuración de la jail SSH

```ini
# /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
findtime = 600
bantime = 3600
```

- **maxretry = 5** — 5 intentos fallidos antes del baneo
- **findtime = 600** — ventana de 10 minutos para contar intentos
- **bantime = 3600** — baneo de 1 hora

Verificar estado:
```bash
sudo fail2ban-client status sshd
```

---

## 10. Checklist post-instalación

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

# 5. Verificar watchdog DAG activo
crontab -l | grep paperclip-watchdog

# 6. Verificar UFW per-port (no per-interface)
sudo ufw status numbered
# Esperado: una regla por puerto, NO "allow in on tailscale0"

# 7. Verificar fail2ban activo
sudo fail2ban-client status sshd

# 8. Verificar Docker binds (ningún 0.0.0.0)
ss -tlnp | grep docker
# O usar el watchdog: exposure-watchdog.sh check docker
```

---

## Referencias

- `docs/HERMES_CONFIG_GUIDE.md` — configuración completa de Hermes
- `docs/PAPERCLIP_GUIDE.md` — configuración completa de Paperclip
- `templates/hermes.env.example` — template de `.env` con comentarios
- Hermes `SECURITY.md` — modelo de confianza y política de vulnerabilidades
