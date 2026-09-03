#!/usr/bin/env bash
# scripts/swarm-status.sh — /swarm:status (spec §11): run actual, tier, agentes registrados,
# líneas de summary, hallazgos abiertos y runs recientes. Determinista: ni un turno de modelo.
#
# Contrato de salida (ruling 12): 0 = normal · 1 = no hay .swarm/ · 2 = hay datos que este script NO
# puede interpretar de forma determinista (imprime todo lo que sí pudo, más una línea
# "no interpretable: …" por caso). El 2 es lo que activa el fallback acotado de commands/status.md.
# Nunca se degrada en silencio a "tier: ?": un dato ilegible se DICE.
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
degraded=0

if [ ! -d "$SWARM_ROOT" ]; then
  echo "swarm: no hay .swarm/ en $SWARM_ROOT — corre /swarm:init en este repo primero" >&2
  exit 1
fi

RUN_ROOT="$SWARM_ROOT/run"
current=""
[ -f "$RUN_ROOT/current" ] && current="$(cat "$RUN_ROOT/current" 2>/dev/null)"

if [ -z "$current" ] || [ ! -d "$RUN_ROOT/$current" ]; then
  echo "swarm: sin runs registrados todavía (.swarm/ inicializado, ningún /swarm:run cerrado)"
else
  python3 - "$RUN_ROOT/$current" "$current" <<'PYEOF'
import json, os, sys

run_dir, run_id = sys.argv[1], sys.argv[2]

tier = started = "?"
degraded = False
run_json = os.path.join(run_dir, "run.json")
if os.path.isfile(run_json):
    try:
        with open(run_json) as fh:
            data = json.load(fh)
        tier = data.get("tier", "?")
        started = data.get("started", "?")
    except (ValueError, OSError) as exc:
        # Antes esto era un `pass` y el usuario veía "tier: ?" sin saber por qué. Un run.json
        # truncado (run interrumpido a mitad de escritura) o de otra versión del plugin es
        # justamente el residual que un script no puede resolver y un lector sí.
        print("no interpretable: %s (%s)" % (run_json, exc))
        degraded = True

print("run: %s · tier: %s · iniciado: %s" % (run_id, tier, started))

agents_dir = os.path.join(run_dir, "agents")
rows = []
if os.path.isdir(agents_dir):
    for name in sorted(os.listdir(agents_dir)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(agents_dir, name)) as fh:
                a = json.load(fh)
        except (ValueError, OSError):
            continue
        rows.append((a.get("domain", "?"), a.get("agent", name[:-5]), a.get("owner", "?")))
print("agentes registrados: %d" % len(rows))
for domain, agent, owner in sorted(rows):
    print("  - %-14s %s (lanzado por %s)" % (domain, agent, owner))

summary = os.path.join(run_dir, "summary.md")
if os.path.isfile(summary):
    with open(summary) as fh:
        lines = [l.rstrip("\n") for l in fh if l.strip()]
    print("summary del run (%d líneas):" % len(lines))
    for l in lines:
        print("  %s" % l)
else:
    print("summary del run: (todavía sin líneas)")

if degraded:
    sys.exit(2)
PYEOF
  [ $? -eq 2 ] && degraded=2
fi

python3 - "$SWARM_ROOT" <<'PYEOF'
import os, re, sys
from collections import Counter

swarm_root = sys.argv[1]
findings_dir = os.path.join(swarm_root, "findings")
open_by_agent = Counter()
open_by_tag = Counter()
total_open = 0
unparsed = []
if os.path.isdir(findings_dir):
    for name in sorted(os.listdir(findings_dir)):
        if not name.endswith(".md"):
            continue
        bad = 0
        with open(os.path.join(findings_dir, name)) as fh:
            for line in fh:
                m = re.search(r"\[key:([^|\]]+)\|([^|\]]+)\|", line)
                if not m:
                    # una línea que EMPIEZA como una entrada pero no trae la cabecera de metadatos
                    # (fichero editado a mano, o entrada de una versión futura): el conteo saldría
                    # bajo y nadie se enteraría. Se dice.
                    if line.startswith("- ["):
                        bad += 1
                    continue
                if "[status:open]" not in line:
                    continue
                total_open += 1
                open_by_agent[m.group(1)] += 1
                open_by_tag[m.group(2)] += 1
        if bad:
            unparsed.append((name, bad))
for name, bad in unparsed:
    print("no interpretable: %d entradas de findings/%s sin cabecera [key:…]" % (bad, name))
by_tag = ", ".join("%s: %d" % (t, n) for t, n in sorted(open_by_tag.items())) or "—"
print("hallazgos abiertos: %d (%s)" % (total_open, by_tag))
for agent, n in sorted(open_by_agent.items()):
    print("  - %-22s %d" % (agent, n))

run_root = os.path.join(swarm_root, "run")
recents = []
if os.path.isdir(run_root):
    import json
    for name in os.listdir(run_root):
        d = os.path.join(run_root, name)
        rj = os.path.join(d, "run.json")
        if not os.path.isdir(d) or not os.path.isfile(rj):
            continue
        try:
            with open(rj) as fh:
                data = json.load(fh)
        except (ValueError, OSError):
            continue
        recents.append((data.get("started", ""), name, data.get("tier", "?")))
recents.sort(reverse=True)
print("runs recientes: %d" % len(recents))
for started, name, tier in recents[:5]:
    print("  - %s (%s, %s)" % (name, tier, started))

if unparsed:
    sys.exit(2)
PYEOF
[ $? -eq 2 ] && degraded=2

exit "$degraded"
