#!/usr/bin/env python3
"""
Centro de Comando — Aggregator
Expone 5 endpoints HTML consumidos por Glance via widget 'extension'.
Puerto: 9001 (0.0.0.0, accesible desde contenedor Docker de Glance)
"""

import base64
import http.server
import json
import os
import re
import subprocess
import urllib.error
import urllib.request
from pathlib import Path


def load_env(path):
    env = {}
    try:
        with open(os.path.expanduser(path)) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, _, v = line.partition('=')
                    env[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return env


# --- Configuración ---

_scripts_env = load_env("~/ai-lab/scripts/.env")

PORT = 9001
BIND = "0.0.0.0"

LAB_IP = os.environ.get("LAB_IP") or _scripts_env.get("LAB_IP", "127.0.0.1")

DAGU_URL = f"http://{LAB_IP}:8480"
MOOLMESH_URL = f"http://{LAB_IP}:5200"
HERMES_CRONS = os.path.expanduser("~/.hermes/cron/jobs.json")
CPU_TEMP_LOG = os.path.expanduser("~/ai-lab/logs/cpu-temp.log")
_hermes_env = load_env("~/.hermes/.env")

DAGU_USER = _scripts_env.get("DAGU_AUTH_USER") or _hermes_env.get("DAGU_AUTH_USER", "")
DAGU_PASS = _scripts_env.get("DAGU_AUTH_PASS") or _hermes_env.get("DAGU_AUTH_PASS", "")


# --- Helpers HTML con clases CSS nativas de Glance ---

def row(label, value, cls="text-muted"):
    return (
        f'<div style="display:flex;justify-content:space-between;margin:2px 0">'
        f'<span style="opacity:0.7">{label}</span>'
        f'<span class="{cls}">{value}</span>'
        f'</div>'
    )


def error_html(msg):
    return f'<div class="color-negative" style="font-size:0.85em">{msg}</div>'


def fetch_json(url, headers=None, timeout=5):
    req = urllib.request.Request(url)
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def dagu_get_token():
    """Dagu v2.8.2 uses JWT auth — login and return Bearer token."""
    payload = json.dumps({"username": DAGU_USER, "password": DAGU_PASS}).encode()  # nosecret
    req = urllib.request.Request(
        f"{DAGU_URL}/api/v1/auth/login",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read().decode())
        return data["token"]


# --- Endpoints ---

def endpoint_system():
    parts = []

    # CPU temperatura
    try:
        lines = Path(CPU_TEMP_LOG).read_text().strip().split('\n')
        last_line = ""
        for line in reversed(lines):
            if line.strip():
                last_line = line
                break
        m = re.search(r'MAX_TEMP=(\d+\.?\d*)', last_line)
        if m:
            temp = float(m.group(1))
        else:
            r = subprocess.run(
                ['sensors', '-A', 'coretemp-isa-0000'],
                capture_output=True, text=True, timeout=5
            )
            cleaned = re.sub(r'\(.*?\)', '', r.stdout)
            temps = [float(t) for t in re.findall(r'\+(\d+\.?\d*)°C', cleaned)]
            temp = max(temps) if temps else None

        if temp is None:
            parts.append(row("CPU Temp", "n/d"))
        elif temp >= 90:
            parts.append(row("CPU Temp", f"{temp:.0f}°C  ⚠ CRÍTICO", "color-negative"))
        elif temp >= 75:
            parts.append(row("CPU Temp", f"{temp:.0f}°C  / high:94°", "color-highlight"))
        else:
            parts.append(row("CPU Temp", f"{temp:.0f}°C  / high:94°", "color-positive"))
    except Exception as e:
        parts.append(row("CPU Temp", f"error: {str(e)[:40]}", "color-negative"))

    # RAM
    try:
        mem = Path('/proc/meminfo').read_text()
        total_kb = int(re.search(r'MemTotal:\s+(\d+)', mem).group(1))
        avail_kb = int(re.search(r'MemAvailable:\s+(\d+)', mem).group(1))
        used_gb = (total_kb - avail_kb) / (1024 ** 2)
        total_gb = total_kb / (1024 ** 2)
        pct = int(100 * (total_kb - avail_kb) / total_kb)
        cls = "color-negative" if pct > 85 else ("color-highlight" if pct > 70 else "color-positive")
        parts.append(row("RAM", f"{used_gb:.1f} / {total_gb:.1f} GB  ({pct}%)", cls))
    except Exception:
        parts.append(row("RAM", "error", "color-negative"))

    # Disco
    try:
        r = subprocess.run(['df', '-BG', '--output=used,size,pcent', '/home'],
                           capture_output=True, text=True, timeout=5)
        line = r.stdout.strip().split('\n')[-1].split()
        used_g, total_g = int(line[0].rstrip('G')), int(line[1].rstrip('G'))
        pct = int(line[2].rstrip('%'))
        cls = "color-negative" if pct > 85 else ("color-highlight" if pct > 70 else "color-positive")
        parts.append(row("Disco /home", f"{used_g} / {total_g} GB  ({pct}%)", cls))
    except Exception:
        parts.append(row("Disco", "error", "color-negative"))

    # NLM Gateway (responds 404 on / but that means it's alive)
    try:
        urllib.request.urlopen("http://127.0.0.1:8770", timeout=2)
        parts.append(row("NLM Gateway :8770", "activo", "color-positive"))
    except urllib.error.HTTPError:
        parts.append(row("NLM Gateway :8770", "activo", "color-positive"))
    except Exception:
        parts.append(row("NLM Gateway :8770", "caído", "color-negative"))

    return '<div style="font-size:0.9em">' + ''.join(parts) + '</div>'


def endpoint_paperclip():
    sql = """
SELECT
  c.name,
  SUM(ce.input_tokens + ce.cached_input_tokens) AS tokens_total,
  ROUND(
    100.0 * SUM(ce.cached_input_tokens)
    / NULLIF(SUM(ce.input_tokens + ce.cached_input_tokens), 0), 1
  ) AS cache_hit_pct,
  ROUND(SUM(ce.cost_cents) / 100.0, 3) AS costo_usd
FROM cost_events ce
JOIN companies c ON ce.company_id = c.id
WHERE ce.created_at >= NOW() - INTERVAL '24 hours'
GROUP BY c.name
ORDER BY SUM(ce.cost_cents) DESC;
""".strip()

    try:
        r = subprocess.run(
            ['docker', 'exec', 'paperclip-db-1', 'psql',
             '-U', 'paperclip', '-d', 'paperclip',
             '-t', '-A', '-F', '\t', '-c', sql],
            capture_output=True, text=True, timeout=20
        )
        if r.returncode != 0:
            return error_html(f"psql error: {r.stderr[:80]}")

        lines = [l for l in r.stdout.strip().split('\n') if '\t' in l]
        if not lines:
            return '<div class="text-muted" style="font-size:0.85em">Sin datos en las últimas 24h</div>'

        html = (
            '<table style="width:100%;font-size:0.85em;border-collapse:collapse">'
            '<tr style="opacity:0.6;font-size:0.8em">'
            '<td>Empresa</td><td style="text-align:right">Tokens</td>'
            '<td style="text-align:right">Cache%</td><td style="text-align:right">USD/24h</td>'
            '</tr>'
        )
        total_usd = 0.0
        for line in lines:
            cols = line.split('\t')
            if len(cols) < 4:
                continue
            empresa, tokens_raw, cache_raw, costo_raw = cols[0], cols[1], cols[2], cols[3]
            try:
                cache_f = float(cache_raw) if cache_raw else 0.0
                costo_f = float(costo_raw) if costo_raw else 0.0
                tokens_i = int(float(tokens_raw)) if tokens_raw else 0
                total_usd += costo_f
            except ValueError:
                continue
            cache_cls = "color-positive" if cache_f >= 80 else (
                "color-highlight" if cache_f >= 50 else "color-negative")
            tokens_fmt = f"{tokens_i:,}"
            html += (
                f'<tr><td>{empresa}</td>'
                f'<td style="text-align:right">{tokens_fmt}</td>'
                f'<td style="text-align:right" class="{cache_cls}">{cache_raw}%</td>'
                f'<td style="text-align:right">${costo_raw}</td></tr>'
            )
        html += f'<tr style="border-top:1px solid rgba(255,255,255,0.1);opacity:0.6"><td colspan="3">Total</td><td style="text-align:right">${total_usd:.3f}</td></tr>'
        html += '</table>'
        return html

    except subprocess.TimeoutExpired:
        return error_html("timeout: DB no respondió en 20s")
    except Exception as e:
        return error_html(f"error: {str(e)[:80]}")


def endpoint_dags():
    if not DAGU_USER or not DAGU_PASS:
        return error_html("DAGU_AUTH_USER/PASS no encontrados en .env")

    try:
        token = dagu_get_token()
        data = fetch_json(
            f"{DAGU_URL}/api/v1/dags",
            headers={"Authorization": f"Bearer {token}"}
        )
    except urllib.error.HTTPError as e:
        return error_html(f"Dagu HTTP {e.code}")
    except urllib.error.URLError as e:
        return error_html(f"Dagu inaccesible: {e.reason}")
    except Exception as e:
        return error_html(f"error Dagu: {str(e)[:60]}")

    # Dagu v2.8.2: status codes — 4=succeeded, 5=failed, 3=running, 2=cancelled
    STATUS = {
        0: ("—", "text-muted"),
        1: ("pendiente", "text-muted"),
        2: ("cancelado", "text-muted"),
        3: ("corriendo", "color-highlight"),
        4: ("ok", "color-positive"),
        5: ("FALLÓ", "color-negative"),
    }

    dags = data.get('dags', [])
    if not dags:
        return '<div class="text-muted">No hay DAGs</div>'

    failed, running, ok_count = [], [], 0
    for entry in dags:
        dag = entry.get('dag', {})
        latest = entry.get('latestDAGRun', {})
        st = latest.get('status', 0)
        status_label = latest.get('statusLabel', '')
        name = dag.get('name', '?')
        if status_label == 'failed' or st == 5:
            failed.append(name)
        elif status_label == 'running' or st == 3:
            running.append(name)
        elif status_label == 'succeeded' or st == 4:
            ok_count += 1

    html = '<div style="font-size:0.85em">'
    total = len(dags)

    if failed:
        html += f'<div class="color-negative" style="margin-bottom:4px">⚠ Fallidos: {", ".join(failed)}</div>'
    if running:
        html += f'<div class="color-highlight" style="margin-bottom:4px">▶ Corriendo: {", ".join(running)}</div>'

    html += f'<div style="margin-bottom:6px;opacity:0.7">{ok_count}/{total} DAGs ok</div>'

    for entry in dags:
        dag = entry.get('dag', {})
        latest = entry.get('latestDAGRun', {})
        st = latest.get('status', 0)
        status_label = latest.get('statusLabel', '')
        name = dag.get('name', '?')

        if status_label:
            label_map = {
                'succeeded': ('ok', 'color-positive'),
                'failed': ('FALLÓ', 'color-negative'),
                'running': ('corriendo', 'color-highlight'),
                'cancelled': ('cancelado', 'text-muted'),
                'not_started': ('—', 'text-muted'),
            }
            st_text, st_cls = label_map.get(status_label, (status_label, 'text-muted'))
        else:
            st_text, st_cls = STATUS.get(st, ("?", "text-muted"))

        html += (
            f'<div style="display:flex;justify-content:space-between">'
            f'<span style="opacity:0.8">{name}</span>'
            f'<span class="{st_cls}">{st_text}</span></div>'
        )

    html += '</div>'
    return html


def endpoint_sessions():
    try:
        data = fetch_json(f"{MOOLMESH_URL}/api/sessions", timeout=5)
    except urllib.error.HTTPError as e:
        return error_html(f"MoolMesh HTTP {e.code}")
    except urllib.error.URLError as e:
        return error_html(f"MoolMesh inaccesible: {e.reason}")
    except Exception as e:
        return error_html(f"error: {str(e)[:60]}")

    sessions = data if isinstance(data, list) else data.get('sessions', data.get('data', []))

    if not sessions:
        return '<div class="text-muted">Sin sesiones recientes</div>'

    html = '<div style="font-size:0.85em">'
    for s in sessions[:6]:
        provider = s.get('provider', 'Agent')
        project = s.get('project', s.get('cwd', '?'))
        if '/' in str(project):
            project = str(project).split('/')[-1]
        events = s.get('events', s.get('event_count', s.get('total_events', 0)))
        num_sessions = s.get('sessions', 0)
        tool_calls = s.get('tool_calls', 0)
        html += (
            f'<div style="display:flex;justify-content:space-between;margin:2px 0">'
            f'<span style="opacity:0.8">{provider}: {str(project)[:18]}</span>'
            f'<span class="color-positive">{events}ev / {num_sessions}s</span></div>'
        )
    html += '</div>'
    return html


def endpoint_hermes_crons():
    try:
        data = json.loads(Path(HERMES_CRONS).read_text())
    except FileNotFoundError:
        return error_html("jobs.json no encontrado")
    except Exception as e:
        return error_html(f"error: {str(e)[:60]}")

    jobs = data.get('jobs', [])
    if not jobs:
        return '<div class="text-muted" style="font-size:0.85em">Sin crons</div>'

    errors = [j for j in jobs if j.get('last_status') == 'error' and j.get('enabled')]
    ok_count = sum(1 for j in jobs if j.get('last_status') == 'ok' and j.get('enabled'))
    enabled = [j for j in jobs if j.get('enabled')]

    html = '<div style="font-size:0.85em">'

    if errors:
        names = ", ".join(j.get('name', '?') for j in errors)
        html += f'<div class="color-negative" style="margin-bottom:4px">⚠ Error: {names}</div>'

    html += f'<div style="margin-bottom:6px;opacity:0.7">{ok_count}/{len(enabled)} crons ok</div>'

    STATUS_MAP = {
        'ok': ('ok', 'color-positive'),
        'error': ('error', 'color-negative'),
        'running': ('corriendo', 'color-highlight'),
    }

    for j in jobs:
        name = j.get('name', '?')
        enabled = j.get('enabled', False)
        status = j.get('last_status', '—')
        schedule = j.get('schedule_display', '?')

        if not enabled:
            st_text, st_cls = 'off', 'text-muted'
        else:
            st_text, st_cls = STATUS_MAP.get(status, (status or '—', 'text-muted'))

        last_err = j.get('last_error', '')
        tooltip = ''
        if last_err and st_text == 'error':
            short_err = last_err[:50].replace('"', '&quot;')
            tooltip = f' title="{short_err}"'

        html += (
            f'<div style="display:flex;justify-content:space-between;margin:1px 0">'
            f'<span style="opacity:0.8">{name}</span>'
            f'<span class="{st_cls}"{tooltip}>{st_text}</span></div>'
        )

    html += '</div>'
    return html


# --- HTTP Server ---

ROUTES = {
    '/system': endpoint_system,
    '/paperclip': endpoint_paperclip,
    '/dags': endpoint_dags,
    '/sessions': endpoint_sessions,
    '/hermes-crons': endpoint_hermes_crons,
}


class Handler(http.server.BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        handler = ROUTES.get(self.path.split('?')[0])
        if handler is None:
            self.send_response(404)
            self.end_headers()
            return

        try:
            body = handler()
        except Exception as e:
            body = error_html(f"Error interno: {e}")

        data = body.encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Widget-Title', '')
        self.send_header('Widget-Content-Type', 'html')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == '__main__':
    print(f"Centro Aggregator iniciando en {BIND}:{PORT}")
    with http.server.HTTPServer((BIND, PORT), Handler) as server:
        server.serve_forever()
