#!/bin/bash
# Módulo 06 — Instrucciones de pasos manuales post-bootstrap

LOCAL_IP="$(hostname -I | awk '{print $1}')"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}${BOLD}  Bootstrap completo.${NC}"
echo ""
echo -e "${YELLOW}${BOLD}  PASOS MANUALES REQUERIDOS${NC}"
echo -e "  (no se pueden automatizar — requieren autenticación interactiva)"
echo ""
echo "  ── 1. SECRETS ─────────────────────────────────────────────"
echo "  Completar los archivos de configuración antes de iniciar"
echo "  los servicios:"
echo ""
echo "    ~/.hermes/.env          → Telegram bot token + OpenCode key"
echo "    ~/.env_agents           → API keys (Anthropic, OpenAI, etc.)"
echo "    $LAB_DIR/repos/paperclip/.env.paperclip"
echo ""
echo "  Templates de referencia en: $SCRIPT_DIR/templates/"
echo "  Generar BETTER_AUTH_SECRET con: openssl rand -hex 32"
echo ""
echo "  ── 2. TAILSCALE ────────────────────────────────────────────"
echo "     sudo tailscale up"
echo ""
echo "  ── 3. GITHUB CLI ───────────────────────────────────────────"
echo "     gh auth login"
echo ""
echo "  ── 4. CLAUDE CODE ──────────────────────────────────────────"
echo "     npm install -g @anthropic-ai/claude-code"
echo "     claude    ← para completar el login"
echo ""
echo "  ── 5. NOTEBOOKLM (nlm) — login headless via CDP ───────────"
echo "     # En el servidor (terminal 1):"
echo "     Xvfb :99 -screen 0 1280x720x24 &"
echo "     export DISPLAY=:99"
echo "     nlm login --force"
echo ""
echo "     # En el servidor (terminal 2):"
echo "     ss -tlnp | grep 9222    ← verificar que Chromium expone CDP"
echo ""
echo "     # Desde tu Mac (terminal local):"
echo "     ssh -L 9222:localhost:9222 $LAB_USER@$LOCAL_IP"
echo ""
echo "     # En Chrome del Mac:"
echo "     Abrir chrome://inspect → Configure → localhost:9222"
echo "     Clic en 'inspect' en el tab de Google Sign-in"
echo "     Completar login de Google normalmente"
echo ""
echo "     # Verificar:"
echo "     nlm notebook list"
echo ""
echo "  ── 6. GEMINI CLI ───────────────────────────────────────────"
echo "     gemini    ← sigue el flujo OAuth en el navegador"
echo ""
echo "  ── 7. OPENCODE ─────────────────────────────────────────────"
echo "     opencode  ← seleccionar provider y autenticar"
echo ""
echo "  ── 8. INICIAR SERVICIOS ────────────────────────────────────"
echo "     # Después de completar los secrets:"
echo "     sudo systemctl start hermes"
echo ""
echo "     # Dagu (systemd user — primer inicio abre UI para crear credenciales):"
echo "     systemctl --user start dagu"
echo "     # Abrir http://<TAILSCALE_IP>:8480 → crear usuario admin"
echo "     # Guardar credenciales en ~/.hermes/.env (DAGU_AUTH_USER, DAGU_AUTH_PASS)"
echo ""
echo "     # Paperclip:"
echo "     cd $LAB_DIR/repos/paperclip"
echo "     docker compose -f docker/docker-compose.yml \\"
echo "       --env-file .env.paperclip \\"
echo "       --project-name paperclip \\"
echo "       up -d --build"
echo ""
echo "  ── 9. PORTAINER ────────────────────────────────────────────"
echo "     https://$LOCAL_IP:9443    ← crear usuario admin"
echo ""
echo "  ── 10. SYNCTHING — configurar sincronización con Tailscale ────"
echo "     # Obtener Device ID de este servidor:"
echo "     syncthing --device-id"
echo ""
echo "     # La GUI escucha solo en localhost:8384 (default — no cambiar)."
echo "     # Acceder siempre via tunnel SSH desde tu máquina local:"
echo "     ssh -L 8384:localhost:8384 $LAB_USER@<IP-del-servidor>"
echo "     # Luego abrir: http://localhost:8384"
echo ""
echo "     # En GUI → Actions → Settings → GUI:"
echo "     Configurar usuario y contraseña"
echo "     (GUI Listen Address debe quedar en 127.0.0.1:8384 — no modificar)"
echo ""
echo "     # En GUI → Settings → Connections:"
echo "     Listen Addresses: default   ← NO fijar a una IP específica"
echo "     Desactivar: Global Discovery, Enable Relays, NAT Traversal"
echo ""
echo "     # Agregar carpeta sincronizada:"
echo "     Folder ID: knowledge"
echo "     Folder Path: $LAB_DIR/knowledge"
echo "     File Versioning: Staggered — mantener 90 días (protección ransomware)"
echo ""
echo "     # En Mac: instalar Syncthing desde https://syncthing.net/downloads/"
echo "     Intercambiar Device IDs entre servidor y Mac"
echo "     Agregar la misma carpeta en el Mac (ej. ~/Documents/knowledge)"
echo ""
echo "  ── 11. SSH — keepalive para evitar sesiones colgadas ──────
     # En el servidor (ya configurado por el bootstrap):
     # /etc/ssh/sshd_config tiene ClientAliveInterval 30 y ClientAliveCountMax 3

     # En tu Mac — agregar a ~/.ssh/config:
     Host <nombre-servidor>
         HostName <ip-tailscale>
         User $LAB_USER
         ServerAliveInterval 30
         ServerAliveCountMax 3

     # Después puedes conectarte con: ssh <nombre-servidor>

  ── 12. TMUX — sesión persistente del lab ───────────────────
     # La sesión se crea automáticamente al boot via cron (@reboot).
     # Para abrirla o reconectarla manualmente:
     lab

     # El script ~/ai-lab/scripts/lab-session.sh crea 4 ventanas:
     #   1. trabajo  — shell limpio
     #   2. hermes   — shell limpio (lanzar logs: journalctl -u hermes -f)
     #   3. paperclip — shell limpio (lanzar logs: docker compose logs -f server)
     #   4. monitor  — htop corriendo
     #
     # Atajos clave (prefijo: Ctrl+a):
     #   Ctrl+a + 1/2/3/4  → cambiar ventana
     #   Ctrl+a + d         → desconectarse sin cerrar la sesión
     #   Ctrl+a + |         → dividir vertical
     #   Ctrl+a + -         → dividir horizontal

  ── 13. SEARXNG — activar en Hermes ────────────────────────"
echo "     Agregar a ~/.env_agents:"
echo "     SEARXNG_URL=http://localhost:8080"
echo ""
echo "     Verificar que Hermes lo detecta:"
echo "     hermes   →   /tools  →  buscar 'web_search backend'"
echo ""
echo "  Documentación completa: README.md"
echo "═══════════════════════════════════════════════════════════════"
echo ""
