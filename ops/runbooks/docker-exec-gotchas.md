# Docker exec — Trampas conocidas

## -t agrega \r a cada línea

**Síntoma:** SQL dumps contienen `\r\n` en lugar de `\n`. Al restaurar, PostgreSQL falla con errores de sintaxis.

**Causa:** `docker exec -t` asigna un pseudo-TTY que agrega `\r` (carriage return, 0x0d) a cada línea de output.

**Cómo detectar:**
```bash
xxd dump.sql | head -20 | grep '0d 0a'
file dump.sql  # Dirá "CRLF" si está contaminado
```

**Regla:** NUNCA usar `-t` en scripts. Solo usar `-t` cuando se necesita un terminal interactivo.

```bash
# MAL — contamina el output
docker exec -t paperclip-db-1 pg_dumpall -U paperclip > dump.sql

# BIEN — output limpio
docker exec paperclip-db-1 pg_dumpall -U paperclip > dump.sql

# BIEN — para input via pipe
docker exec -i paperclip-db-1 psql -U paperclip < dump.sql
```

**Fix si ya tenés un dump contaminado:**
```bash
sed -i 's/\r$//' dump.sql
```

## -i es necesario para restaurar dumps

Al restaurar un dump vía stdin, se necesita `-i` (stdin interactivo):

```bash
# Sin -i, psql no recibe el input
docker exec -i outline-postgres psql -U outline < dump.sql
```

## Container names en compose

Docker Compose genera nombres con sufijo numérico: `paperclip-server-1`, no `paperclip-server`. El nombre depende del proyecto de compose.

Para encontrar el nombre real:
```bash
docker ps --format '{{.Names}}' | grep paperclip
```
