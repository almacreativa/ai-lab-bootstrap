#!/usr/bin/env bash
set -euo pipefail

# Escanea el sistema y genera ~/ai-lab/ops/core-manifest.yaml
# Este manifiesto es la fuente de verdad para core-guard.sh

LAB_DIR="${LAB_DIR:-$HOME/ai-lab}"
MANIFEST="$LAB_DIR/ops/core-manifest.yaml"

mkdir -p "$(dirname "$MANIFEST")"

HOSTNAME=$(hostname)
GENERATED=$(date -Iseconds)

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "not configured")
TAILSCALE_IFACE="tailscale0"
LAN_IFACE=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}' || echo "")
LAN_IP=""
LAN_SUBNET=""
if [ -n "$LAN_IFACE" ]; then
  LAN_IP=$(ip -4 addr show "$LAN_IFACE" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1 || true)
  LAN_CIDR=$(ip -4 addr show "$LAN_IFACE" 2>/dev/null | awk '/inet / {print $2}' | head -1 || true)
  if [ -n "$LAN_CIDR" ]; then
    LAN_SUBNET=$(python3 -c "import ipaddress; print(ipaddress.ip_network('$LAN_CIDR', strict=False))" 2>/dev/null || echo "")
  fi
fi

cat > "$MANIFEST" << HEADER
# core-manifest.yaml — generado automáticamente por generate-core-manifest.sh
# NO editar a mano — regenerar con: ~/ai-lab/ops/manifests/generate-core-manifest.sh
generated: "${GENERATED}"
hostname: "${HOSTNAME}"
tailscale_ip: "${TAILSCALE_IP}"
core_version: "1.0.0"

HEADER

# --- Sección network: detección dinámica de red ---
cat >> "$MANIFEST" << NETWORK
network:
  tailscale_ip: "${TAILSCALE_IP}"
  tailscale_iface: "${TAILSCALE_IFACE}"
  lan_subnet: "${LAN_SUBNET}"
  lan_ip: "${LAN_IP}"

NETWORK

# --- Sección security: política de puertos (declarativa, no auto-detectada) ---
cat >> "$MANIFEST" << 'SECURITY'
security:
  model: "per-port"
  ufw_default: "deny incoming"
  fail2ban: true

  allowed_ports:
    - port: 22
      proto: tcp
      from: [tailscale, lan]
      service: SSH
    - port: 9119
      proto: tcp
      from: [tailscale]
      service: Hermes dashboard
    - port: 22000
      proto: tcp
      from: [tailscale, lan]
      service: Syncthing P2P
    - port: 8480
      proto: tcp
      from: [tailscale]
      service: Dagu
    - port: 5200
      proto: tcp
      from: [tailscale]
      service: MoolMesh
    - port: 9001
      proto: tcp
      from: [tailscale]
      service: centro-de-comando
    - port: 8770
      proto: tcp
      from: [tailscale]
      service: NLM gateway
    - port: 8646
      proto: tcp
      from: [tailscale]
      service: Hermes xAI proxy
    - port: 8384
      proto: tcp
      from: [tailscale]
      service: Syncthing GUI
    - port: 9000
      proto: tcp
      from: [tailscale]
      service: Glance (host network)

  docker_binds:
    - service: paperclip-server
      port: 3100
      bind: [localhost, tailscale]
    - service: paperclip-db
      port: 5432
      bind: [localhost]
    - service: odysseus
      port: 7000
      bind: [localhost, tailscale]
    - service: portainer
      port: 9443
      bind: [tailscale]
    - service: uptime-kuma
      port: 3001
      bind: [tailscale]
    - service: searxng
      port: 8080
      bind: [localhost]
    - service: glance
      port: 9000
      bind: [host_network]
    - service: chromadb-odysseus
      port: 8100
      bind: [localhost]

SECURITY

