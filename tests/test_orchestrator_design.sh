#!/usr/bin/env bash
# tests/test_orchestrator_design.sh — la raíz integra el dominio design (spec §15 fase 4): lo
# encadena tras discovery SOLO en tier full (spec §9.1: light = un solo dominio).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" 'subagent_type: "swarm:design-orchestrator"')" "root launches design-orchestrator by type"
assert_eq "0" "$(has "$body" 'name: "design-orchestrator"')" "root names it exactly design-orchestrator"
assert_eq "0" "$(has "$body" 'operation: design')" "root passes operation: design"
assert_eq "0" "$(has "$body" 'solo en `tier: full`')" "root documents design chains ONLY in tier full"
assert_eq "1" "$(has "$body" 'aún no existe (fase 4)')" "root no longer says design-orchestrator is unimplemented"
assert_eq "0" "$(has "$body" '## 9. Diseño')" "root has a dedicated §9 Diseño section"

# §4 cierre: nuevas líneas de camino terminal para design
assert_eq "0" "$(has "$body" 'diseño completado')" "root's close section documents the design terminal path"

# tier: light must never chain to design — both termination clauses that make this airtight
assert_eq "0" "$(has "$body" 'Si `tier: light`, el run termina aquí')" "§5.4 explicitly terminates the run in tier light instead of chaining to design"
assert_eq "0" "$(has "$body" 'Solo `tier: full`')" "§9.1 gates the whole design domain on tier full"

# --- refactor/migración sustancial: discovery still skips, but design NOW chains (tier full) ---

# stale bundling must be fully gone: refactor no longer lumped with pure bugfix/docs/infra as a
# single skip-both category anywhere in the file (project's own regression lesson: grep the WHOLE
# file for the enumerated-list pattern, don't assume one site is the whole bug)
assert_eq "1" "$(has "$body" 'bugfix/refactor/docs/infra')" "root no longer bundles refactor with pure bugfix/docs/infra as one skip-both category"

# §5.1 documents the new keyword-driven sub-classification for refactor/migración
assert_eq "0" "$(has "$body" 'refactor/migración sustancial')" "§5.1 introduces the refactor/migración sustancial sub-classification"
assert_eq "0" "$(has "$body" 'reestructura, restructuring')" "§5.1 lists the refactor/migración keyword table"
assert_eq "0" "$(has "$body" 'pero design NO')" "§5.1 states discovery skips but design does not, for the refactor path"

# §9.1 documents the two independent chaining paths (product decisions vs refactor/migración)
assert_eq "0" "$(has "$body" 'dos vías independientes')" "§9.1 documents design now runs via two independent paths, not one chained condition"
assert_eq "0" "$(has "$body" 'Vía refactor/migración sustancial')" "§9.1 has its own refactor/migración path to design"
assert_eq "0" "$(has "$body" 'ya no son la misma condición encadenada')" "§9.1 clarifies discovery-skip and design-skip are independently justified now"

# §9.4 keeps 'diseño completado' generic to both paths (product decisions and refactor)
assert_eq "0" "$(has "$body" 'vía decisiones de producto O vía refactor/migración')" "§9.4 documents both paths close with the same DONE line"

# §4's combined-omission line no longer implies refactor is always bundled with pure bugfix/docs/infra
assert_eq "0" "$(has "$body" 'bugfix/docs/tests/infra puro')" "§4/§5.1/§9.4 use the narrowed bugfix/docs/tests/infra puro category"
assert_eq "0" "$(has "$body" 'en `tier: full` refactor/migración YA NO cae aquí')" "§4 states refactor/migración no longer falls into the combined-omission line in tier full"

# §7 output example: a refactor objective in tier full shows discovery omitted but design chained
assert_eq "0" "$(has "$body" 'objetivo de refactor/migración sustancial, sin decisión de producto que preguntar')" "§7 has a worked example of the refactor path chaining to design"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
