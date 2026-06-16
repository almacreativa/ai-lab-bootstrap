# Workflows de operación

Los flujos de trabajo del lab una vez instalado. Arquitectura en
[`KNOWLEDGE_MANAGEMENT.md`](KNOWLEDGE_MANAGEMENT.md) · problemas en
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## 1. Instalación inicial del sistema de conocimiento

Orden probado (cada paso valida antes del siguiente):

```bash
# 1. Estructura
mkdir -p ~/ai-lab/knowledge/{shared/templates,companies}
mkdir -p ~/ai-lab/knowledge/companies/<id8-empresa-primaria>/{deliverables,sessions,wiki}

# 2. Backfill manual de sesiones (30 días, incremental desde entonces)
cd knowledge-pipeline/
python3 claude_code_extract.py --company-id <id8> --since-days 30 \
  --output-dir ~/ai-lab/knowledge/companies/<id8>/sessions/
python3 opencode_extract.py --company-id <id8> --since-days 30 \
  --output-dir ~/ai-lab/knowledge/companies/<id8>/sessions/

# 3. Primera destilación (LLM gratis vía el orquestador) → AGENTS.md + insights.md
#    + patterns.md — y REVISARLOS A MANO (15 min, es la semilla de todo)

# 4. Mem0
cd stacks/mem0 && cp .env.example .env  # completar key del LLM + generar MEM0_API_KEY
docker compose up -d --build && docker exec ollama ollama pull nomic-embed-text
# smoke test en stacks/mem0/README.md (add → search → aislamiento → 401)

# 5. Plugin de wiki en la plataforma de agentes (mounts ro+rw, ver TROUBLESHOOTING)

# 6. Automatización: cron del ingest + monitoreo (Uptime Kuma + push monitor)

# 7. Capas humanas: Outline (stacks/outline/README.md) + NotebookLM + Obsidian/Syncthing

# 8. Sync a Outline (espejo de solo lectura del knowledge)
bash scripts/sync-outline.sh --all
# Crear .outline-collections.env con OUTLINE_<id8>=<collection-uuid> por empresa
```

---

## 2. Semana típica (qué hace el sistema solo y qué hacés vos)

| Cuándo | Automático | Humano |
|--------|-----------|--------|
| Continuo | Agentes leen contexto, escriben su wiki, registran memorias en Mem0 | — |
| c/2 h | Espejo de deliverables por empresa al host | — |
| Domingo madrugada | Ingest semanal por empresa: extrae → destila → actualiza insights/AGENTS.md → sync Outline → notifica Telegram + ping al monitor | Leer la notificación |
| Mensual (~10 min) | — | `nlm-sync.sh <empresa> <cuaderno>` (login fresco primero) |
| Trimestral | — | Auditoría de secrets (permisos + git) y revisión de fuentes |

**Si algo falla, te enterás:** caída de servicio → alerta del monitor; ingest que no
corrió → dead-man's-switch; paso fallido → el script continúa y reporta el error.

---

## 3. Onboarding de una empresa/cliente nueva

El flujo completo con todas las dependencias (el orden importa):

1. **Crear la empresa en la plataforma de agentes** (UI). ⚠️ Si se clona desde otra:
   vaciar los workspaces de los agentes nuevos (heredan archivos de la origen).
2. **Carpetas:** `knowledge/companies/<id8>/{deliverables,sessions,wiki}`
3. **Routing de espejos:** entrada por `issue_prefix` en el script de sync de deliverables
4. **Ingest:** entrada en el `case` del weekly-ingest + línea de cron escalonada (+30-90 min de la anterior)
5. **Mounts:** curado `:ro` + `wiki/` rw anidado, SOLO de esa empresa → recrear server
   y crear su dir compartido de deliverables en el contenedor
6. **Plugin wiki:** configurar su wiki root en el panel de la empresa → health check 3× Yes
7. **Mem0:** solo convención `user_id="company_<id8>"` + documentarla
8. **Wiki pública:** colección `<Empresa>` en Outline + registrar UUID en `.outline-collections.env`
9. **AGENTS.md curado** de la empresa (≤500 palabras) + snippet de contexto en las
   instrucciones de cada agente (leer AGENTS.md / tools wiki_* / Mem0 / nunca credenciales)
10. **Smoke test:** un agente lee su AGENTS.md, escribe en su wiki, guarda una memoria
    — y verificar que la memoria NO aparece buscando desde otro namespace
11. **Diferidos:** cuaderno NLM y push monitor cuando tenga contenido; sandboxes si
    manejará datos sensibles

**Regla de atribución:** las sesiones de los CLIs del host van a la empresa primaria;
el trabajo para otras empresas se etiqueta `[company:<id8>]` en la sesión.

---

## 4. Ingest manual / re-proceso puntual

```bash
# Corrida completa de una empresa (idéntica al cron):
bash scripts/weekly-ingest.sh <id8>

# Ver el resultado:
tail -30 ~/ai-lab/logs/ingest-<id8>.log
ls -lt ~/ai-lab/knowledge/companies/<id8>/sessions/ | head

# Re-procesar una fuente específica: borrar su entrada en el .processed.yaml
# correspondiente y re-correr (NUNCA borrar el yaml entero: reprocesa todo).
```

---

## 5. Mantenimiento del conocimiento (salud de la información)

- **Una sola dirección de escritura:** solo el pipeline escribe el knowledge curado.
  Los agentes escriben en su `wiki/`. Si encontrás contenido curado que nadie
  escribió por pipeline → algo está mal montado (revisar `:ro`).
- **Outline es espejo automático** — `sync-outline.sh` replica knowledge, deliverables
  y docs con jerarquía completa. No se edita en Outline; se corrige en el filesystem.
- **insights.md es acumulativo con pesos** — los insights repetidos suben (`visto ×N`);
  no borrar, corregir con nota de fecha (el historial de correcciones también enseña).
- **AGENTS.md ≤500 palabras siempre** — si crece, mover detalle a patterns/runbooks.
- **Cross-check mensual:** preguntar a la capa de consulta natural algo que sepas la
  respuesta; si responde mal, la fuente está desactualizada → re-sync.
