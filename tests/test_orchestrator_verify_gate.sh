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

body="$(awk '/^## 4\. Cierre/{f=1} f && /^## 5\./{exit} f' "$F")"
assert_eq "0" "$([ -n "$body" ] && echo 0 || echo 1)" "§4. Cierre section extracted (non-empty)"
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

# C2 regression: verifier's OWN BLOCKED/malformed outcome on its FIRST launch must be an explicit
# third branch (distinct from the domain-BLOCKED branch on the correction round) — never treated
# as an implicit OK, never relaunched, never conflated with the KO-segunda-vez two-strike.
assert_eq "0" "$(echo "$body" | grep -qF 'no es un `OK` ni un `KO <motivo>`' && echo 0 || echo 1)" "§4 has an explicit branch for verifier's own non-OK/non-KO first-launch response"
assert_eq "0" "$(echo "$body" | grep -qF 'verifier no completó' && echo 0 || echo 1)" "§4's verifier-first-launch-failure branch has its own close line"
assert_eq "0" "$(echo "$body" | grep -qF 'DISTINTA de las de arriba' && echo 0 || echo 1)" "§4 states the verifier-self-failure branch is distinct from the domain-correction-failure branch"

# I1 regression: swarm:verifier launches must be registered in the run manifest, same as every
# other Agent(...) launch in this file (spec §5, no carve-out for the gate).
verifier_registers="$(echo "$body" | grep -cF 'mem-manifest.sh" register --run <run-id> --agent verifier-')"
assert_eq "0" "$([ "$verifier_registers" -ge 2 ] && echo 0 || echo 1)" "§4 registers swarm:verifier in the manifest before EACH of its two launch points (got $verifier_registers)"
assert_eq "0" "$(echo "$body" | grep -qF -- '--domain verify' && echo 0 || echo 1)" "§4's verifier register call uses --domain verify"

# I2 regression: the launched INSTANCE name must be domain-qualified (verifier-<domain-tag>), not
# the bare fixed "verifier" — avoids two green domains in the same run colliding on manifest file /
# two-strike counter. subagent_type itself stays the fixed "swarm:verifier" contract.
assert_eq "0" "$(echo "$body" | grep -qF 'name: "verifier-<domain-tag>"' && echo 0 || echo 1)" "§4's Agent(...) launches use a domain-qualified instance name"
assert_eq "1" "$(echo "$body" | grep -qF 'name: "verifier"' && echo 0 || echo 1)" "§4 no longer launches a bare fixed-name \"verifier\" instance"
assert_eq "0" "$(echo "$body" | grep -qF 'subagent_type: "swarm:verifier"' && echo 0 || echo 1)" "§4 still launches subagent_type swarm:verifier (the contract/file, unchanged)"

# I3 regression: the non-relaunch branch must handle BOTH a well-formed BLOCKED <motivo> (propagate
# literal) AND a malformed/empty domain reply (synthesize a fallback close line) — not assume a
# literal BLOCKED string always exists to copy.
assert_eq "0" "$(echo "$body" | grep -qF 'el dominio no devolvió un veredicto' && echo 0 || echo 1)" "§4 synthesizes a fallback close line when the domain's correction reply is malformed/empty"
assert_eq "0" "$(echo "$body" | grep -qF 'Propaga literal' && echo 0 || echo 1)" "§4 clarifies literal-propagation only applies when a well-formed BLOCKED string exists"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
