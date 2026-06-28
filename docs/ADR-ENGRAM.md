# ADR: Engram como memoria compartida de proyecto para agentes de desarrollo

**Fecha:** 2026-06-13
**Actualizado:** 2026-06-28
**Estado:** Implementado — correccion de permisos y Memory Protocol aplicados
**Cuaderno de investigacion:** NotebookLM `<NLM_NOTEBOOK_ID>`

---

## 1. Problema que resuelve

Hoy hay **5 sesiones de Claude Code corriendo simultaneamente** en el servidor.
Cuando una sesion descubre un bug, toma una decision arquitectonica o aprende un
patron del codebase, ese conocimiento **muere con la sesion**. La siguiente sesion
(del mismo agente o de otro) arranca de cero.

Cada agente tiene su propia isla de memoria:

| Agente | Donde guarda | Quien lo lee |
|--------|-------------|-------------|
| Claude Code | `.claude/projects/.../memory/` | Solo Claude Code |
| OpenCode | Contexto en `opencode.jsonc` | Solo OpenCode |
| Antigravity | `~/.gemini/` state | Solo Antigravity |

No existe un canal compartido a nivel de **proyecto de codigo** donde todos los
agentes depositen y consulten aprendizajes.

### Que NO resuelve (y no debe)

- **Memoria de empresa** -> eso es Mem0 (`company_<COMPANY_UUID_1>`, `company_<COMPANY_UUID_3>`)
- **Directivas estaticas** -> eso es CLAUDE.md / AGENTS.md
- **Conocimiento historico profundo** -> eso es NLM Gateway + cuadernos
- **Destilacion semanal** -> eso es el pipeline KM (`weekly-ingest.sh`)

Engram ocupa una capa que HOY esta vacia: **memoria dinamica del proyecto,
compartida entre agentes, que sobrevive entre sesiones**.

---

## 2. Evaluacion del entorno actual

### 2.1 Recursos del servidor

| Recurso | Estado | Impacto de Engram |
|---------|--------|-------------------|
| **RAM** | 16GB total, ~10GB disponible | ~5-15MB por sesion stdio. **Despreciable.** |
| **Disco** | 98GB, 23GB libres (76%) | Binario: ~7MB. DB SQLite por proyecto: KB-MB. **Despreciable.** |
| **CPU** | x86_64 | Binario precompilado disponible para linux_amd64. |
| **Puertos** | 7437 (default Engram HTTP) libre | Solo si se usa `engram serve`. En modo stdio MCP **no usa puertos**. |

### 2.2 Agentes instalados y compatibilidad MCP

| Agente | Instalado | Soporta MCP | Estado MCP actual | Engram setup |
|--------|-----------|-------------|-------------------|--------------|
| **Claude Code** | `~/.local/bin/claude` | stdio | `mcpServers: {}` (vacio) | `engram setup claude` o manual en settings.json |
| **OpenCode** | `~/.opencode/bin/opencode` | stdio | 1 MCP (notebooklm-mcp) | `engram setup opencode` |
| **Antigravity** CLI | `~/.gemini/` | stdio (fork de Gemini CLI) | Sin MCP | Config manual |
| **Codex** | No instalado | stdio | N/A | Aplica cuando se instale |

---

## 3. Arquitectura propuesta

### 3.1 Modo de operacion: stdio (NO serve)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Claude Code │     │  OpenCode   │     │ Antigravity │
│  sesion 1   │     │  sesion 1   │     │  sesion 1   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │ stdio             │ stdio             │ stdio
       ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ engram mcp  │     │ engram mcp  │     │ engram mcp  │
│ (proceso    │     │ (proceso    │     │ (proceso    │
│  efimero)   │     │  efimero)   │     │  efimero)   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────┬───────┘───────────────────┘
                   ▼
           ┌──────────────┐
           │  ~/.engram/  │
           │  engram.db   │  ← SQLite con FTS5
           │  (una sola   │    (WAL mode = lecturas
           │   instancia) │     concurrentes OK)
           └──────────────┘
