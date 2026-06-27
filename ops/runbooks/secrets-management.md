# Secrets Management — Bundle con age

## Arquitectura

Los secrets del lab se distribuyen en archivos `.env` con permisos 600.
Para transferir secrets entre labs se usa `age` (cifrado asimétrico).

```
secrets.age (en password manager)
    ↓ age -d
lab-secrets.env (temporal, se destruye)
    ↓ setup-instance.sh
~/.hermes/.env          → Telegram, AI keys, Dagu auth
~/ai-lab/scripts/.env   → Backup, monitoring, notificaciones
~/ai-lab/repos/paperclip/docker/.env  → Postgres, auth
~/ai-lab/stacks/outline/.env          → Outline keys
~/ai-lab/stacks/mem0/.env             → Mem0 keys
```

## Crear el bundle (una vez por lab)

```bash
# 1. Generar age key (solo una vez en la vida)
age-keygen -o ~/age-key.txt
# GUARDAR ~/age-key.txt EN PASSWORD MANAGER — sin ella no se puede desencriptar

# 2. Crear archivo de secrets
cat > /tmp/lab-secrets.env << 'EOF'
# Backup
B2_ACCOUNT_ID=
B2_BACKUP_KEY=
RESTIC_REPOSITORY=b2:lab-backpus
RESTIC_PASSWORD=

# Telegram
TELEGRAM_BOT_TOKEN=
TELEGRAM_ALLOWED_USERS=

# Monitoring
UPTIME_KUMA_PUSH_URL=
KUMA_PUSH_URL=
CPU_TEMP_KUMA_PUSH_URL=
CENTRO_KUMA_PUSH_URL=

# AI Providers
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
OPENCODE_GO_API_KEY=

# Paperclip
BETTER_AUTH_SECRET=
PAPERCLIP_PUBLIC_URL=http://100.x.x.x:3100
POSTGRES_PASSWORD=

# Dagu
DAGU_AUTH_USER=
DAGU_AUTH_PASS=

# Outline (si se usa)
OUTLINE_SECRET_KEY=
OUTLINE_UTILS_SECRET=

# Mem0 (si se usa)
MEM0_API_KEY=

# NLM Gateway (si se usa)
GATEWAY_API_KEY=

# PCP Board
PCP_BOARD_KEY=
EOF

# 3. Llenar los valores reales
nano /tmp/lab-secrets.env

# 4. Encriptar
AGE_PUB=$(grep "public key:" ~/age-key.txt | awk '{print $NF}')
age -r "$AGE_PUB" -o secrets.age /tmp/lab-secrets.env

# 5. Destruir el archivo en claro
shred -u /tmp/lab-secrets.env

# 6. Guardar secrets.age en password manager
```

## Usar el bundle en un lab nuevo

```bash
# Transferir secrets.age y age-key.txt al servidor
scp secrets.age age-key.txt user@newserver:~/

# Correr setup-instance.sh
cd ~/ai-lab/repos/ai-lab-bootstrap
./setup-instance.sh --secrets ~/secrets.age
```

## Actualizar el bundle

Cuando se agrega un secret nuevo:

```bash
# 1. Desencriptar
age -d -i ~/age-key.txt -o /tmp/lab-secrets.env secrets.age

# 2. Editar
nano /tmp/lab-secrets.env

# 3. Re-encriptar
AGE_PUB=$(grep "public key:" ~/age-key.txt | awk '{print $NF}')
age -r "$AGE_PUB" -o secrets.age /tmp/lab-secrets.env

# 4. Destruir
shred -u /tmp/lab-secrets.env
```

## Auditoría de permisos

Verificar que todos los `.env` tienen permisos 600:

```bash
for f in ~/.hermes/.env \
         ~/ai-lab/scripts/.env \
         ~/ai-lab/repos/paperclip/docker/.env \
         ~/ai-lab/stacks/mem0/.env \
         ~/ai-lab/stacks/outline/.env; do
  if [ -f "$f" ]; then
    perms=$(stat -c "%a" "$f")
    if [ "$perms" != "600" ]; then
      echo "WARN: $f tiene permisos $perms (debería ser 600)"
      chmod 600 "$f"
    else
      echo "OK: $f (600)"
    fi
  fi
done
```

## Verificar ausencia en git

```bash
for r in ~/ai-lab/repos/*/; do
  [ -d "$r/.git" ] || continue
  FOUND=$(git -C "$r" ls-files | grep -E '\.env$|\.apikey$' | grep -v example)
  if [ -n "$FOUND" ]; then
    echo "ALERTA: secrets en repo $r:"
    echo "$FOUND"
  fi
done
```
