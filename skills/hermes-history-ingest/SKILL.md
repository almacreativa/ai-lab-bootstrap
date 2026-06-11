---
name: hermes-history-ingest
description: "Destila sesiones de Hermes en conocimiento estructurado, clasificando lab vs empresa."
version: 1.0.0
author: AI Lab
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [knowledge-management, ingest, destilacion, sesiones]
    category: knowledge
    related_skills: [wiki-ingest]
---

# Hermes History Ingest

Procesa las sesiones de Hermes (`~/.hermes/sessions/*.jsonl`) y destila su contenido
en conocimiento estructurado, **clasificando cada sesión** entre administración del lab
(privado de Hermes) y trabajo para una empresa (knowledge compartido de esa empresa).

Forma parte del pipeline definido en `~/shared/demos/knowledge-management-execution-plan.md`.

## Cuándo se activa

- El usuario o un script pide "ejecutá el skill hermes-history-ingest"
- El ingest semanal (`weekly-ingest.sh`) lo invoca vía `hermes chat`

## Parámetros (en el prompt de invocación)

- **Ventana temporal:** por defecto últimos 7 días; el invocador puede pedir otra (ej: "últimos 30 días")
- **Registro de empresas:** hoy `<company-id>` = <Empresa A>. Si aparecen empresas nuevas, el invocador las nombra.

## Estado incremental — OBLIGATORIO

Estado en `~/ai-lab/knowledge/.state/hermes.processed.yaml`:

```yaml
version: 1
last_run: 2026-06-11T18:00:00Z
sources:
  hermes:
    files:
      - id: "20260611_063000_ab12cd34"   # nombre del archivo sin .jsonl
        hash: "a1b2c3d4"                  # sha del tamaño+mtime
        processed_at: "..."
        output: "companies/<company-id>/sessions/hermes-2026-06-11.md"
```

**Procedimiento:** leer el estado primero. Procesar SOLO archivos de sesión que no
figuren en `files` (o cuyo hash cambió). Al terminar, actualizar el estado. Si no hay
sesiones nuevas, reportar "0 sesiones nuevas" y terminar — no releer nada.

## Clasificación lab vs empresa (regla dual)

1. **Etiqueta explícita (prioridad):** si la sesión contiene `[company:<id>]` en el
   título o en los primeros mensajes → pertenece a esa empresa.
2. **Inferencia por contenido (fallback):** sin etiqueta, clasificar por rúbrica:
   - **Lab admin:** configuración del servidor, Docker, providers, Hermes/gateway,
     instalación de herramientas, debugging de infraestructura, monitoreo, backups.
   - **Empresa:** deliverables, clientes, proyectos, contenido producido, decisiones
     de producto/negocio de esa empresa.
   - **Mixta:** separar los insights ítem por ítem; cada insight va a su destino.

## Salidas

**Trabajo de empresa** → `~/ai-lab/knowledge/companies/<id>/sessions/hermes-YYYY-MM-DD.md`
- Con frontmatter YAML: `source: hermes`, `company_id`, `date`, `model`, `topics`, `session_id`
- Si ya existe el archivo de esa fecha, AGREGAR una sección, no sobrescribir
- Actualizar `index.md` del directorio (tabla: Fecha | Fuente | Sesión | Temas clave | Archivo)

**Lab admin** → AGREGAR a `~/.hermes/memories/lab-insights.md` bajo un heading con la fecha.
Este archivo es PRIVADO de Hermes: nunca copiarlo a `~/ai-lab/knowledge/` ni a Outline.

**Insights acumulativos** → `companies/<id>/sessions/insights.md`:
- Antes de agregar un insight, revisar el archivo: si ya existe uno equivalente,
  no duplicar — marcarlo con `(visto ×N)` incrementando el contador (los insights
  recurrentes pesan más).
- Máximo 10 insights por sesión procesada. Cada insight: una línea con el qué + el porqué.

## Reglas de seguridad

- NUNCA copiar credenciales, tokens, API keys o passwords al output. Si una sesión
  los contiene, reemplazar por `[REDACTADO]`.
- No volcar transcripts completos: destilar (decisiones, aprendizajes, problemas
  resueltos, comandos útiles), no transcribir.

## Reporte final

Al terminar, responder con un resumen: sesiones procesadas, sesiones ignoradas
(ya en estado), insights nuevos por destino (lab / por empresa), archivos escritos.
