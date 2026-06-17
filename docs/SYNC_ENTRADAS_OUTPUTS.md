# Sistema de Entradas y Outputs por Empresa

> **Patrón:** el operador deja archivos en `entradas/` → los agentes reciben una tarea → producen trabajo → el resultado aparece en `outputs/`. Sin UI. Sin intervención manual.

---

## 1. Qué resuelve

Cada empresa en Paperclip tiene agentes trabajando, pero sin este sistema el flujo de comunicación operador ↔ agentes es manual: crear issues a mano, revisar workspaces dispersos, no saber qué produjo cada agente.

Este sistema crea un contrato claro:

```
OPERADOR                                   AGENTES
    │                                          │
    │  cp plan.md ~/knowledge/empresa/entradas/│
    │ ─────────────────────────────────────── ▶│  Issue creada automáticamente
    │                                          │  CEO lee el plan, delega, trabaja
    │                                          │
    │◀ ─────────────────────────────────────── │  outputs/<Agente>/resultado.md
    │  ver ~/knowledge/empresa/outputs/         │
```

**Canal adicional:** si la empresa tiene un repo GitHub, los colaboradores externos pueden subir archivos a `repo/entradas/` via `git push` y entran al mismo pipeline.

---

## 2. Arquitectura

```
~/ai-lab/
├── knowledge/
│   └── <empresa>/
│       ├── entradas/     ← inbox: operador deja input aquí
│       └── outputs/      ← outbox: agentes escriben aquí (via sync)
│
├── stacks/
│   └── sync-config/
│       └── <empresa>.json  ← config por empresa
│
└── scripts/
    └── sync-company.sh     ← script genérico (un proceso para todas)
```

El script `sync-company.sh <slug>` corre en cron cada 30 minutos y hace:

1. **Pull del repo** (si está configurado) → detecta commits externos → crea issue si hay nuevos
2. **Sync repo/entradas/ → host/entradas/** (si tiene repo)
3. **Sync entradas/ host → contenedor** (knowledge/entradas/)
4. **Detecta archivos nuevos en entradas/** → valida → crea issue en Paperclip
5. **Sync workspaces → outputs/** (copia directa del contenedor al host)
6. **Sync outputs/ → repo/produccion/** + git push (si tiene repo, sin --delete)

---

## 3. Setup — empresa nueva

### 3.1 Crear la estructura de carpetas

```bash
mkdir -p ~/ai-lab/knowledge/<slug>/{entradas,outputs}
mkdir -p ~/ai-lab/stacks/sync-config/
```

### 3.2 Crear el config JSON

Copiar la plantilla y completar con los valores reales de Paperclip:

```bash
cp templates/sync-config.example.json \
   ~/ai-lab/stacks/sync-config/<slug>.json
```

Editar el archivo. Los valores necesarios se obtienen así:

```bash
# Company ID y Project ID
docker exec paperclip-db-1 psql -U paperclip -d paperclip \
  -c "SELECT c.name, c.id, c.issue_prefix, p.id as project_id
      FROM companies c JOIN projects p ON p.company_id = c.id
      WHERE c.name = 'NombreEmpresa';"

# Agent IDs
docker exec paperclip-db-1 psql -U paperclip -d paperclip \
  -c "SELECT name, id FROM agents
      WHERE company_id = 'TU_COMPANY_ID';"
```

**Campo `slug`**: nombre corto, sin espacios, en minúsculas. Usado como identificador en logs y rutas.

**Campo `knowledge_host_path`**: ruta absoluta a `~/ai-lab/knowledge/<slug>`.

**Campo `container_knowledge_path`**: siempre sigue el patrón:
```
/paperclip/instances/default/companies/<company_id>/knowledge
```

**Campo `wiki_container_path`**: los primeros 8 caracteres del `company_id`:
```
/paperclip/knowledge/companies/<primeros-8-chars>/wiki
```

**Campo `entradas_routing`**: define a qué agente llega cada entrada. Por defecto va al CEO. Se pueden agregar reglas por keyword en el nombre del archivo:
```json
"rules": [
  { "keyword": "contenido", "agent_id": "UUID_AGENTE_CONTENIDO" }
]
```

### 3.3 Agregar al crontab

```bash
crontab -e
```

Agregar (escalonar las empresas para evitar conflictos en Docker):

```cron
# Empresa 1 (minutos 0 y 30)
*/30 * * * * /home/USER/ai-lab/scripts/sync-company.sh empresa1 >> /home/USER/ai-lab/logs/sync-empresa1.log 2>&1

