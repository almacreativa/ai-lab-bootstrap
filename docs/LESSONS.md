# Lecciones aprendidas (en producción, para que no las repitas)

Errores reales encontrados montando el lab. Cada una costó tiempo de debugging.

## Docker y seguridad

1. **Docker bypassea UFW.** Docker escribe sus propias reglas iptables (DNAT antes
   de INPUT): las reglas UFW NO protegen puertos publicados por contenedores. La
   protección real es el **bind address** (`127.0.0.1:` o IP de Tailscale). UFW solo
   sirve para servicios bare metal. Corolario: ningún compose publica en `0.0.0.0`.
2. **Contenedor → host también pasa por UFW.** Un contenedor que necesita llegar a un
   servicio bare metal del host (ej: un monitor) requiere regla explícita para el
   rango Docker: `ufw allow from 172.16.0.0/12 to any port <p>`.
3. **postgres alpine → debian corrompe índices.** Cambiar la imagen de Postgres entre
   musl (alpine) y glibc (debian/pgvector) sobre el mismo volumen rompe el
   ordenamiento de índices de texto (collation). Camino seguro: dump → volumen NUEVO
   → init limpio → restore. El volumen viejo queda de rollback gratis.
4. **Servicios detrás de `tailscale serve`**: bindear a `127.0.0.1` y dejar que serve
   termine TLS. HTTPS válido sin exponer nada, y Google OAuth funciona porque
   `*.ts.net` es un dominio real con certificado.

## Plataforma de agentes (Paperclip)

5. **La portabilidad/clonado de empresas copia los workspaces CON contenido.** Al
   crear una empresa desde otra, los agentes nuevos nacen con los archivos internos
   de la empresa origen. Vaciar los workspaces antes de operar:
   `find <workspace> -mindepth 1 -delete` dentro del contenedor.
6. **Dos agentes con el mismo nombre en empresas distintas colisionan en cualquier
   espejo por-nombre.** Enrutar espejos por empresa (join con `companies.issue_prefix`),
   no solo por nombre de agente.
7. **Los plugins (alpha) no vienen compilados en la imagen.** El manifest es un
   artefacto de build (`dist/manifest.js`). Buildear in-container (`pnpm build` en el
   paquete del plugin) y **persistir `dist/` con un mount** — si el contenedor se
   recrea sin él, el plugin queda en `status=error` y hay que resetearlo en la tabla
   `plugins` además de rebuildear.
8. **Los agentes comparten contenedor y tienen bash** ⇒ el aislamiento por aplicación
   es blando. Mounts granulares por empresa o sandbox providers.

## Orquestador (Hermes)

9. **El binario no está en PATH de shells no interactivos** (cron, scripts): usar la
   ruta absoluta del venv.
10. **Su sandbox resuelve `~` a un home interno** (`~/.hermes/home/`): todo lo que se
    le documente en memoria debe usar rutas absolutas.
11. **Bot de Telegram público = intentos de acceso garantizados.** Configurar
    `TELEGRAM_ALLOWED_USERS` SIEMPRE, nunca `GATEWAY_ALLOW_ALL_USERS=true`.

## Outline

12. **No tiene login usuario/password** — exige proveedor de auth. Y **el plugin
    nativo de Google rechaza cuentas Gmail personales** ("Cannot create account using
    personal gmail address"). Solución: las mismas credenciales de Google como **OIDC
    genérico** (`OIDC_AUTH_URI=https://accounts.google.com/o/oauth2/v2/auth`, callback
    `/auth/oidc.callback` — agregar esa redirect URI en Google Console).

## Pipeline de conocimiento

13. **Destilación incremental o muerte.** Sin estado (`.processed.yaml` con id+hash),
    cada corrida reprocesa todo: cada vez más lenta y más cara. Con estado, una semana
    sin novedades cuesta segundos.
14. **La primera destilación se revisa a mano.** El LLM barato destila bien pero
    comete errores de matiz (reportar planes como hechos, invertir el sentido de una
    regla). Es la semilla de todo el knowledge: 15 minutos de revisión humana evitan
    propagar errores a cada agente futuro.
15. **NotebookLM no se automatiza.** Las cookies OAuth expiran (~14 días). Sync
    semi-manual mensual con verificación de auth al inicio y fallo elegante.
16. **El LLM gratis alcanza para destilación rutinaria.** Modelos free-tier vía
    OpenAI-compatible API destilan sesiones y patrones correctamente. Reservar
    modelos pagos para la primera pasada pesada, si hace falta.
