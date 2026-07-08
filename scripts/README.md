# Scripts del lab base

Scripts operativos que instala el bootstrap. Todos leen su configuración de
instancia desde `~/ai-lab/scripts/.env` (ver `.env.example`) o del entorno —
nunca traen valores hardcodeados.

## Criterio de inclusión (público vs privado)

**Va en este repo** lo que es corazón del funcionamiento del laboratorio:
salud e infraestructura (health-check, backup, monitoreo, post-reboot),
comunicación entre componentes (MCPs genéricos, aggregator, notificaciones)
y gestión del ciclo de vida (onboarding, mantenimiento). Regla práctica:
*¿le sirve a cualquier instancia del lab sin editar más que el `.env`?*

**NO va en este repo** ninguna implementación de caso de uso puntual:
scripts atados a una empresa concreta, integraciones en evaluación, o
personalizaciones de una instancia. Eso vive en el repo privado de cada
instancia (espejo versionado del sistema vivo).

## Inventario

| Script | Función |
|---|---|
| `lab-health-check.sh` | Verifica containers/redes/endpoints, reinicia si algo falla |
| `lab-backup.sh` | Backup restic → B2 con notificación y push a Uptime Kuma |
| `cpu-temp-monitor.sh` | Sensores CPU → log estructurado + push a Uptime Kuma |
| `post-reboot-check.sh` | Verificación y recuperación de servicios tras reboot |
| `centro-aggregator.py` | Aggregator HTTP (:9001) que alimenta los widgets de Glance |
| `paperclip-watchdog.sh` | Mata heartbeats zombies y detecta OOM en Paperclip |
| `maintenance-check.sh` | Detecta updates de herramientas con ventana de estabilidad |
| `telegram-notify.sh` | Notificaciones del lab vía bot de Telegram |
| `onboard-company.sh` | Onboarding de empresa nueva en Paperclip |
| `sync-company.sh` | Espejo bidireccional entradas/outputs empresa ↔ contenedor |
| `weekly-ingest.sh` | Ingesta semanal de conocimiento por empresa |
| `deploy-agent-prompts.sh` | Despliega promptTemplates (S1+S2+S3) a la DB |
| `dagu-mcp.sh` / `moolmesh-mcp.sh` / `playwright-mcp.sh` | Wrappers MCP stdio |
| `paperclip-mcp-company.sh.template` | Template del MCP de Paperclip por empresa |
| `paperclip-*.sh` | Monitores y pollers de Paperclip (crons de Hermes) |
| `nlm-sync.sh` | Sincronización de cuadernos NotebookLM |
| `create-routine.sh` | Alta de rutinas/crons de Hermes |
| `cleanup-tmp.sh` | Limpieza de temporales |
| `security-apply-sudo.sh` | Endurecimiento de sudo |
| `sync-outline.sh` | (obsoleto — Outline retirado; pendiente de reemplazo) |
