# AI Session Analyzer

Script en Python para procesar y analizar sesiones de multiples agentes de IA (Claude, Codex, Qwen), extrayendo informacion clave y generando reportes organizados.

## Descripcion

Este script procesa sesiones de Claude Code como fuente principal, integrando delegaciones a Codex (GPT-5.4) y actividad paralela de Qwen sobre los mismos proyectos. Genera reportes detallados que incluyen:
- Historico de mensajes del usuario
- Respuestas del sistema
- Pares de preguntas y respuestas
- Operaciones de archivos ejecutadas
- Analisis de flujo de trabajo con contexto tecnico
- **v3.0:** Actividad detallada de subagentes
- **v3.0:** Memoria del proyecto (decisiones, lecciones tecnicas)
- **v3.0:** Tool-results externos (Playwright snapshots, etc.)
- **v3.1:** Reporte de eficiencia y consumo de tokens (por sesion, ranking, modelos)
- **v4.0:** Integracion con Codex CLI (GPT-5.4) — detecta delegaciones, matchea sesiones, enriquece reportes
- **v4.1:** Integracion con Qwen CLI — visibilidad de actividad paralela en el mismo proyecto

## Instalacion

### Requisitos
- Python 3.6 o superior
- Librerias estandar de Python (json, pathlib, datetime, argparse, re)

### Instalacion
```bash
# Clonar o descargar el script
# Solo se necesita el archivo process_sessions.py
```

## Uso

### Uso Basico
```bash
# Procesar archivos JSONL en el directorio actual
python3 process_sessions.py .

# Procesar archivos en un directorio especifico
python3 process_sessions.py /ruta/a/carpeta/con/sesiones/

# Especificar directorio de salida personalizado
python3 process_sessions.py . -o mi_carpeta_reportes
```

### Funcionalidades v2.0
```bash
# Extraer las ultimas 30 conversaciones en archivo separado
python3 process_sessions.py . -o reportes --last 30

# Generar historial completo de modificaciones de un archivo especifico
python3 process_sessions.py . -o reportes --file-history CLAUDE.md

# Combinar ambas funcionalidades
python3 process_sessions.py . -o reportes --last 20 --file-history process_sessions.py
```

### Funcionalidades v3.0 (Subagentes y Memoria)
```bash
# Procesamiento completo (por defecto incluye subagentes, tool-results y memoria)
python3 process_sessions.py . -o reportes

# Omitir procesamiento de subagentes (mas rapido, solo JSONL principales)
python3 process_sessions.py . -o reportes --no-subagents
```

### Funcionalidades v4.0 (Integracion Codex)
```bash
# Integrar delegaciones a Codex CLI (GPT-5.4)
python3 process_sessions.py . -o reportes --codex-dir ~/.codex/
```

### Funcionalidades v4.1 (Integracion Qwen)
```bash
# Incluir actividad paralela de Qwen sobre el mismo proyecto
python3 process_sessions.py . -o reportes --qwen-dir ~/.qwen/

# Combinado completo: Claude + Codex + Qwen
python3 process_sessions.py . -o reportes --codex-dir ~/.codex/ --qwen-dir ~/.qwen/
```

### Ver todas las opciones
```bash
python3 process_sessions.py --help
```

### Estructura de Archivos de Entrada
```
tu-proyecto/
├── process_sessions.py              # El script
├── sesion1.jsonl                    # Archivos de sesiones Claude
├── sesion2.jsonl
├── {uuid-sesion}/                   # Directorio de sesion (v3.0)
│   ├── subagents/                   # Subagentes de la sesion
│   │   ├── agent-aa22126.jsonl
│   │   ├── agent-acompact-d70276.jsonl
│   │   └── ...
│   └── tool-results/                # Resultados de tools externos
│       ├── b06525d.txt
│       ├── mcp-playwright-snapshot-*.txt
│       └── ...
├── memory/                          # Memoria del proyecto (v3.0)
│   ├── MEMORY.md
│   └── technical-notes.md
└── reports/                         # Carpeta generada automaticamente
    ├── 00_resumen_sesiones.md
    ├── 01_historico_mensajes_usuario.md
    ├── 02_respuestas_sistema.md
    ├── 03_preguntas_respuestas.md
    ├── 04_operaciones_archivos.md
    ├── 05_qa_mejorado_con_operaciones.md
    ├── 06_subagentes_detalle.md          # v3.0
    ├── 07_memoria_proyecto.md            # v3.0
    ├── 08_tool_results_externos.md       # v3.0
    ├── 09_eficiencia_tokens.md           # v3.1
    ├── 10_codex_integrado.md             # v4.0 (con --codex-dir)
    ├── 12_qwen_paralelo.md               # v4.1 (con --qwen-dir)
    ├── log_operaciones_archivos.md
    ├── ultimas_N_conversaciones.md       (opcional con --last)
    └── historial_ARCHIVO.md              (opcional con --file-history)
```

