# Ciclo de vida de perfiles

## Qué es un perfil

Un perfil es una configuración desplegable que agrega funcionalidad sobre el core del lab. Ejemplos: DevLab, OpsLab, KnowledgeLab.

Cada perfil vive en `lab-profiles/<nombre>/` y contiene:
- `profile.yaml` — declaración de recursos (servicios, containers, agentes, DAGs)
- `dags/` — DAGs específicos del perfil
- `stacks/` — Docker Compose stacks del perfil
- `configs/` — Configuraciones adicionales

## Estados

```
NO INSTALADO → INSTALADO → ACTIVO → DESACTIVADO → DESINSTALADO
```

### install (NO INSTALADO → INSTALADO)

1. Copiar DAGs del perfil a `~/.config/dagu/dags/`
2. Crear directorio de datos: `~/ai-lab/data/profiles/<nombre>/`
3. Levantar containers: `docker compose up -d`
4. Registrar agentes en Paperclip (si aplica)

### activate (INSTALADO → ACTIVO)

1. Habilitar DAGs (están presentes pero pueden estar deshabilitados)
2. Iniciar containers del perfil
3. Verificar con `profile-guard.sh <nombre>`

### deactivate (ACTIVO → DESACTIVADO)

1. Detener containers del perfil: `docker compose stop`
2. Deshabilitar DAGs del perfil en Dagu
3. Los datos persisten en `~/ai-lab/data/profiles/<nombre>/`

### uninstall (DESACTIVADO → DESINSTALADO)

1. Eliminar containers: `docker compose down`
2. Eliminar DAGs del perfil de `~/.config/dagu/dags/`
3. **Los datos NO se eliminan** — quedan en `data/profiles/<nombre>/`
4. Para eliminar datos: `rm -rf ~/ai-lab/data/profiles/<nombre>/` (manual)

## Dónde persisten los datos

| Tipo | Ubicación | Persiste en uninstall |
|---|---|---|
| Datos del perfil | `~/ai-lab/data/profiles/<nombre>/` | Sí |
| Docker volumes | `docker volume ls` | Sí (hasta `docker volume prune`) |
| DAGs | `~/.config/dagu/dags/` | No (se eliminan) |
| Configs copiados | Depende del perfil | Depende |

## Verificar salud de un perfil

```bash
~/ai-lab/ops/guards/profile-guard.sh <nombre>
```

El guard verifica:
- Servicios core requeridos (running)
- Containers del perfil (running)
- Agentes en Paperclip DB (conteo)
- DAGs instalados

Si el perfil no está instalado, el guard sale con 0 sin error.
