# Outline — Wiki pública del AI Lab

Implementa la **Fase 7** del plan (`~/shared/demos/knowledge-management-execution-plan.md`).
RAM total: ~1.1GB (Outline 1g + Postgres 384m + Redis 256m). Storage local, sin MinIO.

Outline **no tiene login con usuario/password**: requiere un proveedor de
autenticación. Para el lab usamos **Google OAuth + HTTPS de Tailscale** (Google exige
una URL HTTPS con dominio real; el dominio `*.ts.net` de Tailscale cumple).

## Pasos de instalación

### 1. Secrets — [HUMANO, 2 min]

```bash
cd ~/ai-lab/stacks/outline
cp .env.example .env
openssl rand -hex 32   # → SECRET_KEY
openssl rand -hex 32   # → UTILS_SECRET
openssl rand -hex 16   # → OUTLINE_DB_PASSWORD (también dentro de DATABASE_URL)
```

### 2. HTTPS vía Tailscale — [HUMANO, 5 min]

```bash
# Habilitar HTTPS en el tailnet (una vez): admin console → DNS → Enable HTTPS
sudo tailscale serve --bg --https=443 http://127.0.0.1:3010
tailscale serve status    # muestra la URL: https://<maquina>.<tailnet>.ts.net
```

Poner esa URL en `URL=` del `.env`. Cualquier dispositivo del tailnet accede con
HTTPS válido; nada queda expuesto a internet.

### 3. Google OAuth — [HUMANO, 10 min]

1. https://console.cloud.google.com/apis/credentials → Create Credentials → OAuth Client ID
2. Tipo: Web application
3. Authorized redirect URI: `https://<maquina>.<tailnet>.ts.net/auth/google.callback`
   (la ruta exacta importa)
4. Si pide configurar pantalla de consentimiento: tipo External, solo el email del lab
   como test user alcanza.
5. Copiar Client ID y Client Secret al `.env`.

### 4. Deploy — [AGENTE o humano]

```bash
cd ~/ai-lab/stacks/outline
docker compose up -d
docker logs outline --tail 20    # esperar "listening on port 3000"
```

Primer login con la cuenta Google → ese usuario queda admin.

### 5. Estructura de colecciones — [HUMANO en la UI, según plan F7.2]

```
Borrador/         ← propuestas de agentes pendientes de revisión
<Empresa A>/    ← Proyectos / Deliverables / Decisiones
Compartido/       ← Templates / Boilerplate
```

El conocimiento del lab (infra, IPs, stack) NO va a Outline — es privado de Hermes.

### 6. MCP para agentes — [AGENTE]

1. En Outline: Settings → API → New API key (una key por agente/herramienta;
   con permisos limitados a su colección donde aplique)
2. Hermes: agregar el MCP server de Outline a `~/.hermes/config.yaml` con
   `OUTLINE_API_URL=https://<url>/api` y la key
3. Validar: `hermes chat -q "listá los documentos en Outline" --max-turns 2`

## Operación

- Backup: volúmenes `outline-pg` y `outline-data` (incluir en el backup del lab)
- Rollback de documentos: historial de versiones nativo de Outline (un clic)
- Monitoreo: agregar monitor HTTP en Uptime Kuma → `http://localhost:3010`
