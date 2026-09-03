#!/usr/bin/env bash
# tests/test_stack_pack.sh — contrato del primer stack pack (spec §8): los 6 ficheros, el esquema
# de requirements.json, y —lo importante— que CADA comando documentado en commands.md sea
# realmente ejecutable por el agente que la propia tabla nombra como ejecutor (lección de fase 5a:
# un comando documentado que el guard deniega es un callejón sin salida silencioso).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
PACK="$PLUGIN_ROOT/skills/pack-php-ddd-symfony8"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

for f in SKILL.md commands.md conventions.md boundaries.md precedents.md requirements.json; do
  assert_eq "0" "$([ -f "$PACK/$f" ] && echo 0 || echo 1)" "pack has $f (spec §8 file contract)"
done

# Marcador de detección: el mismo que scripts/mem-scan.sh ya implementa (spec §8.1 fila 1).
assert_file_contains "$PACK/SKILL.md" "composer.json" "SKILL.md documents the composer.json marker"
assert_file_contains "$PACK/SKILL.md" "symfony/" "SKILL.md documents the symfony/* require marker"
assert_file_contains "$PACK/SKILL.md" "php-ddd-symfony8" "SKILL.md names the stack id used in context-pack.md"

# El pack es material de estudio generalizado: ningún nombre de proyecto/empresa real.
assert_eq "0" "$(grep -ril 'quantum' "$PACK" | wc -l | tr -d ' ')" "pack content names no real project (ruling 10)"

# requirements.json del pack: mismo esquema que el del plugin (spec §7).
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert set(['os','project','libs']) <= set(d.keys()), 'missing top-level keys'
for k in ('os','project','libs'):
    assert isinstance(d[k], list), k + ' must be a list'
tools = [i.get('tool') for i in d['os']]
assert 'php' in tools and 'composer' in tools, 'pack must require php and composer'
for i in d['os']:
    assert 'required' in i, 'os entry without required: ' + str(i)
    if i.get('required'):
        assert i.get('install'), 'required os entry needs an install hint: ' + str(i)
files = [i.get('file') for i in d['project']]
assert 'composer.json' in files, 'pack must declare composer.json as a project file'
for i in d['libs']:
    assert i.get('name') and i.get('manager'), 'lib entry needs name+manager: ' + str(i)
" "$PACK/requirements.json"
assert_eq "0" "$?" "pack requirements.json matches the §7 schema"

# --- el corazón: cada comando de la tabla, contra el guard del ejecutor que la tabla declara ---
guard() {
  local out
  out="$(python3 "$HOOK" <<PYIN
{"agent_type": "$1", "tool_name": "Bash", "tool_input": {"command": $2}}
PYIN
)"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

rows="$(python3 - "$PACK/commands.md" <<'PYEOF'
import json, re, sys

KEYS = {"lint","fix","typecheck","test","test-one","scan-deps","outdated","licenses",
        "scan-secrets","sast","migrate-diff","migrate-status","migrate-up"}

def is_header_or_separator(first_cell):
    return first_cell in ("clave", "---") or set(first_cell) <= set("- :")

data_lines = 0
parsed = 0
rows = 0
for line in open(sys.argv[1]):
    if not line.startswith("|"):
        continue
    raw_cells = line.strip().strip("|").split("|")
    first = raw_cells[0].strip()
    if is_header_or_separator(first):
        continue
    data_lines += 1
    # No partimos en exactamente 4 celdas por un split naive: el comando (3a columna) puede
    # contener sus propios "|" literales (p.ej. la alternancia de un regex de grep), que un split
    # ciego trocea de mas. clave/condicion (las 2 primeras) y ejecutor (la ultima) NUNCA llevan
    # "|" -- así que partimos desde ambos extremos y unimos lo que quede en medio como el comando
    # real, backticks y pipes internos intactos.
    if len(raw_cells) < 4:
        continue
    key = raw_cells[0].strip()
    _cond = raw_cells[1].strip()
    execs = raw_cells[-1].strip()
    cmd = "|".join(raw_cells[2:-1]).strip()
    if key not in KEYS:
        continue
    m = re.match(r"^`(.+)`$", cmd)
    if not m:
        continue
    parsed += 1
    # Los <placeholders> se sustituyen por un token inocuo antes de pasar por el guard.
    real = re.sub(r"<[^>]+>", "PLACEHOLDER", m.group(1))
    for agent in [e.strip() for e in execs.split("+")]:
        print(json.dumps([("swarm:" + agent), real]))
    rows += 1
assert parsed == data_lines, (
    "parser dropped %d of %d table data rows silently (parsed=%d, data_lines=%d)"
    % (data_lines - parsed, data_lines, parsed, data_lines)
)
assert rows >= 12, "expected the full §8 command set, got %d rows" % rows
PYEOF
)"
assert_eq "0" "$?" "commands.md table parses and covers the §8 command set"

while IFS= read -r pair; do
  [ -n "$pair" ] || continue
  agent="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[0])' "$pair")"
  cmd="$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])[1]))' "$pair")"
  assert_eq "allow" "$(guard "$agent" "$cmd")" "$agent may run its documented pack command: $cmd"
done <<EOF
$rows
EOF

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