# Binarios en ~/.local/bin/
echo "binaries:" >> "$MANIFEST"
if [ -d "$HOME/.local/bin" ]; then
  for bin in "$HOME/.local/bin"/*; do
    [ -f "$bin" ] || [ -L "$bin" ] || continue
    name=$(basename "$bin")
    # Saltar archivos .old y similares
    [[ "$name" == *.old* ]] && continue
    version=$("$bin" --version 2>/dev/null | head -1 || "$bin" version 2>/dev/null | head -1 || echo "unknown")
    version=$(echo "$version" | head -c 80)
    echo "  - name: \"${name}\"" >> "$MANIFEST"
    echo "    path: \"${bin}\"" >> "$MANIFEST"
    echo "    version: \"${version}\"" >> "$MANIFEST"
  done
fi

# Servicios systemd user habilitados (solo .service, no sockets/timers)
echo "" >> "$MANIFEST"
echo "services:" >> "$MANIFEST"
echo "  systemd_user:" >> "$MANIFEST"
if systemctl --user list-unit-files --state=enabled --type=service --no-pager --no-legend 2>/dev/null; then
  :
fi | while read -r unit state _; do
  echo "    - name: \"${unit}\"" >> "$MANIFEST"
  if systemctl --user is-active "$unit" &>/dev/null; then
    echo "      status: \"active\"" >> "$MANIFEST"
  else
    echo "      status: \"inactive\"" >> "$MANIFEST"
  fi
done

# Servicios systemd system del lab (hermes, dagu — no todos los del sistema)
echo "  systemd_system:" >> "$MANIFEST"
for unit in hermes.service dagu.service; do
  if systemctl list-unit-files "$unit" --no-pager --no-legend 2>/dev/null | grep -q "$unit"; then
    echo "    - name: \"${unit}\"" >> "$MANIFEST"
    if systemctl is-active "$unit" &>/dev/null; then
      echo "      status: \"active\"" >> "$MANIFEST"
    else
      echo "      status: \"inactive\"" >> "$MANIFEST"
    fi
  fi
done

# Containers Docker corriendo
echo "  docker:" >> "$MANIFEST"
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null | while IFS=$'\t' read -r name image status; do
  echo "    - name: \"${name}\"" >> "$MANIFEST"
  echo "      image: \"${image}\"" >> "$MANIFEST"
  echo "      status: \"running\"" >> "$MANIFEST"
done

# Redes Docker custom
echo "" >> "$MANIFEST"
echo "networks:" >> "$MANIFEST"
docker network ls --format '{{.Name}}\t{{.Driver}}' 2>/dev/null | grep -v -E '^(bridge|host|none)\t' | while IFS=$'\t' read -r name driver; do
  echo "  - name: \"${name}\"" >> "$MANIFEST"
  echo "    driver: \"${driver}\"" >> "$MANIFEST"
done

# DAGs de Dagu
echo "" >> "$MANIFEST"
echo "dags:" >> "$MANIFEST"
if [ -d "$HOME/.config/dagu/dags" ]; then
  for dag in "$HOME/.config/dagu/dags"/*.yaml; do
    [ -f "$dag" ] || continue
    echo "  - \"$(basename "$dag")\"" >> "$MANIFEST"
  done
fi

# Estado del backup
echo "" >> "$MANIFEST"
echo "backup:" >> "$MANIFEST"
if [ -f "$LAB_DIR/scripts/.env" ] && grep -q "RESTIC_PASSWORD" "$LAB_DIR/scripts/.env" 2>/dev/null; then
  echo "  configured: true" >> "$MANIFEST"
  source "$LAB_DIR/scripts/.env" 2>/dev/null || true
  if [ -z "${RESTIC_REPOSITORY:-}" ]; then
    RESTIC_REPOSITORY=$(grep -h '^RESTIC_REPO=' "$LAB_DIR/scripts/lab-backup.sh" "$LAB_DIR/ops/backup/lab-backup.sh" 2>/dev/null | head -1 | cut -d'"' -f2 || true)
  fi
  export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
  export B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-}"
  export B2_ACCOUNT_KEY="${B2_BACKUP_KEY:-}"
  export RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"
  LAST_SNAP=$(restic snapshots --latest 1 --json 2>/dev/null | python3 -c "import json,sys; s=json.load(sys.stdin); print(s[0]['time'][:19] if s else 'none')" 2>/dev/null || echo "unknown")
  echo "  last_snapshot: \"${LAST_SNAP}\"" >> "$MANIFEST"
else
  echo "  configured: false" >> "$MANIFEST"
fi

# Crons de Hermes, MCPs configurados y scripts (con detección de huérfanos)
# — plan unificación monitoreo/operación, fase 3
python3 - "$MANIFEST" "$LAB_DIR" << 'PYEOF'
import json, os, re, subprocess, sys
from pathlib import Path

manifest, lab_dir = sys.argv[1], sys.argv[2]
home = Path.home()
out = []

def yq(s):
    return str(s).replace('"', "'")

# ── Crons de Hermes ──
out.append("\nhermes_crons:")
try:
    jobs = json.loads((home / ".hermes/cron/jobs.json").read_text()).get("jobs", [])
    for j in jobs:
        out.append(f'  - name: "{yq(j.get("name", "?"))}"')
        out.append(f'    enabled: {str(bool(j.get("enabled"))).lower()}')
        sched = j.get("schedule_display") or j.get("schedule") or "?"
        out.append(f'    schedule: "{yq(sched)}"')
        cmd = str(j.get("command") or j.get("script") or j.get("prompt") or "")
        m = re.search(r'([\w.-]+\.(?:sh|py))', cmd)
        if m:
            out.append(f'    script: "{m.group(1)}"')
except Exception:
    out.append("  []")

# ── MCPs configurados ──
out.append("\nmcps:")
out.append("  claude_code:")
try:
    servers = json.loads((home / ".claude.json").read_text()).get("mcpServers", {})
    for name, cfg in servers.items():
        cmdline = " ".join([cfg.get("command", "")] + cfg.get("args", []))
        out.append(f'    - name: "{yq(name)}"')
        out.append(f'      command: "{yq(cmdline.strip())}"')
except Exception:
    out.append("    []")
out.append("  hermes:")
try:
    import yaml
    hcfg = yaml.safe_load((home / ".hermes/config.yaml").read_text()) or {}
    for name, cfg in (hcfg.get("mcp_servers") or {}).items():
        cmdline = " ".join([str(cfg.get("command", ""))] + [str(a) for a in (cfg.get("args") or [])])
        out.append(f'    - name: "{yq(name)}"')
        out.append(f'      command: "{yq(cmdline.strip())}"')
except Exception:
    out.append("    []")

# ── Scripts de ~/ai-lab/scripts/ con consumidores ──
scripts_dir = Path(lab_dir) / "scripts"
scripts = sorted([p.name for p in scripts_dir.iterdir()
                  if p.suffix in (".sh", ".py") and p.is_file()])

# Fuentes donde puede aparecer un consumidor
sources = {}   # etiqueta → texto
for dag in sorted((home / ".config/dagu/dags").glob("*.yaml")):
    sources[f"dag:{dag.name}"] = dag.read_text()
try:
    sources["crontab"] = subprocess.run(["crontab", "-l"], capture_output=True, text=True).stdout
except Exception:
    pass
try:
    sources["hermes-cron"] = (home / ".hermes/cron/jobs.json").read_text()
except Exception:
    pass
try:
    sources["hermes-config"] = (home / ".hermes/config.yaml").read_text()
except Exception:
    pass
try:
    sources["claude-mcp"] = (home / ".claude.json").read_text()
except Exception:
    pass
for unit in sorted((home / ".config/systemd/user").glob("*.service")):
    sources[f"systemd:{unit.name}"] = unit.read_text()
for other in scripts:
    try:
        sources[f"script:{other}"] = (scripts_dir / other).read_text()
    except Exception:
        pass

# Herramientas de invocación manual deliberada — no son huérfanos
MANUAL_SCRIPTS = {
    "onboard-company.sh", "create-routine.sh", "security-apply-sudo.sh",
    "odysseus-research.sh", "odysseus-email-check.sh", "odysseus-task-poll.sh",
    "nlm-distill.sh",
    "nlm-sync.sh", "lab-session.sh",
}

out.append("\nscripts:")
for name in scripts:
    consumers = sorted(set(
        label for label, text in sources.items()
        if name in text and label != f"script:{name}"
    ))
    if not consumers and name in MANUAL_SCRIPTS:
        consumers = ["manual"]
    out.append(f'  - name: "{name}"')
    if consumers:
        out.append(f'    consumers: [{", ".join(chr(34) + c + chr(34) for c in consumers)}]')
    else:
        out.append("    consumers: []")

with open(manifest, "a") as f:
    f.write("\n".join(out) + "\n")
PYEOF

# Software de sistema
echo "" >> "$MANIFEST"
echo "system:" >> "$MANIFEST"
echo "  os: \"$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')\"" >> "$MANIFEST"
echo "  docker: \"$(docker --version 2>/dev/null | head -1)\"" >> "$MANIFEST"
echo "  python: \"$(python3 --version 2>&1)\"" >> "$MANIFEST"
echo "  node: \"$(node --version 2>/dev/null || echo 'not installed')\"" >> "$MANIFEST"
echo "  tailscale: \"$(tailscale version 2>/dev/null | head -1 || echo 'not installed')\"" >> "$MANIFEST"

echo "[generate-core-manifest] Manifiesto generado en $MANIFEST"
