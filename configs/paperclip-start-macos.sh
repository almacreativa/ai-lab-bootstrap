#!/bin/bash
# Paperclip launcher (macOS) — generado por bootstrap-macos.sh con HOME
set -e

export HOME="{{HOME}}"
cd "$HOME/ai-lab/repos/paperclip"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

set -a
[ -f .env.paperclip ] && source .env.paperclip
set +a

export DATABASE_URL="${DATABASE_URL:-postgres://paperclip@localhost:5432/paperclip}"

echo "[paperclip-start] Corriendo migraciones..."
npx pnpm run db:migrate 2>/dev/null || true

echo "[paperclip-start] Iniciando servidor en puerto ${PORT:-3100}"
exec node server/dist/index.js
