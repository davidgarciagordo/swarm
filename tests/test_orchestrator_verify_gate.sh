#!/usr/bin/env bash
# tests/test_orchestrator_verify_gate.sh — agents/orchestrator.md §4 debe enganchar swarm:verifier
# ANTES de cualquier cierre EN VERDE (nunca antes de BLOCKED/KO propagado, que ya no cierra en
# verde) y aplicar el mismo two-strike que hooks/validate-output.py cuando el verifier da KO.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/orchestrator.md exists"
[ -f "$F" ] || exit 1

body="$(cat "$F")"
assert_eq "0" "$(echo "$body" | grep -qF 'swarm:verifier' && echo 0 || echo 1)" "§4 invokes swarm:verifier"
assert_eq "0" "$(echo "$body" | grep -qF 'operation: verify' && echo 0 || echo 1)" "§4 passes operation: verify"
assert_eq "0" "$(echo "$body" | grep -qF 'cierre EN VERDE' && echo 0 || echo 1)" "§4 scopes the gate to green closes only"
assert_eq "0" "$(echo "$body" | grep -qF 'verificación fallida' && echo 0 || echo 1)" "§4 has a BLOCKED-verificación-fallida close line"
assert_eq "0" "$(echo "$body" | grep -qF 'two-strike' && echo 0 || echo 1)" "§4 documents the two-strike retry"
assert_eq "0" "$(echo "$body" | grep -qF '§14bis' && echo 0 || echo 1)" "§4 cites spec §14bis"

# la sección sigue exigiendo el resto de líneas de cierre pre-existentes (no se han borrado por error)
for existing in "cierre normal" "análisis completado" "diseño completado" "implementación completada"; do
  assert_eq "0" "$(echo "$body" | grep -qF "$existing" && echo 0 || echo 1)" "§4 still has the pre-existing '$existing' close line"
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