### Datos de Codex (fuente externa, v4.0)
```
~/.codex/                            # Directorio de Codex CLI (--codex-dir)
├── state_5.sqlite                   # Indice de threads y metadata
├── session_index.jsonl              # Nombres de companion tasks
└── sessions/                        # Rollouts completos
    └── YYYY/MM/DD/
        └── rollout-{ts}-{thread_id}.jsonl
```
Ver `CODEX_DATA_GUIDE.md` para documentacion detallada del formato.

### Datos de Qwen (fuente externa, v4.1)
```
~/.qwen/                             # Directorio de Qwen CLI (--qwen-dir)
└── projects/
    └── {path-encoded}/              # Mismo encoding que Claude
        └── chats/
            └── {uuid}.jsonl         # Sesiones (formato similar a Claude)
```

## Reportes Generados

### 1. Resumen de Sesiones (`00_resumen_sesiones.md`)
- Estadisticas generales (mensajes, operaciones, Q&A)
- v3.1: Tokens por sesion (input, output, cache creation, cache read)
- v3.1: Modelo principal por sesion
- v3.0: Conteo de subagentes por sesion
- v3.0: Herramientas usadas por subagentes
- v3.0: Modelos de subagentes y uso de tokens
- v3.0: Directorios de sesion detectados
- Herramientas mas utilizadas
- Timeframes de las sesiones

### 2. Historico de Mensajes (`01_historico_mensajes_usuario.md`)
- Todos los prompts del usuario
- Organizados cronologicamente
- Con timestamps y contexto

### 3. Respuestas del Sistema (`02_respuestas_sistema.md`)
- Respuestas cuando se completaron tareas
- Informacion tecnica y confirmaciones
- Modelos utilizados

### 4. Pares Q&A Basicos (`03_preguntas_respuestas.md`)
- Conversaciones completas estructuradas
- Formato pregunta-respuesta

### 5. Operaciones de Archivos (`04_operaciones_archivos.md`)
- Lista de todas las operaciones realizadas
- v3.0: Incluye operaciones de subagentes en seccion separada
- Formato: Operacion | Archivo | Herramienta | Linea

### 6. Q&A Mejorado con Operaciones (`05_qa_mejorado_con_operaciones.md`)
**El reporte mas valioso!**

Para cada pregunta-respuesta incluye:
- Operaciones de archivos ejecutadas durante esa interaccion
- Resumen: Herramientas utilizadas, archivos tocados, total de operaciones
- Detalle por herramienta: Ejemplos especificos de cada operacion
- **v3.0: Subagentes invocados** - Para cada subagente muestra:
  - Modelo utilizado y duracion
  - Tarea asignada (prompt)
  - Herramientas y archivos que toco
  - Uso de tokens

### 7. Detalle de Subagentes (`06_subagentes_detalle.md`) - v3.0
**Nuevo en v3.0!**

Reporte completo de todos los subagentes:
- Estadisticas globales (total, por tipo, tokens, herramientas top)
- Detalle por sesion con todos los subagentes
- Para cada subagente: tarea asignada, herramientas usadas, archivos tocados, resultado
- Deteccion de sesiones compactadas (context window management)

### 8. Memoria del Proyecto (`07_memoria_proyecto.md`) - v3.0
**Nuevo en v3.0!**

Contenido de la carpeta `memory/`:
- Indice de memoria (MEMORY.md)
- Archivos de memoria con sus metadatos (frontmatter)
- Decisiones de proyecto, lecciones tecnicas, preferencias del usuario

### 9. Tool-Results Externos (`08_tool_results_externos.md`) - v3.0
**Nuevo en v3.0!**

Inventario de resultados de tools externalizados:
- Categorizados por tipo (Playwright/Browser, MCP Tools, Otros)
- Tamano de cada archivo
- Preview del contenido

### 10. Eficiencia y Consumo de Tokens (`09_eficiencia_tokens.md`) - v3.1/v4.0
**Nuevo en v3.1!**