```

**Por que stdio y no serve:**
- No agrega un servicio mas al stack
- No consume RAM cuando ningun agente esta activo
- No necesita cron, watchdog, ni monitor
- SQLite en WAL mode maneja concurrencia de lecturas nativamente
- Las escrituras se serializan a nivel de SQLite — para nuestro volumen es suficiente

### 3.2 Scope: una DB global, aislamiento por project_name

Cada repo tiene `.engram/config.json`:

```json
{"project_name": "paperclip"}
```

Repos candidatos:

| Repo | project_name | Justificacion |
|------|-------------|---------------|
| `~/ai-lab/repos/paperclip` | `paperclip` | El mas activo, multiples sesiones |
| `~/ai-lab/repos/<REPO_NAME>` | `<REPO_NAME>` | Documentacion del lab |
| `~/dev/my-app` | `my-app` | Proyecto de desarrollo real |

### 3.3 Mapa de capas de memoria

```
┌─────────────────────────────────────────────────────────┐
│                    CAPA DE EMPRESA                       │
│  Mem0 (company_<COMPANY_UUID_1> / company_<COMPANY_UUID_3>)│
│  Que: identidad, politicas, clientes, procesos          │
├─────────────────────────────────────────────────────────┤
│                    CAPA DE PROYECTO                       │
│  Engram (project_name por repo, SQLite local)            │  ← NUEVA
│  Que: decisiones tecnicas, bugs resueltos, patrones      │
├─────────────────────────────────────────────────────────┤
│                    CAPA DE DIRECTIVAS                     │
│  CLAUDE.md / AGENTS.md (archivos estaticos por repo)     │
├─────────────────────────────────────────────────────────┤
│                CAPA DE CONOCIMIENTO PROFUNDO              │
│  NLM Gateway -> cuadernos NotebookLM por empresa          │
├─────────────────────────────────────────────────────────┤
│                    CAPA DE DESTILACION                    │
│  Pipeline KM (weekly-ingest.sh -> patterns/insights)      │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Analisis de riesgos

### 4.1 Duplicacion de memoria
Mitigacion: Memory Protocol en CLAUDE.md del proyecto.

### 4.2 Corrupcion de SQLite por kill -9
Mitigacion: SQLite en WAL mode es crash-safe por diseno.

### 4.3 Crecimiento descontrolado de la DB
Mitigacion: soft-delete, dedup por hash, topic_key upserts. Revision trimestral con `engram stats`.

### 4.4 Agente no usa Engram
Mitigacion: CLAUDE.md se carga automaticamente. Si un agente lo ignora, no rompe nada.

### 4.5 Go binary y actualizaciones
Mitigacion: binario no se auto-actualiza. DB SQLite tiene migraciones automaticas.

---

## 5. Plan de implementacion

### Fase 1: Instalacion base (5 min)

```bash
curl -sL https://github.com/Gentleman-Programming/engram/releases/latest/download/engram_linux_amd64.tar.gz \
  | tar xz -C ~/.local/bin/ engram
chmod +x ~/.local/bin/engram
engram version
```

### Fase 2: Configurar en Claude Code (2 min)

```json
{
  "mcpServers": {
    "engram": {
      "command": "engram",
      "args": ["mcp", "--tools=agent"]
    }
  }
}
```

### Fase 3: Configurar en OpenCode (2 min)

```json
"engram": {
  "type": "local",
  "enabled": true,
  "command": "engram",
  "args": ["mcp", "--tools=agent"]
}
```

### Fase 4: Configurar en Antigravity (2 min)

Create/edit `~/.gemini/settings.json` to add the MCP.

### Fase 5: Crear CLAUDE.md con Memory Protocol (5 min)

In the pilot repo, create:
- `.engram/config.json` (fixes project_name)
- CLAUDE.md with Memory Protocol

### Fase 6: Smoke test (5 min)

1. `engram save "test" "Primera memoria de prueba"`
2. Open Claude Code in pilot repo
3. Ask: "search your memory for this project"
4. Verify it finds the test memory

---

## 6. Que NO hacer

| Tentacion | Por que no |
|-----------|-----------|
| Arrancar `engram serve` como daemon | No hay agentes remotos. stdio es suficiente. |
| Configurar Engram Cloud | Sincronizacion entre maquinas no necesaria. |
| Conectar Engram al pipeline KM de inmediato | Primero validar que los agentes lo usan. |
| Crear `.engram/config.json` en TODOS los repos | Empezar con 1 repo piloto. |
| Desactivar auto-memory de Claude Code | Claude auto-memory guarda preferencias de usuario. Engram guarda conocimiento de proyecto. Conviven. |

