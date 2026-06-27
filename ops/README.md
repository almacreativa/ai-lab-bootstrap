# ops/ — Framework operativo del lab

Este directorio se copia al host (`~/ai-lab/ops/`) durante `setup-instance.sh`.
Contiene todo lo necesario para que un lab se auto-audite, se respalde y documente sus problemas conocidos.

## Estructura

```
ops/
├── guards/                    # Drift detection (audit-only, nunca modifica)
│   ├── guard-lib.sh           # Funciones compartidas (report_ok, report_gap, emit_json, etc.)
│   ├── core-guard.sh          # Audita binarios, servicios, containers, networks, DAGs, backup
│   ├── bootstrap-guard.sh     # Detecta qué del sistema está cubierto por el bootstrap
│   └── profile-guard.sh       # Audita perfiles desplegados contra su profile.yaml
├── manifests/
│   └── generate-core-manifest.sh  # Genera snapshot YAML del estado del sistema
├── backup/
│   ├── lab-backup.sh          # Backup completo: dumps + configs + restic
│   ├── setup-backup.sh        # Wizard para configurar restic + B2
│   └── dr-restore.sh          # Restore desde backup con checklist
└── runbooks/                  # Documentación de problemas reales
    ├── dr-test.md
    ├── backup-troubleshoot.md
    ├── docker-exec-gotchas.md
    ├── apt-sources-restore.md
    ├── profile-lifecycle.md
    ├── tailscale-boot-race.md
    ├── paperclip-crash-loop.md
    └── secrets-management.md
```

## Correr guards manualmente

```bash
# Primero regenerar el manifest (fuente de verdad para core-guard)
~/ai-lab/ops/manifests/generate-core-manifest.sh

# Auditar el core
~/ai-lab/ops/guards/core-guard.sh

# Auditar cobertura del bootstrap
~/ai-lab/ops/guards/bootstrap-guard.sh

# Auditar un perfil específico
~/ai-lab/ops/guards/profile-guard.sh devlab
```

Los guards corren automáticamente cada domingo a las 5 AM (DAG: `lab-guards.yaml`).

## Interpretar reportes JSON

Los reportes se guardan en `~/ai-lab/logs/guard/`. Formato:

```json
{
  "guard": "core",
  "timestamp": "2026-06-27T02:10:00+00:00",
  "hostname": "i7local",
  "summary": { "ok": 64, "gap": 0, "drift": 4 },
  "checks": [
    { "type": "binary", "name": "claude", "status": "ok" },
    { "type": "service", "name": "dagu.service", "status": "ok" },
    { "type": "service", "name": "syncthing.service", "status": "drift",
      "expected": "active", "actual": "inactive" }
  ]
}
```

- **ok**: recurso presente y en el estado esperado
- **gap**: recurso faltante o no cubierto
- **drift**: recurso presente pero en estado diferente al esperado

## Agregar un check a un guard

1. En el guard correspondiente, usar las funciones de `guard-lib.sh`:
   - `report_ok "tipo" "nombre"` — check pasó
   - `report_gap "tipo" "nombre" "detalle"` — recurso faltante
   - `report_drift "tipo" "nombre" "esperado" "actual"` — estado diferente
2. El JSON y Telegram se generan automáticamente

## Agregar un runbook

Crear `ops/runbooks/nombre-del-problema.md` con esta estructura:
- Síntoma (qué ve el operador)
- Causa (por qué pasa)
- Fix (comandos exactos)
- Verificación (cómo confirmar que se resolvió)