Reporte completo de consumo y eficiencia por sesion:
- **Consumo global:** Tabla comparativa sesiones principales vs subagentes (input, output, cache creation, cache read)
- **Cache hit rate:** Porcentaje de reutilizacion de contexto
- **Consumo por sesion:** Tabla con duracion, Q&A, operaciones, tokens main/sub, tokens/Q&A, tokens/operacion
- **Detalle por sesion:** Desglose de tokens, modelos usados, output ratio, cache efficiency
- **Ranking de eficiencia:** Sesiones ordenadas por tokens/Q&A (menor = mas eficiente)
- **Uso de modelos global:** Que modelos se usaron, cuantas veces, tipo (principal/subagent/compaction)

Ideal para:
- Evaluar que sesiones fueron mas costosas y por que
- Comparar eficiencia entre sesiones de desarrollo
- Entender la proporcion de gasto en subagentes vs agente principal
- Medir la efectividad del cache de contexto

### 11. Codex Integrado (`10_codex_integrado.md`) - v4.0
**Nuevo en v4.0! Requiere `--codex-dir`**

Reporte completo de delegaciones Claude → Codex (GPT-5.4):
- **Timeline** de todas las invocaciones a Codex detectadas
- **Detalle por delegacion matcheada:**
  - Tarea completa enviada a Codex (prompt integro)
  - Razonamiento del modelo GPT-5.4 (pasos de pensamiento)
  - Comandos ejecutados con sus outputs
  - Respuestas completas de Codex (no el resumen truncado que Claude recibio)
- **Match scoring:** timestamp + proyecto/CWD + overlap de prompt

### 12. Qwen Paralelo (`12_qwen_paralelo.md`) - v4.1
**Nuevo en v4.1! Requiere `--qwen-dir`**

Reporte de actividad paralela de Qwen CLI sobre el mismo proyecto:
- **Resumen:** Sesiones, mensajes, comandos ejecutados
- **Correlacion temporal:** Dias con actividad simultanea Claude+Qwen
- **Indice de sesiones:** Tabla con fecha, mensajes, comandos, branch
- **Detalle por sesion:**
  - Inputs del usuario
  - Respuestas del modelo (completas)
  - Comandos ejecutados (run_shell_command)
  - Todo intercalado cronologicamente

Util para:
- Ver que investigaba Qwen mientras Claude trabajaba en el mismo proyecto
- Comparar enfoques entre agentes para el mismo problema
- Recuperar analisis o datos que Qwen genero independientemente

### 13. Log de Operaciones CSV (`log_operaciones_archivos.md`)
Log simple compatible con Excel/Google Sheets:
- **Formato**: `Operacion;Ruta;Herramienta;Sesion;Timestamp;Origen`
- v3.0: Columna `Origen` indica si es sesion principal o subagente
- Importable: Usar `;` como separador en hojas de calculo

### 14. Ultimas N Conversaciones (`ultimas_N_conversaciones.md`)
**Generado con `--last N`**
- Extrae las ultimas N conversaciones mas recientes
- v3.0: Incluye subagentes vinculados a cada interaccion

### 15. Historial de Archivo (`historial_ARCHIVO.md`)
**Generado con `--file-history FILENAME`**
- Timeline completo de modificaciones de un archivo especifico
- v3.0: Incluye modificaciones hechas por subagentes

## Que Son los Subagentes

Claude Code utiliza **subagentes** para delegar trabajo en paralelo. Cuando el agente principal invoca la herramienta `Agent`, se crea un subagente que:

- Tiene su propio archivo JSONL en `{session-id}/subagents/`
- Usa su propio modelo (frecuentemente `claude-haiku` para tareas rapidas)
- Ejecuta herramientas independientemente (Read, Write, Bash, Grep, etc.)
- Puede usar MCP tools (Playwright, Shopify, etc.)
- Devuelve resultados al agente principal

**Tipos de subagentes:**
- `Explore` - Investigacion y busqueda en el codebase
- `general-purpose` - Tareas generales
- `technical-writer` - Documentacion
- `codex:codex-rescue` - Delegacion a Codex CLI (GPT-5.4) via OpenAI
- Sesiones `compact` - Subagentes cuyo contexto fue compactado

Sin el procesamiento de subagentes, se pierde entre el **30-60%** de las operaciones reales de una sesion.

## Integracion con Codex (v4.0)

Claude Code puede delegar tareas a **Codex CLI** (OpenAI, modelo GPT-5.4). Cuando esto ocurre:
- Claude registra un `Agent` tool_use con `subagent_type: "codex:codex-rescue"`
- Claude recibe un resumen breve como tool_result (~2-5KB)
- La conversacion completa de Codex (comandos, razonamiento, respuestas) vive en `~/.codex/sessions/`

