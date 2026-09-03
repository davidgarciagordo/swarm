#!/usr/bin/env bash
# tests/test_verifier_contract.sh — contrato del gate de verificación independiente (spec §14bis):
# swarm:verifier es genérico (sin conocimiento de ningún dominio concreto), read-only, y su cabecera
# de lanzamiento/salida coincide exactamente con lo que agents/orchestrator.md §4 espera invocar.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/verifier.md"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/verifier.md exists"
[ -f "$F" ] || exit 1

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
assert_eq "0" "$(echo "$front" | grep -q '^name: verifier$' && echo 0 || echo 1)" "name: verifier"
assert_eq "0" "$(echo "$front" | grep -q '^model: opus$' && echo 0 || echo 1)" "model opus (juicio nunca en modelo débil, spec §2 principio 5)"
tools="$(echo "$front" | grep '^tools:')"
assert_eq "0" "$(echo "$tools" | grep -qF 'Read' && echo 0 || echo 1)" "tools includes Read"
assert_eq "0" "$(echo "$tools" | grep -qF 'Grep' && echo 0 || echo 1)" "tools includes Grep"
assert_eq "0" "$(echo "$tools" | grep -qF 'Bash' && echo 0 || echo 1)" "tools includes Bash"
assert_eq "1" "$(echo "$tools" | grep -qF 'Write' && echo 0 || echo 1)" "tools NEVER includes Write (read-only by construction, spec §2 principio 7)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Edit' && echo 0 || echo 1)" "tools NEVER includes Edit"
assert_eq "1" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools NEVER includes SendMessage (root talks to the domain, not verifier)"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools NEVER includes AskUserQuestion"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qF 'operation: verify' && echo 0 || echo 1)" "body documents operation: verify"
assert_eq "0" "$(echo "$body" | grep -qF 'domain:' && echo 0 || echo 1)" "body documents the domain: header line"
assert_eq "0" "$(echo "$body" | grep -qF 'verdict:' && echo 0 || echo 1)" "body documents the verdict: header line"
assert_eq "0" "$(echo "$body" | grep -qF '## Salida' && echo 0 || echo 1)" "body documents 'Read de agents/<domain>.md, sección ## Salida' as the contract source"
assert_eq "0" "$(echo "$body" | grep -qF 'mem-files.sh" query' && echo 0 || echo 1)" "body queries mem-files.sh for real findings"
assert_eq "0" "$(echo "$body" | grep -qF 'run:' && echo 0 || echo 1)" "body filters findings by [run:<run-id>]"
assert_eq "0" "$(echo "$body" | grep -qF 'VERIFY' && echo 0 || echo 1)" "body's finding TAG is VERIFY"
assert_eq "0" "$(echo "$body" | grep -qF 'no ves la transcripción interna' && echo 0 || echo 1)" "body states the honest limitation (no visibility into the domain's internal transcript)"
assert_eq "0" "$(echo "$body" | grep -qF 'files=0' && echo 0 || echo 1)" "body rejects OK with files=0"

# read-only real contra bash-guard (fichero nuevo, sin helper _run_hook — invoca el hook directo,
# mismo patrón que tests/test_discovery_orchestrator_spawns.sh)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:verifier", "tool_name": "Bash", "tool_input": {"command": "python3 x.py"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "swarm:verifier cannot run python3"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
