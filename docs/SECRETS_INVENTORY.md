# Inventario y política de secrets
**Actualizado:** 2026-06-11 · Este documento lista UBICACIONES, jamás valores.

## Política (no negociable)

1. **Ningún secret entra a NINGÚN repo git** — ni privado ni público. Este repo
   versiona `.env.example`; los `.env` reales viven solo en el servidor con permisos 600.
2. Los repos llevan **hook pre-commit anti-secrets** (`scripts/pre-commit-secrets.sh`).
3. Rotación: puntual ante sospecha, no calendarizada (lab de un operador).
   Bitwarden/BWS evaluado y descartado por overkill — ver `DECISIONES_KM.md` ADR #14.
4. Los agentes tienen PROHIBIDO escribir credenciales en wiki, memorias, deliverables
   o knowledge (instrucción en todos los skills y snippets).
5. Al crear una automatización que use una key: agregarla a la columna **"Lo consume"**
   de este documento inmediatamente. Ver `DIRECTRICES_AUTOMATIZACIONES.md` regla #4.

## Dónde vive cada secret (servidor)

| Archivo (600) | Contiene | Lo consume |
|---------------|----------|------------|
| `$HOME/.hermes/.env` | Telegram bot token, keys de LLM providers, `MEM0_API_KEY`, `OUTLINE_API_KEY`, `PCP_BOARD_KEY` (board API de Paperclip) | Hermes + sus cron jobs |
| `$HOME/.hermes/auth.json` | credential_pool (providers de LLM del lab) | Hermes |
| `$HOME/.local/share/opencode/auth.json` | keys de OpenCode CLI (montado ro en Paperclip) | OpenCode + agentes Paperclip |
| `~/ai-lab/repos/paperclip/docker/.env` | `POSTGRES_PASSWORD`, `BETTER_AUTH_SECRET`, `MEM0_API_KEY`, URL pública | compose de Paperclip |
| `~/ai-lab/stacks/mem0/.env` | key del LLM de extracción, `MEM0_API_KEY` | Mem0 |
| `~/ai-lab/stacks/outline/.env` | `SECRET_KEY`, `UTILS_SECRET`, password DB, OIDC client id/secret de Google | Outline |
| `~/ai-lab/stacks/outline/.apikey` | API key admin de Outline | scripts/Hermes |
| `~/ai-lab/stacks/nlm-gateway/.env` | `GATEWAY_API_KEY` (también en compose de Paperclip como NLM_GATEWAY_KEY) | NLM Gateway + agentes Paperclip |
| `~/ai-lab/scripts/.env` | Telegram token/chat, `KUMA_PUSH_URL` | weekly-ingest, notificaciones |
| `$HOME/.config/gh/` | OAuth de GitHub (cuenta `<GIT_USER>`) | gh CLI |
| Cookies NLM (perfil de `nlm`) | sesión Google NotebookLM (~14 días) | nlm CLI / MCP |

## Auditoría

Trimestral (o tras cualquier incidente): verificar permisos 600 y ausencia en git:
```bash
for f in $HOME/.hermes/.env ~/ai-lab/repos/paperclip/docker/.env \
         ~/ai-lab/stacks/{mem0,outline}/.env ~/ai-lab/scripts/.env; do stat -c "%a %n" "$f" 2>/dev/null; done
for r in ~/ai-lab/repos/*/; do [ -d "$r/.git" ] && git -C "$r" ls-files | grep -E "\.env$|\.apikey" | grep -v example && echo "ADVERTENCIA: $r"; done
```

## Notas sobre gestión de secrets

- **Centralización vs. fricción:** para un lab de un operador, `.env` 600 fuera de git es suficiente.
  Evaluar Bitwarden Secrets Manager si entra un segundo operador o los secrets se multiplican.
- **Rotación reactiva:** rotar ante sospecha de compromiso, no en calendario fijo.
  Documentar cada rotación con fecha y motivo.
- **Plantillas huérfanas:** verificar periódicamente que no existan archivos `.env` con
  nombres de variables pero valores placeholder — pueden confundir auditorías automatizadas.
