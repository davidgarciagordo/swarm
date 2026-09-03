#!/usr/bin/env bash
# tests/test_orchestrator_implementation.sh — la raíz integra el dominio implementation (spec §15
# fase 5): SOLO por invocación explícita, nunca encadenado tras discovery/design.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" 'subagent_type: "swarm:implementation-orchestrator"')" "root launches implementation-orchestrator by type"
assert_eq "0" "$(has "$body" 'name: "implementation-orchestrator"')" "root names it exactly implementation-orchestrator"
assert_eq "0" "$(has "$body" 'operation: implement-phase')" "root passes operation: implement-phase"
assert_eq "0" "$(has "$body" 'NUNCA encadena')" "root explicitly documents implementation NEVER auto-chains after design"
assert_eq "1" "$(has "$body" 'implementation-orchestrator, fase 5')" "root no longer says implementation-orchestrator is unimplemented"
assert_eq "0" "$(has "$body" '## 10. Implementación')" "root has a dedicated §10 Implementación section"
assert_eq "0" "$(has "$body" 'checkpoint humano')" "root documents the human checkpoint rationale for not auto-chaining"

# I2 (fase 5a final review): §5.1's objective classification must have a path that actually REACHES
# §10 — without this, "implementa el plan de X" fell into the "todo omitido" close and never routed
# to implementation-orchestrator, mirroring the existing §5.1→§8.1 pointer pattern.
assert_eq "0" "$(has "$body" 'pide explícitamente implementar un plan ya escrito')" "§5.1 recognizes an explicit implement-the-plan objective"
assert_eq "0" "$(printf '%s' "$body" | tr '\n' ' ' | grep -qF 've a §10 en vez de terminar aquí' && echo 0 || echo 1)" "§5.1 routes to §10 instead of closing as todo-omitido"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
