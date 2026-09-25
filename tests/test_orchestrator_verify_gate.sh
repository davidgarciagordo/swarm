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

body="$(awk '/^## 4\. Closing/{f=1} f && /^## 5\./{exit} f' "$F")"
assert_eq "0" "$([ -n "$body" ] && echo 0 || echo 1)" "§4. Cierre section extracted (non-empty)"
assert_eq "0" "$(echo "$body" | grep -qF 'swarm:verifier' && echo 0 || echo 1)" "§4 invokes swarm:verifier"
assert_eq "0" "$(echo "$body" | grep -qF 'operation: verify' && echo 0 || echo 1)" "§4 passes operation: verify"
assert_eq "0" "$(echo "$body" | grep -qF 'GREEN closing' && echo 0 || echo 1)" "§4 scopes the gate to green closes only"
assert_eq "0" "$(echo "$body" | grep -qF 'verification failed' && echo 0 || echo 1)" "§4 has a BLOCKED-verificación-fallida close line"
assert_eq "0" "$(echo "$body" | grep -qF 'two-strike' && echo 0 || echo 1)" "§4 documents the two-strike retry"
# NOTE: the spec §14bis citation was deliberately removed in cdf601b ("delete delivery-phase
# plan/spec docs, inline their content into agents") — the spec docs no longer exist, and that
# commit stripped ~140 dangling "(spec §X)" citations repo-wide without touching any actual rule.
# This assertion checked a citation that is now correctly gone, so it is dropped rather than
# translated.

# la sección sigue exigiendo el resto de líneas de cierre pre-existentes (no se han borrado por error)
for existing in "normal close" "analysis completed" "design completed" "implementation completed"; do
  assert_eq "0" "$(echo "$body" | grep -qF "$existing" && echo 0 || echo 1)" "§4 still has the pre-existing '$existing' close line"
done

# C2 regression: verifier's OWN BLOCKED/malformed outcome on its FIRST launch must be an explicit
# third branch (distinct from the domain-BLOCKED branch on the correction round) — never treated
# as an implicit OK, never relaunched, never conflated with the KO-segunda-vez two-strike.
assert_eq "0" "$(echo "$body" | grep -qF 'neither a clean `OK` nor a clean `KO <reason>`' && echo 0 || echo 1)" "§4 has an explicit branch for verifier's own non-OK/non-KO launch response"
assert_eq "0" "$(echo "$body" | grep -qF 'verifier did not complete' && echo 0 || echo 1)" "§4's verifier-launch-failure branch has its own close line"
assert_eq "0" "$(echo "$body" | grep -qF 'DIFFERENT from the ones above' && echo 0 || echo 1)" "§4 states the verifier-self-failure branch is distinct from the domain-correction-failure branch"

# Re-review fix: C2's branch must cover BOTH of verifier's launches (first attempt AND the retry
# relaunch after a domain corrects), not only the first — a BLOCKED/malformed response on the
# SECOND launch was previously unhandled (same false-green hole C2 closes for the first launch).
assert_eq "0" "$(echo "$body" | grep -qF 'EITHER of its two launches' && echo 0 || echo 1)" "§4's verifier-self-failure branch is scoped to EITHER of verifier's two launches"
assert_eq "1" "$(echo "$body" | grep -qF 'a su PRIMER lanzamiento no es un' && echo 0 || echo 1)" "§4 no longer scopes the verifier-self-failure branch to the first launch only"

# I1 regression: swarm:verifier launches must be registered in the run manifest, same as every
# other Agent(...) launch in this file (spec §5, no carve-out for the gate).
verifier_registers="$(echo "$body" | grep -cF 'mem-manifest.sh" register --run <run-id> --agent verifier-')"
assert_eq "0" "$([ "$verifier_registers" -ge 2 ] && echo 0 || echo 1)" "§4 registers swarm:verifier in the manifest before EACH of its two launch points (got $verifier_registers)"
assert_eq "0" "$(echo "$body" | grep -qF -- '--domain verify' && echo 0 || echo 1)" "§4's verifier register call uses --domain verify"

# I2 regression: the launched INSTANCE name must be domain-qualified (verifier-<domain-tag>), not
# the bare fixed "verifier" — avoids two green domains in the same run colliding on the same agent
# name / manifest file (does NOT separate hooks/validate-output.py's malformed-stop retry counter,
# which keys on agent_type basename + reason hash, not on name: — documented as a known limit in
# §4's prose). subagent_type itself stays the fixed "swarm:verifier" contract.
assert_eq "0" "$(echo "$body" | grep -qF 'name: "verifier-<domain-tag>"' && echo 0 || echo 1)" "§4's Agent(...) launches use a domain-qualified instance name"
assert_eq "1" "$(echo "$body" | grep -qF 'name: "verifier"' && echo 0 || echo 1)" "§4 no longer launches a bare fixed-name \"verifier\" instance"
assert_eq "0" "$(echo "$body" | grep -qF 'subagent_type: "swarm:verifier"' && echo 0 || echo 1)" "§4 still launches subagent_type swarm:verifier (the contract/file, unchanged)"

# Re-review fix: §4 must NOT claim the domain-qualified name: separates the malformed-stop retry
# counter (false — hooks/validate-output.py keys retry_key on agent_type basename, not name:) —
# it must instead document that as an honest known limitation.
assert_eq "0" "$(echo "$body" | grep -qF 'same agent name or the same' && echo 0 || echo 1)" "§4's collision-avoidance claim is scoped to agent-name/manifest-file only (two-strike claim removed)"
assert_eq "1" "$(echo "$body" | tr '\n' ' ' | grep -qF 'el mismo nombre de agente, el mismo contador two-strike' && echo 0 || echo 1)" "§4 no longer claims the rename separates the two-strike retry counter (false — retry_key keys on agent_type, not name:)"
assert_eq "0" "$(echo "$body" | grep -qF 'Known limitation' && echo 0 || echo 1)" "§4 documents the retry-counter limitation honestly"
assert_eq "0" "$(echo "$body" | grep -qF "agent_type.split(':')[-1]" && echo 0 || echo 1)" "§4 cites the real retry_key derivation from hooks/validate-output.py"

# I3 regression: the non-relaunch branch must handle BOTH a well-formed BLOCKED <motivo> (propagate
# literal) AND a malformed/empty domain reply (synthesize a fallback close line) — not assume a
# literal BLOCKED string always exists to copy.
assert_eq "0" "$(echo "$body" | grep -qF 'the domain did not return a valid' && echo 0 || echo 1)" "§4 synthesizes a fallback close line when the domain's correction reply is malformed/empty"
assert_eq "0" "$(echo "$body" | grep -qF '"Propagate literal"' && echo 0 || echo 1)" "§4 clarifies literal-propagation only applies when a well-formed BLOCKED string exists"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