Con `--codex-dir`, el script:
1. **Detecta** invocaciones a Codex en las sesiones de Claude (Agent, Skill, Bash)
2. **Matchea** cada invocacion a la sesion de Codex correspondiente usando 3 criterios:
   - Proximidad temporal (±120s)
   - Mismo proyecto/CWD
   - Overlap de texto en el prompt
3. **Enriquece** los reportes con el detalle completo de lo que hizo Codex

Ver `CODEX_DATA_GUIDE.md` para documentacion del formato de datos de Codex.

## Integracion con Qwen (v4.1)

Qwen CLI es otro agente de IA que puede trabajar sobre los mismos proyectos que Claude. A diferencia de Codex (que es delegado por Claude), Qwen trabaja de forma **independiente** — no hay handoff automatico.

Con `--qwen-dir`, el script:
1. **Detecta el CWD** del proyecto Claude actual
2. **Busca sesiones de Qwen** del mismo proyecto (usando el mismo encoding de paths)
3. **Parsea las sesiones** extrayendo inputs, respuestas y comandos
4. **Correlaciona temporalmente** — identifica dias con actividad simultanea Claude+Qwen
5. **Genera reporte** `12_qwen_paralelo.md` con el detalle completo

### Formato de datos de Qwen

Qwen usa JSONL similar a Claude pero con diferencias:
- `message.parts` en vez de `message.content`
- `functionCall` / `functionResponse` en vez de `tool_use` / `tool_result`
- `role: "model"` en vez de `role: "assistant"`
- Herramienta principal: `run_shell_command`
- Eventos `type: "system"` con telemetria (se ignoran)

## Opciones de Linea de Comandos

```
usage: process_sessions.py [-h] [-o OUTPUT] [--last LAST]
                           [--file-history FILE_HISTORY] [--no-subagents]
                           [--codex-dir CODEX_DIR] [--qwen-dir QWEN_DIR]
                           input_dir

Argumentos:
  input_dir             Directorio con archivos .jsonl y/o carpetas de sesion
  -o, --output          Directorio de salida para reportes
  --last N              Extraer las ultimas N conversaciones
  --file-history FILE   Generar historial de un archivo especifico
  --no-subagents        No procesar subagentes ni tool-results
  --codex-dir DIR       Directorio de Codex CLI (~/.codex/) para integrar delegaciones
  --qwen-dir DIR        Directorio de Qwen CLI (~/.qwen/) para incluir sesiones paralelas
```

## Caracteristicas Tecnicas

### Deteccion Automatica
- Encuentra todos los archivos `.jsonl` automaticamente
- v3.0: Descubre carpetas de sesion con subagentes y tool-results
- v3.0: Detecta carpeta `memory/` si existe
- v4.0: Detecta invocaciones a Codex por patrones en tool_use
- v4.1: Matchea proyecto Claude con proyecto Qwen por CWD
- Procesa multiples sesiones

### Extraccion Inteligente
- Nombres de archivos limpios (sin rutas largas)
- Deteccion de archivos del proyecto vs. sistema
- Agrupacion por herramientas utilizadas
- v3.0: Vinculacion de subagentes a interacciones Q&A por timestamp
- v3.0: Tracking de token usage por subagente

### Formatos de Salida
- Markdown bien estructurado
- Timestamps precisos
- v3.0: Log CSV con columna de origen (main/subagent)
- Division automatica de archivos >2MB

### Division Automatica de Archivos
- Deteccion automatica de archivos >2MB
- Partes numeradas: `archivo_parte_1.md`, `archivo_parte_2.md`, etc.
- Indice navegable: `archivo_indice.md` con enlaces a todas las partes

### Deteccion de Operaciones
- Git: commit, push, pull, branch, clone, add
- Package Managers: npm, yarn, pip, poetry, conda
- File System: mkdir, cp, mv, rm, touch
- Build & Test: npm/yarn build, pytest, jest, cargo, maven
- Search: grep, find, ripgrep, locate
- v3.0: MCP tools (Playwright, Shopify, Cloudflare, etc.)
- v3.0: Agent invocations (subagent spawning)

## Actualizaciones