# Empresa 2 (minutos 5 y 35)
5,35 * * * * /home/USER/ai-lab/scripts/sync-company.sh empresa2 >> /home/USER/ai-lab/logs/sync-empresa2.log 2>&1

# Empresa 3 (minutos 10 y 40)
10,40 * * * * /home/USER/ai-lab/scripts/sync-company.sh empresa3 >> /home/USER/ai-lab/logs/sync-empresa3.log 2>&1
```

### 3.4 (Opcional) Conectar a un repo de GitHub

Si la empresa colabora con un equipo externo via GitHub:

**Editar el config**, cambiar `repo.enabled` a `true` y completar:

```json
"repo": {
  "enabled": true,
  "host_path": "/home/USER/dev/mi-repo",
  "branch": "main",
  "bot_authors": ["tubot@users.noreply.github.com"],
  "sync_entradas_from_repo": true,
  "produccion_from_workspaces": true,
  ...
}
```

**Crear la carpeta `entradas/` en el repo** con un README explicativo:

```bash
mkdir -p ~/dev/mi-repo/entradas
```

Crear `entradas/README.md` con instrucciones para el equipo (ver sección 5).

```bash
cd ~/dev/mi-repo
git add entradas/
git commit -m "feat: agrega carpeta entradas/ para input de agentes"
git push
```

---

## 4. Uso diario

### Como operador (directo en el host)

```bash
# Dejar un plan para los agentes
cp mi-plan.md ~/ai-lab/knowledge/empresa/entradas/

# Los agentes lo verán en el próximo ciclo (≤30 min)
# Para ejecución inmediata:
bash ~/ai-lab/scripts/sync-company.sh empresa
```

**Formato recomendado para el nombre del archivo:**
```
YYYY-MM-DD-descripcion-breve.md
```

El contenido puede ser libre — el agente lee el archivo completo.

### Como colaborador externo (via GitHub)

Si la empresa tiene repo habilitado:

```bash
# Clonar el repo
git clone https://github.com/tu-org/mi-repo

# Crear un archivo en entradas/
echo "# Plan de julio" > entradas/2026-07-01-plan-julio.md

# Push — el sync lo detecta en el próximo ciclo
git add entradas/2026-07-01-plan-julio.md
git commit -m "plan: objetivos de julio para los agentes"
git push
```

### Leer los outputs

```bash
# Ver qué produjeron los agentes
ls ~/ai-lab/knowledge/empresa/outputs/

# Estructura:
# outputs/CEO/
# outputs/CSO/
# outputs/Analyst/
# outputs/wiki/        ← wiki del LLM
# outputs/deliverables/ ← directorio de deliverables (si aplica)
```

Si la empresa tiene repo, los outputs también aparecen en `repo/produccion/` en GitHub.

---

## 5. README sugerido para `repo/entradas/`

Crear `entradas/README.md` en el repo público con este contenido (adaptar según el proyecto):

```markdown
# Entradas — Input para los agentes de [Nombre Empresa]

Esta carpeta es el canal de comunicación del equipo con los agentes IA.

## Cómo usarla

1. Sube un archivo `.md` o `.txt` a esta carpeta
2. El sistema lo detecta automáticamente (~30 min) y crea una tarea para los agentes
3. Los resultados aparecen en `produccion/`

## Tipos de archivos

- Planes de trabajo
- Briefs de contenido
- Feedback sobre trabajo previo
- Investigaciones o datos externos
- Instrucciones de ajuste

## Reglas

