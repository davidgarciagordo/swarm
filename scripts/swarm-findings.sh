#!/usr/bin/env bash
# scripts/swarm-findings.sh — /swarm:findings [agente|tag] [--all] (spec §11): consulta filtrada
# sobre .swarm/findings/. Determinista, sin modelo.
#
# El filtro se valida AQUÍ (no en la prosa del comando): un comando de slash no pasa por
# hooks/bash-guard.py, así que el argumento del usuario tiene que fallar cerrado en el propio script.
#
# Contrato de salida (ruling 12): 0 = normal · 1 = no hay .swarm/ · 64 = filtro inválido (error del
# usuario, lo resuelve el propio script) · 2 = hay entradas que no se pueden interpretar de forma
# determinista. Solo el 2 activa el fallback acotado de commands/findings.md.
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"

filter=""
show_all=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) show_all=1; shift ;;
    -*) echo "usage: swarm-findings.sh [agente|TAG] [--all]" >&2; exit 64 ;;
    *)
      if [ -n "$filter" ]; then
        echo "swarm: un solo filtro (agente o TAG)" >&2
        exit 64
      fi
      filter="$1"; shift ;;
  esac
done

if [ -n "$filter" ]; then
  case "$filter" in
    *[!A-Za-z0-9_-]*|"")
      echo "swarm: filtro inválido '$filter' — solo [A-Za-z0-9_-]" >&2
      exit 64
      ;;
  esac
fi

if [ ! -d "$SWARM_ROOT" ]; then
  echo "swarm: no hay .swarm/ en $SWARM_ROOT — corre /swarm:init en este repo primero" >&2
  exit 1
fi

python3 - "$SWARM_ROOT" "$filter" "$show_all" <<'PYEOF'
import os, re, sys

swarm_root, flt, show_all = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
findings_dir = os.path.join(swarm_root, "findings")
KEY_RE = re.compile(r"\[key:([^|\]]+)\|([^|\]]+)\|([^\]]*)\]")
STATUS_RE = re.compile(r"\[status:(\w+)\]")
CAP = 50

rows = []
unparsed = 0
if os.path.isdir(findings_dir):
    for name in sorted(os.listdir(findings_dir)):
        if not name.endswith(".md"):
            continue
        with open(os.path.join(findings_dir, name)) as fh:
            for line in fh:
                m = KEY_RE.search(line)
                if not m:
                    # línea con forma de entrada pero sin cabecera de metadatos: no se puede filtrar
                    # ni clasificar de forma determinista. Se cuenta y se dice (ruling 12), en vez de
                    # desaparecer del listado sin dejar rastro.
                    if line.startswith("- ["):
                        unparsed += 1
                    continue
                agent, tag = m.group(1), m.group(2)
                sm = STATUS_RE.search(line)
                status = sm.group(1) if sm else "open"
                if not show_all and status != "open":
                    continue
                if flt and flt != agent and flt != tag:
                    continue
                # el cuerpo legible empieza tras el último "] " de la cabecera de metadatos
                body = line.rstrip("\n")
                idx = body.rfind("] ")
                body = body[idx + 2:] if idx != -1 else body
                rows.append((agent, tag, status, body))

scope = "todos" if show_all else "abiertos"
label = ("filtro %s · " % flt) if flt else ""
print("hallazgos (%s%s): %d" % (label, scope, len(rows)))
for agent, tag, status, body in rows[:CAP]:
    mark = "" if status == "open" else " [%s]" % status
    print("  - %-22s %s%s" % (agent, body, mark))
if len(rows) > CAP:
    print("  … y %d más (afina con /swarm:findings <agente|TAG>)" % (len(rows) - CAP))
if unparsed:
    print("no interpretable: %d entradas sin cabecera [key:…] (no se pueden filtrar)" % unparsed)
    sys.exit(2)
PYEOF
rc=$?

exit "$rc"
