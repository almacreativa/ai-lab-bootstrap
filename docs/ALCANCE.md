# Alcance del Lab Base

> **Estado: BORRADOR** — pendiente de cierre junto con la integración de
> Odysseus. Este documento define hasta dónde llega el bootstrap público
> (el "lab base") y cómo se maneja todo lo que queda fuera.

## Principio

El lab base es un producto con alcance **cerrado**: llega hasta un punto
operacional definido y ahí termina. No crece indefinidamente. Las evoluciones
profundas posteriores no entran al bootstrap — viven como personalizaciones
de instancia o como recetas paralelas opcionales.

Esto separa dos fases de trabajo distintas:
1. **Construcción del lab base** (esta fase, en cierre) — el bootstrap recibe
   features hasta declarar la v1.0.
2. **Personalización de laboratorios** (fase siguiente) — cada instancia
   evoluciona en su repo privado; el bootstrap solo recibe fixes.

## Qué cubre el lab base (dentro del alcance)

| Capa | Componentes |
|---|---|
| Infraestructura | Docker, Tailscale, systemd services, UFW, cadena de boot |
| Stacks core | Dagu, Glance, Uptime Kuma, SearXNG, Portainer, Paperclip, Mem0, Odysseus |
| Agentes | Hermes, Claude Code, OpenCode + MCPs genéricos (Dagu, MoolMesh, Playwright, NotebookLM, Paperclip por empresa) |
| Operación | Guards + manifiesto, backup restic→B2, health-check, watchdogs, post-reboot, aggregator de Glance |
| Conocimiento | knowledge/ hub, knowledge-pipeline (extractores), sync-company (entradas/outputs), weekly-ingest, skills de KM |
| Ciclo de vida | Bootstrap multi-OS (Linux/macOS/Windows), onboarding de empresa, import/rehome para migraciones |

**Criterio de inclusión** (ver `scripts/README.md`): es corazón del
funcionamiento del laboratorio — salud, comunicación entre componentes,
infraestructura general. Le sirve a cualquier instancia sin editar más que
el `.env`.

## Qué queda explícitamente fuera

- **Casos de uso de empresas**: scripts, prompts, configs o integraciones
  atados a una empresa concreta. Nunca entran, ni siquiera como ejemplo con
  datos reales.
- **Integraciones en evaluación**: proveedores o herramientas en período de
  prueba (p. ej. proxies de modelos pagos) hasta que se decida su adopción.
- **Skills de agentes** que no sean de knowledge management: son
  personalización natural de cada instancia.
- **Contenido**: knowledge/, memorias, deliverables, sesiones — eso viaja
  por Syncthing y backup, no por git.

## Cómo entran las cosas después del cierre (v1.0)

| Tipo de cambio | Destino |
|---|---|
| Bug fix del lab base | Bootstrap (patch release) |
| Mejora de un script core surgida en una instancia | Genericización deliberada al bootstrap (decisión manual, minor release) |
| Evolución profunda / feature nueva | **Receta paralela** (`recipes/<nombre>/`, opt-in post-bootstrap) o personalización en el repo privado de la instancia |
| Nueva empresa, nuevo cron, nuevo MCP de instancia | Repo privado de la instancia (espejo vía sync-from-live) |

Una **receta** es un módulo opcional autocontenido que se ejecuta después del
bootstrap: instala algo que no toda instancia necesita, con su propia doc y
su propia verificación. El lab base no depende de ninguna receta.

## Condiciones de cierre de la fase de construcción

- [ ] Integración de Odysseus completada (fases 2-6 de su despliegue)
- [ ] Plan de unificación monitoreo/operación implementado (status files + aggregator)
- [ ] Rename del repo privado a nombre agnóstico de hardware
- [ ] Guards 100% verdes en las plataformas soportadas
- [ ] Tag `v1.0.0` en este repo + freeze de features

## Versionado

A partir del freeze: `vMAJOR.MINOR.PATCH`. PATCH = fixes; MINOR =
genericizaciones aceptadas; MAJOR = solo si cambia la arquitectura del lab
base (decisión explícita del operador, no acumulación de features).