### Version 4.1 (Actual)
- Integracion con Qwen CLI via `--qwen-dir`
- Deteccion automatica de sesiones Qwen del mismo proyecto (por CWD)
- Parser de formato Qwen (parts, functionCall/functionResponse, model role)
- Nuevo reporte: `12_qwen_paralelo.md` — actividad paralela con detalle cronologico
- Correlacion temporal: identifica dias con actividad simultanea Claude+Qwen
- Resumen de sesiones enriquecido con estadisticas de Qwen

### Version 4.0
- Integracion con Codex CLI (OpenAI GPT-5.4) via `--codex-dir`
- Deteccion automatica de delegaciones a Codex (Agent, Skill, Bash)
- Matching de sesiones Codex por 3 criterios: timestamp + proyecto/CWD + prompt overlap
- Nuevo reporte: `10_codex_integrado.md` — tareas, comandos, razonamiento y respuestas completas
- Reporte de eficiencia ampliado con columna y tokens de Codex
- Resumen de sesiones enriquecido con estadisticas de Codex
- Q&A mejorado muestra delegaciones a Codex inline
- `CODEX_DATA_GUIDE.md` — documentacion completa del formato de datos de Codex
- `extract_codex_full.py` — script standalone para analisis de Codex puro

### Version 3.1
- Token tracking completo en sesiones principales (input, output, cache creation, cache read)
- Tracking de modelos usados por sesion
- Nuevo reporte: `09_eficiencia_tokens.md` - consumo global, por sesion, ranking de eficiencia
- Metricas de eficiencia: tokens/Q&A, tokens/operacion, cache hit rate, output ratio
- Ranking de sesiones por eficiencia (menor tokens/Q&A = mejor)
- Tabla comparativa sesiones principales vs subagentes
- Uso de modelos global con clasificacion (principal/subagent/compaction)

### Version 3.0
- Procesamiento completo de subagentes (`{session}/subagents/agent-*.jsonl`)
- Lectura de tool-results externos (`{session}/tool-results/*.txt`)
- Analisis de memoria del proyecto (`memory/*.md`)
- Nuevo reporte: `06_subagentes_detalle.md` - estadisticas y detalle por subagente
- Nuevo reporte: `07_memoria_proyecto.md` - decisiones y lecciones tecnicas
- Nuevo reporte: `08_tool_results_externos.md` - inventario de resultados externos
- Subagentes integrados en reportes 05 Q&A mejorado y ultimas N conversaciones
- Resumen de sesiones enriquecido con stats de subagentes, modelos y tokens
- Log CSV con columna de origen (main vs subagent)
- File history incluye modificaciones de subagentes
- Flag `--no-subagents` para procesamiento rapido sin subagentes
- Fix: codigo inalcanzable en `_generate_file_history_report`
- Deteccion de rutas de proyecto mas generica (no hardcodeada)

### Version 2.0
- Division automatica de archivos >2MB con indices navegables
- Log CSV exportable compatible con Excel/Google Sheets
- Deteccion ampliada de operaciones (Git, npm, pip, builds, tests)
- Filtros temporales con `--last N` para ultimas conversaciones
- Historial por archivo con `--file-history` para auditorias
- Timestamps numericos para facil ordenamiento

### Version 1.0 (Base)
- Extraccion mejorada de nombres de archivos
- Reporte Q&A con operaciones de archivos
- Deteccion automatica de herramientas
- Formato Markdown optimizado

## Desarrollado para

Desarrolladores, Project Managers y equipos que:
- Trabajan con multiples agentes de IA (Claude, Codex, Qwen) en los mismos proyectos
- Necesitan documentar procesos de desarrollo asistidos por IA
- Quieren visibilidad completa de lo que hizo cada agente
- Buscan generar reportes tecnicos automaticos
- Necesitan auditar que hicieron los subagentes y agentes externos en cada sesion

---

**Pro Tip**: El reporte `05_qa_mejorado_con_operaciones.md` es el mas valioso — muestra no solo que archivos se tocaron en cada interaccion, sino tambien que hicieron los subagentes invocados y las delegaciones a Codex con sus respuestas completas.

**Pro Tip v4.0**: Con `--codex-dir ~/.codex/`, el reporte `10_codex_integrado.md` muestra TODO lo que hizo Codex: los 35+ comandos que ejecuto, su razonamiento, y la respuesta completa — no solo el resumen de 5KB que Claude recibio de vuelta.

**Pro Tip v4.1**: Con `--qwen-dir ~/.qwen/`, el reporte `12_qwen_paralelo.md` muestra la actividad de Qwen en el mismo proyecto, con correlacion temporal para ver que dias ambos agentes estaban trabajando en paralelo.
