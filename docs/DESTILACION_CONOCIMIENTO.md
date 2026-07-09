# Patrón: destilación de conocimiento por batería de preguntas

Un patrón de trabajo del lab para convertir **documentación masiva no
estructurada** (años de PDFs, docs, historiales) en **knowledge curado en
markdown**, en minutos y gastando una fracción de los tokens que costaría
procesarla con agentes.

Implementación de referencia: `scripts/nlm-distill.sh` (motor: NotebookLM).

## La idea

```
  Documentación masiva          Motor de conocimiento           Knowledge curado
  (PDFs, docs, años de   ──1──▶  con RAG propio          ──2──▶  (N archivos .md
   historia de una               (NotebookLM, u otro)             con front matter,
   organización)                                                  en el hub)
                                       ▲
                            batería de preguntas
                            (una por tema, con slug)
```

1. **Ingesta delegada**: la documentación se sube a un sistema que ya sabe
   ingerir y indexar (NotebookLM ingiere PDFs/docs nativamente y **gratis** —
   ese trabajo no consume tokens del lab).
2. **Ordeña por preguntas**: un script dispara una batería de preguntas
   curadas — una por dimensión del conocimiento — y guarda cada respuesta
   como un archivo markdown con front matter (fuente, fecha, pregunta).

## Por qué ahorra tokens (la economía del patrón)

| Enfoque | Costo |
|---|---|
| Agentes procesando la doc completa en sesiones | Semanas de heartbeats; CADA token de la doc pasa por el contexto del LLM, posiblemente varias veces |
| **Destilación** | La ingesta la paga el motor (NotebookLM: $0); el lab solo paga N preguntas × 1 respuesta. La doc de años nunca toca tu presupuesto de tokens |

Además el resultado es **mejor**: respuestas sintéticas con la doc completa
como contexto (RAG del motor), no lecturas parciales de un agente con ventana
limitada.

## Anatomía de una batería de preguntas

Archivo de texto plano; `## slug` nombra el archivo de salida, las líneas
siguientes son la pregunta:

```
## vision-y-valor
¿Qué es esta organización, cuál es su propuesta de valor central y qué
problema resuelve? Incluye su filosofía o principios rectores.
## clientes-mercado
¿Quiénes son los clientes e implementaciones, en qué verticales, y qué
resultados se obtuvieron?
```

Principios para diseñar baterías:
- **Una pregunta por dimensión** (visión, productos, clientes, metodología,
  decisiones, glosario) — no preguntas ómnibus.
- **Pedir estructura en la pregunta** ("detalla fases, tiempos y entregables")
  — la respuesta nace lista para ser knowledge.
- **Incluir siempre un glosario** ("terminología propia con definición") —
  es lo que hace que un agente nuevo hable el idioma del dominio.
- La batería default de onboarding vive en el script; para dominios
  específicos, pasar un archivo propio.

## Contrato del patrón (para construir variantes)

Toda implementación de destilación debe cumplir:

1. **Entrada**: identificador del destino (empresa/dominio) + fuente
   (cuaderno, colección, índice) + batería de preguntas (opcional, con default).
2. **Salida**: un `.md` por pregunta con **front matter** (`source`,
   `question`, `date`, destino) + un `index.md` — directo al hub
   (`knowledge/...`), respetando el contrato de carpetas (`KNOWLEDGE_HUB.md`).
3. **Ritmo**: pausa entre consultas (rate limit / cortesía con el motor).
4. **Cierre humano**: el output es *semilla* de knowledge — requiere revisión
   humana breve (~15 min) antes de considerarse fundacional, y avisar a los
   agentes (AGENTS.md) si lo es.
5. **Gatillado por humano** (herramienta `manual` en el manifiesto): la
   destilación es un acto de onboarding deliberado, no un cron.

## Variantes del patrón (mismo contrato, otro motor)

| Motor | Cuándo | Cómo |
|---|---|---|
| **NotebookLM** (implementado: `nlm-distill.sh`) | Doc externa masiva, PDFs, onboarding de empresa | vía NLM Gateway (`:8770`), cuaderno allowlisted por empresa |
| **ChromaDB de Odysseus** (futuro) | Destilar el propio hub: "¿qué sabemos ya sobre X?" | el índice ya existe (`127.0.0.1:8100`, embeddings `all-MiniLM-L6-v2`); consultar + sintetizar con un modelo free |
| **Otro RAG** (futuro) | Fuentes con su propio store (pgvector, etc.) | mismo contrato: batería → respuestas → markdown al hub |

## Uso de la implementación de referencia

```bash
# Batería default de onboarding (6 dimensiones):
bash nlm-distill.sh <company_id8> <alias_cuaderno>

# Batería propia:
bash nlm-distill.sh <company_id8> <alias_cuaderno> mis-preguntas.txt
```

Requisitos: NLM Gateway corriendo y el cuaderno allowlisted para la empresa
en `notebooks.yaml`. Salida: `knowledge/companies/<id8>/research/<alias>-<slug>.md`.
