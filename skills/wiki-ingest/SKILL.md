---
name: wiki-ingest
description: "Destila deliverables de Paperclip en patrones reutilizables por empresa."
version: 1.0.0
author: AI Lab
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [knowledge-management, ingest, deliverables, patrones]
    category: knowledge
    related_skills: [hermes-history-ingest]
---

# Wiki Ingest — Deliverables

Procesa los deliverables producidos por Paperclip y destila **patrones reutilizables**
en el knowledge de la empresa correspondiente. No copia los deliverables: extrae las
estructuras, tipos y convenciones que se repiten.

Forma parte del pipeline definido en `~/shared/demos/knowledge-management-execution-plan.md`.

## Cuándo se activa

- El usuario o un script pide "ejecutá el skill wiki-ingest sobre <directorio>"
- El ingest semanal (`weekly-ingest.sh`) lo invoca vía `hermes chat`

## Parámetros (en el prompt de invocación)

- **Directorio fuente:** por defecto `~/ai-lab/ops/deliverables/<empresa-a>-deliverables/`
- **company_id:** por defecto `<company-id>` (<Empresa A>)

## Estado incremental — OBLIGATORIO

Estado en `~/ai-lab/knowledge/.state/deliverables-<company_id>.processed.yaml`, mismo
formato que hermes-history-ingest (id = ruta relativa del archivo, hash = sha del
tamaño+mtime). Procesar SOLO archivos nuevos o modificados. Si no hay nada nuevo,
reportar "0 deliverables nuevos" y terminar.

## Qué destilar

1. **Tipología:** identificar los 5-10 tipos de deliverable más producidos
   (ej: análisis de mercado, calendario de contenidos, brief creativo). Las carpetas
   por rol (`CEO/`, `CSO/`, `Analyst/`) y los nombres de archivo ayudan a tipificar.
2. **Estructura por tipo:** secciones típicas, extensión, tono, formato de metadatos.
3. **Convenciones transversales:** cómo se titulan, cómo se versionan, qué metadata llevan.
4. **Ejemplares de referencia:** para cada tipo, 1-2 rutas a los mejores ejemplos
   (referenciar la ruta, NO copiar el contenido).

## Salidas

`~/ai-lab/knowledge/companies/<id>/patterns.md` — actualizar (no sobrescribir):
- Una sección `## <Tipo de deliverable>` por tipo, con: estructura típica, cuándo se
  usa, rutas de ejemplares, y contador `(ejemplares: N)` actualizado en cada corrida.
- Frontmatter YAML: `source: paperclip`, `company_id`, `date`, `topics: [patrones, deliverables]`.

`~/ai-lab/knowledge/companies/<id>/deliverables/` — opcional: notas breves por tipo si
un tipo amerita documentación extensa (>10 ejemplares).

## Reglas

- NUNCA copiar credenciales o datos sensibles de clientes al knowledge.
- Patrones, no contenido: el objetivo es que un agente nuevo sepa CÓMO se hace un
  deliverable de cada tipo, no leer los deliverables viejos.
- Máximo ~2000 palabras en patterns.md — si crece más, mover detalle a `deliverables/`.

## Reporte final

Resumen: deliverables nuevos procesados, tipos identificados, secciones de
patterns.md actualizadas.