- Solo `.md` y `.txt`, máximo 50 KB
- Nombre sugerido: `YYYY-MM-DD-descripcion.md`
- No borrar archivos — son el historial de input
```

---

## 6. Guardrails — qué se valida antes de crear una issue

Cada archivo en `entradas/` pasa por validación antes de generar una tarea:

| Validación | Regla | Si falla |
|------------|-------|----------|
| Extensión | Solo `.md` o `.txt` | Archivado como "blocked" en el manifest |
| Tamaño | Máximo 50 KB | Mismo que arriba |
| Patrones destructivos | `rm -rf`, `docker exec`, `sudo`, `eval(` | Mismo |
| Inyección de prompt | `ignora tus instrucciones`, `forget everything`, `<system>`, etc. | Mismo |

Los archivos bloqueados se registran en `.state/<slug>-entradas.json` con `"status": "blocked"` y no se reintentan (evita loops). El operador puede revisarlos manualmente.

---

## 7. Protección de ediciones humanas en `produccion/`

El sync usa un **manifest de hashes** (`.state/<slug>-produccion-manifest.json`) para detectar si un humano modificó un archivo en `produccion/` desde el último sync.

**Lógica:**

| Caso | Acción |
|------|--------|
| Archivo nuevo del agente | Copiar a produccion/ |
| Agente actualizó, humano no tocó | Copiar (agente gana) |
| Humano editó, agente no actualizó | **Proteger** (human wins) |
| Ambos modificaron distinto | **Proteger** (humano gana, se loguea conflicto) |

El log del sync reporta qué archivos fueron protegidos en cada ciclo:
```
[2026-06-17 08:24:39] [empresa] Protegidos 2 archivos con ediciones humanas en produccion/:
[2026-06-17 08:24:39] [empresa]   → CEO/plan-trabajo.md
[2026-06-17 08:24:39] [empresa]   → CSO/analisis-mercado.md
```

---

## 8. Monitoreo y troubleshooting

### Ver logs en tiempo real

```bash
tail -f ~/ai-lab/logs/sync-empresa.log
```

### Ver el manifest de entradas procesadas

```bash
cat ~/ai-lab/knowledge/.state/empresa-entradas.json
```

### Forzar procesamiento de un archivo (si el hash cambió)

Borrar la entrada del manifest y re-correr:
```bash
# Eliminar del manifest
python3 -c "
import json
m = json.load(open('$HOME/ai-lab/knowledge/.state/empresa-entradas.json'))
del m['nombre-archivo.md']
json.dump(m, open('$HOME/ai-lab/knowledge/.state/empresa-entradas.json','w'), indent=2)
"
bash ~/ai-lab/scripts/sync-company.sh empresa
```

### La issue no se creó pero el archivo está en entradas/

1. Revisar el manifest: ¿está con `"status": "blocked"`?
   ```bash
   cat ~/ai-lab/knowledge/.state/empresa-entradas.json | python3 -m json.tool | grep -A3 "mi-archivo"
   ```
2. Revisar el log del sync para el mensaje de GUARDRAIL
3. Si fue bloqueado por error, eliminar del manifest y re-correr

### El sync pisó ediciones en `produccion/`

El manifest de produccion/ está vacío o desactualizado. Restaurar desde git e inicializar:
```bash
cd ~/dev/mi-repo
git checkout HEAD -- produccion/archivo-afectado.md
git commit -m "fix: restaura edición manual pisada por sync"
git push
# El siguiente sync inicializará el manifest correctamente
```

### Agregar una empresa nueva sin reiniciar el cron

El script es stateless — agregar el config JSON y la entrada en el crontab es suficiente. No requiere reiniciar ningún servicio.

---

## 9. Referencia de archivos de estado

| Archivo | Contenido |
|---------|-----------|
| `~/ai-lab/knowledge/.state/<slug>-entradas.json` | Hash de cada archivo procesado en entradas/ |
| `~/ai-lab/knowledge/.state/<slug>-produccion-manifest.json` | Hash de lo que sync escribió en produccion/ |
| `~/ai-lab/knowledge/.state/<slug>-last-commit.txt` | Último commit procesado del repo (para detectar externos) |

Todos estos archivos se crean automáticamente en el primer sync. No requieren setup manual.

---

## 10. Antes de correr el script por primera vez

Editar las constantes al inicio de `sync-company.sh`:

```bash
CONTAINER="paperclip-server-1"    # verificar con: docker ps
DB_CONTAINER="paperclip-db-1"     # verificar con: docker ps
CONFIG_DIR="${HOME}/ai-lab/stacks/sync-config"
STATE_DIR="${HOME}/ai-lab/knowledge/.state"
LOG_DIR="${HOME}/ai-lab/logs"
SYNC_AUTHOR="Tu Nombre <bot@tuorganizacion.com>"  # autor de los commits automáticos
```

O bien, usar la variable de entorno `PCSYNC_AUTHOR` para no editar el script:

```bash
export PCSYNC_AUTHOR="Mi Bot <bot@miempresa.com>"
bash ~/ai-lab/scripts/sync-company.sh empresa
```
