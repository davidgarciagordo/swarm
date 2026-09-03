#!/usr/bin/env bash
# tests/test_swarm_findings.sh — /swarm:findings [agente|tag] (spec §11). Determinista, y con la
# validación del filtro EN EL SCRIPT: un comando de slash NO pasa por hooks/bash-guard.py (el guard
# solo actúa sobre agent_type que empieza por "swarm:"), así que el argumento del usuario no puede
# depender de una instrucción en prosa dentro del .md del comando.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/swarm-findings.sh"

assert_eq "0" "$([ -x "$SCRIPT" ] && echo 0 || echo 1)" "scripts/swarm-findings.sh is executable"

root="$(mktemp -d "${TMPDIR:-/tmp}/swarm-findings.XXXXXX")"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/.swarm/findings"
cat > "$root/.swarm/findings/reviewer.md" <<'MD'
- [key:reviewer|REVIEW|src/A.php:10] [sha:abc] [status:open] [run:R1] REVIEW · src/A.php:10 · falta guarda → añadir guarda
- [key:reviewer|REVIEW|src/B.php:20] [sha:abc] [status:resolved] [run:R1] REVIEW · src/B.php:20 · ya resuelto → nada
MD
cat > "$root/.swarm/findings/security-auditor.md" <<'MD'
- [key:security-auditor|SEC|src/C.php:5] [sha:abc] [status:open] [run:R1] SEC · src/C.php:5 · query sin parametrizar → usar prepared
MD

# 1. sin filtro → solo abiertos, de todos los agentes
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "0" "$rc" "exits 0 with findings present"
assert_eq "0" "$(echo "$out" | grep -q 'src/A.php:10' && echo 0 || echo 1)" "shows an open finding"
assert_eq "0" "$(echo "$out" | grep -q 'src/C.php:5' && echo 0 || echo 1)" "shows findings from every agent"
assert_eq "1" "$(echo "$out" | grep -q 'src/B.php:20' && echo 0 || echo 1)" "hides resolved findings by default"

# 2. --all incluye los resueltos
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" --all 2>&1)"
assert_eq "0" "$(echo "$out" | grep -q 'src/B.php:20' && echo 0 || echo 1)" "--all includes resolved findings"

# 3. filtro por agente y por tag
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" security-auditor 2>&1)"
assert_eq "0" "$(echo "$out" | grep -q 'src/C.php:5' && echo 0 || echo 1)" "filters by agent name"
assert_eq "1" "$(echo "$out" | grep -q 'src/A.php:10' && echo 0 || echo 1)" "and excludes the other agent"
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" SEC 2>&1)"
assert_eq "0" "$(echo "$out" | grep -q 'src/C.php:5' && echo 0 || echo 1)" "filters by tag"
assert_eq "1" "$(echo "$out" | grep -q 'src/A.php:10' && echo 0 || echo 1)" "and excludes the other tag"

# 4. filtro inválido → exit 64, sin ejecutar ni interpretar nada
for bad in 'a b' 'x;rm -rf /' '$(id)' '`id`' 'a|b'; do
  out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" "$bad" 2>&1)"; rc=$?
  assert_eq "64" "$rc" "rejects an invalid filter ($bad) with exit 64"
done

# 5. sin .swarm/ → exit 1 accionable
root2="$(mktemp -d "${TMPDIR:-/tmp}/swarm-findings2.XXXXXX")"
out="$(SWARM_ROOT="$root2/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
rm -rf "$root2"
assert_eq "1" "$rc" "exits 1 when .swarm/ does not exist"
assert_eq "0" "$(echo "$out" | grep -q 'swarm:init' && echo 0 || echo 1)" "and points the user at /swarm:init"

# 6. entradas que no casan con la cabecera de metadatos → exit 2 (el residual del ruling 12)
echo '- [algo escrito a mano] REVIEW · src/D.php:1 · nota suelta' >> "$root/.swarm/findings/reviewer.md"
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "2" "$rc" "exits 2 when a '- [' entry has no [key:…] header"
assert_eq "0" "$(echo "$out" | grep -q 'no interpretable' && echo 0 || echo 1)" "and names how many entries it could not read"
assert_eq "0" "$(echo "$out" | grep -q 'src/A.php:10' && echo 0 || echo 1)" "while still listing the findings it COULD read"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
