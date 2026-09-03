#!/usr/bin/env bash
# scripts/req-check.sh — verificación determinista de requirements.json (env-checker, spec §7)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FILE="$PLUGIN_ROOT/requirements.json"
ROOT="$PWD"
PACK_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      [ $# -ge 2 ] || { echo "req-check.sh: --file requires a value" >&2; exit 64; }
      FILE="$2"; shift 2 ;;
    --root)
      [ $# -ge 2 ] || { echo "req-check.sh: --root requires a value" >&2; exit 64; }
      ROOT="$2"; shift 2 ;;
    --pack)
      [ $# -ge 2 ] || { echo "req-check.sh: --pack requires a value" >&2; exit 64; }
      PACK_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ ! -f "$FILE" ]; then
  echo "req-check.sh: requirements file not found: $FILE" >&2
  exit 64
fi

if [ -n "$PACK_FILE" ] && [ ! -f "$PACK_FILE" ]; then
  echo "req-check.sh: pack requirements file not found: $PACK_FILE" >&2
  exit 64
fi

UNAME="$(uname -s 2>/dev/null || echo unknown)"

python3 - "$FILE" "$ROOT" "$UNAME" "$PACK_FILE" <<'PYEOF'
import json
import os
import re
import shutil
import subprocess
import sys

req_file, root, uname = sys.argv[1], sys.argv[2], sys.argv[3]
pack_file = sys.argv[4] if len(sys.argv) > 4 else ""


def load(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (ValueError, OSError) as exc:
        sys.stderr.write("req-check.sh: %s no es JSON valido: %s\n" % (path, exc))
        sys.exit(64)
    if not isinstance(data, dict):
        sys.stderr.write("req-check.sh: %s no es un objeto JSON\n" % path)
        sys.exit(64)
    for key in ("os", "project", "libs"):
        value = data.get(key, [])
        if not isinstance(value, list):
            sys.stderr.write("req-check.sh: %s: '%s' debe ser una lista\n" % (path, key))
            sys.exit(64)
        data[key] = value
    return data


IDENTITY = {"os": "tool", "project": "file", "libs": "name"}


def merge(base, pack):
    """Concatena os/project/libs; ante la misma clave de identidad, gana el PACK (spec §7)."""
    out = {}
    for key, id_field in IDENTITY.items():
        merged = []
        pack_ids = set()
        for item in pack.get(key, []):
            if isinstance(item, dict) and item.get(id_field) is not None:
                pack_ids.add(item[id_field])
            merged.append(item)
        for item in base.get(key, []):
            if isinstance(item, dict) and item.get(id_field) in pack_ids:
                continue          # la entrada del pack ya la cubre
            merged.append(item)
        out[key] = merged
    return out


data = load(req_file)
if pack_file:
    data = merge(data, load(pack_file))

checked = 0
missing_required = []
missing_optional = []


def install_hint(item):
    install = item.get("install") or {}
    brew = install.get("brew")
    apt = install.get("apt")
    if uname == "Darwin" and brew:
        return "brew install %s" % brew
    if uname != "Darwin" and apt:
        return "apt install %s" % apt
    parts = []
    if brew:
        parts.append("brew install %s" % brew)
    if apt:
        parts.append("apt install %s" % apt)
    if parts:
        return " / ".join(parts)
    return "sin hint de instalacion en requirements.json"


def version_tuple(text):
    m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", text or "")
    if not m:
        return None
    return tuple(int(g) if g else 0 for g in m.groups())


def check_os_item(item):
    global checked
    tool = item.get("tool")
    required = bool(item.get("required"))
    checked += 1
    if shutil.which(tool) is None:
        return required, tool, install_hint(item)
    min_version = item.get("min")
    if min_version:
        # Best-effort: una tool sin flag de version fiable, o una salida que no
        # podemos parsear, se trata como presente-y-version-desconocida — nunca
        # es un fallo duro (YAGNI: no se construye un parser de versiones robusto).
        try:
            out = subprocess.run(
                [tool, "--version"], capture_output=True, text=True, timeout=5
            )
            found = version_tuple(out.stdout) or version_tuple(out.stderr)
            wanted = version_tuple(min_version)
            if found and wanted and found < wanted:
                return required, tool, "version %s < min %s" % (
                    ".".join(str(part) for part in found), min_version,
                )
        except Exception:
            pass
    return None


for item in data.get("os", []):
    result = check_os_item(item)
    if result:
        required, tool, hint = result
        entry = {"tool": tool, "hint": hint}
        (missing_required if required else missing_optional).append(entry)

for item in data.get("project", []):
    checked += 1
    path = item.get("file")
    required = bool(item.get("required"))
    if not os.path.isfile(os.path.join(root, path)):
        entry = {"tool": path, "hint": "fichero de proyecto ausente"}
        (missing_required if required else missing_optional).append(entry)

# libs: la verificacion real contra un gestor de paquetes es responsabilidad de
# `dependency-auditor` (comandos del pack: scan-deps/outdated), no de este script. Aqui cada
# entrada se reporta como no bloqueante para que el health-gate nunca falle por una libreria.
for item in data.get("libs", []):
    checked += 1
    missing_optional.append({
        "tool": item.get("name"),
        "hint": "sin verificar aqui - lo audita dependency-auditor",
    })

ok = len(missing_required) == 0
report = {
    "ok": ok,
    "missing_required": missing_required,
    "missing_optional": missing_optional,
    "checked": checked,
}
print(json.dumps(report))
sys.exit(0 if ok else 1)
PYEOF
