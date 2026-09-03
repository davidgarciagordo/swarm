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

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