---

## 7. Criterios de exito (2 semanas)

- [ ] `engram stats` muestra >=10 memorias reales
- [ ] Al menos 2 agentes distintos han escrito memorias
- [ ] Una sesion nueva encontro contexto util via `mem_search`
- [ ] `engram doctor` reporta 0 problemas
- [ ] No hubo incidentes de corrupcion
- [ ] El operador puede inspeccionar memorias con `engram tui` en <30 segundos

---

## 8. Costo total

| Concepto | Costo |
|----------|-------|
| Disco | ~7MB (binario) + KB-MB (DB) |
| RAM | 0 en reposo, ~5-15MB por sesion activa |
| Puertos | Ninguno (stdio) |
| Servicios nuevos | Ninguno |
| Crons nuevos | Ninguno |
| Secrets nuevos | Ninguno |
| Dependencias nuevas | Ninguna (binario estatico) |
| Mantenimiento | `engram stats` + `engram doctor` mensual (~2 min) |
| Riesgo de downtime | Nulo |

**Conclusion:** Es la adicion de menor friccion al stack. Si no funciona, se desinstala borrando el binario y `~/.engram/`.

---

## 9. Postmortem: por que Engram no guardaba (2026-06-28)

### Problema
Despues de 2 semanas de uso, Engram tenia muy pocas memorias guardadas a pesar de
multiples sesiones de agentes trabajando activamente.

### Causa raiz (3 factores)

#### 1. Permisos de escritura faltantes en `settings.local.json`
Solo estaban permitidos los tools de **lectura**:
```
mcp__engram__mem_search      ← lectura
mcp__engram__mem_context     ← lectura
mcp__engram__mem_current_project  ← lectura
```
Faltaban TODOS los de escritura (`mem_save`, `mem_session_summary`, `mem_update`,
`mem_judge`, etc.). Cada intento de guardar generaba un prompt de permisos que el
operador ignoraba o rechazaba sin notarlo.

#### 2. Memory Protocol incompleto en CLAUDE.md
El CLAUDE.md del directorio home no tenia instrucciones de Engram. El CLAUDE.md
del repo de documentacion tenia un protocolo basico sin:
- Formato estructurado de `mem_save` (What/Why/Where/Learned)
- Instruccion OBLIGATORIA de `mem_session_summary` al cerrar
- Protocolo de recuperacion post-compactacion
- Reglas de resolucion de conflictos

#### 3. Sin `ENGRAM_PROJECT` en config MCP
La deteccion de proyecto dependia de `cwd`, que desde el directorio home no
apunta a ningun repo. Resultado: proyecto ambiguo o fallback incorrecto.

### Correccion aplicada

| Cambio | Archivo |
|--------|---------|
| +12 permisos de escritura Engram | `~/.claude/settings.local.json` |
| Memory Protocol completo | CLAUDE.md del home y del repo de documentacion |
| `ENGRAM_PROJECT` configurado | `~/.claude/.mcp.json` |

### Permisos que deben estar en el allowlist
```
mcp__engram__mem_save
mcp__engram__mem_save_prompt
mcp__engram__mem_session_summary
mcp__engram__mem_session_start
mcp__engram__mem_session_end
mcp__engram__mem_update
mcp__engram__mem_judge
mcp__engram__mem_capture_passive
mcp__engram__mem_suggest_topic_key
mcp__engram__mem_get_observation
mcp__engram__mem_review
mcp__engram__mem_compare
```

### Config MCP recomendada (`~/.claude/.mcp.json`)
```json
{
  "engram": {
    "command": "engram",
    "args": ["mcp", "--tools=agent"],
    "env": {
      "ENGRAM_PROJECT": "<nombre-del-lab>"
    }
  }
}
```

### Leccion
Al instalar un MCP server, **validar que los tools de escritura esten en el allowlist**.
Los tools de lectura sin escritura dan la ilusion de que el sistema funciona.
