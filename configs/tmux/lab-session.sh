#!/bin/bash
# Crea o reconecta la sesión tmux del lab.
#
# Uso:    bash lab-session.sh
# Alias:  agregar a ~/.bashrc: alias lab="bash ~/ai-lab/configs/tmux/lab-session.sh"
#
# Ventanas predefinidas:
#   1. temps        — temperatura y fan del procesador (watch sensors)
#   2. hermes-logs  — logs del orquestador (journalctl)
#   3. docker       — logs de contenedores (docker compose logs -f)
#   4. shell        — terminal libre en ~/ai-lab
#
# Personalizar: agregar ventanas adicionales para sesiones de Claude Code,
# OpenCode, o proyectos específicos (ver ejemplos comentados al final).

SESSION="lab"

if tmux has-session -t $SESSION 2>/dev/null; then
  tmux attach -t $SESSION
  exit 0
fi

# Ventana 1: temperatura y fan del procesador
tmux new-session -d -s $SESSION -n "temps" -x 220 -y 50
tmux send-keys -t $SESSION:1 "watch -n 2 sensors" Enter

# Ventana 2: logs de Hermes
tmux new-window -t $SESSION -n "hermes-logs"
tmux send-keys -t $SESSION:2 "journalctl -u hermes -f" Enter

# Ventana 3: logs de Docker (Paperclip + servicios)
tmux new-window -t $SESSION -n "docker"
tmux send-keys -t $SESSION:3 "cd ~/ai-lab/repos/paperclip/docker && docker compose logs -f --tail 50" Enter

# Ventana 4: terminal libre
tmux new-window -t $SESSION -n "shell"
tmux send-keys -t $SESSION:4 "cd ~/ai-lab" Enter

# Arrancar en la terminal libre
tmux select-window -t $SESSION:4

tmux attach -t $SESSION

# ── Ejemplos para personalizar (descomentar y adaptar) ───────────────────────
#
# Ventana de Claude Code con sesión específica:
#   tmux new-window -t $SESSION -n "claude"
#   tmux send-keys -t $SESSION:5 "cd ~/dev/mi-proyecto && claude --resume 'mi-sesion'" Enter
#
# Ventana de OpenCode:
#   tmux new-window -t $SESSION -n "opencode"
#   tmux send-keys -t $SESSION:6 "cd ~/dev/mi-proyecto && opencode" Enter
#
# Ventana de monitoreo con htop:
#   tmux new-window -t $SESSION -n "htop"
#   tmux send-keys -t $SESSION:7 "htop" Enter
