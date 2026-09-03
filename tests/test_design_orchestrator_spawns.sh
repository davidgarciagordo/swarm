#!/usr/bin/env bash
# tests/test_design_orchestrator_spawns.sh — quinta aplicación de la lección de fase 1: un
# orquestador que lanza hojas que NO preexisten necesita Agent(<hojas>) en su frontmatter. Incluye
# los 3 lentes grill EXTERNOS (working-methods:*), que tampoco preexisten cuando design-orchestrator
# arranca.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

F="$PLUGIN_ROOT/agents/design-orchestrator.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/design-orchestrator.md exists"
[ -f "$F" ] || { exit 1; }

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
tools="$(echo "$front" | grep '^tools:')"
agent_clause="$(echo "$tools" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p')"
assert_eq "1" "$([ -z "$agent_clause" ] && echo 0 || echo 1)" "tools: has an Agent(...) clause"
for leaf in planner pattern-advisor domain-modeler; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF "$leaf" && echo 0 || echo 1)" "Agent(...) includes $leaf"
done
for lens in "working-methods:grill-architect" "working-methods:grill-operator" "working-methods:grill-engineer"; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF "$lens" && echo 0 || echo 1)" "Agent(...) includes external lens $lens"
done
assert_eq "0" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: includes SendMessage"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools: NEVER AskUserQuestion (spec §3.2 rule 7)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Write' && echo 0 || echo 1)" "tools: no Write (delegates to planner)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Edit' && echo 0 || echo 1)" "tools: no Edit"
assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "model sonnet (spec §7)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 20$' && echo 0 || echo 1)" "maxTurns 20 (spec §7)"
assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "foreground"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qiF 'no preexisten' && echo 0 || echo 1)" "body documents that leaves+lenses do not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'misma tanda' && echo 0 || echo 1)" "body: pattern-advisor+domain-modeler launched in the same message"
assert_eq "0" "$(echo "$body" | grep -qF 'idempotencia' && echo 0 || echo 1)" "body documents the idempotency check against existing plans"
assert_eq "0" "$(echo "$body" | grep -qF 'arbitra' && echo 0 || echo 1)" "body documents it arbitrates grill findings itself (spec: arbitra actas)"
assert_eq "0" "$(echo "$body" | grep -qF '**Grill:** pendiente' && echo 0 || echo 1)" "body checks the Grill: pendiente marker before treating a plan as idempotent"
assert_eq "0" "$(echo "$body" | grep -qF '**Grill:** arbitrado' && echo 0 || echo 1)" "body documents flipping the marker to arbitrado as its own final action"
assert_eq "0" "$(echo "$body" | grep -qF 'sin grill' && echo 0 || echo 1)" "body documents grill only runs in tier full"
assert_eq "0" "$(echo "$body" | grep -qiF 'no reenv' && echo 0 || echo 1)" "body explicitly says it does NOT forward grill lines verbatim (unlike analysis-orchestrator)"

out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:design-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh register --run adhoc --agent planner --domain design --area . --owner design-orchestrator"}}
EOF2
)"
assert_eq "" "$out" "design-orchestrator can register a leaf via mem-manifest.sh"
out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:design-orchestrator", "tool_name": "Bash", "tool_input": {"command": "python3 x.py"}}
EOF2
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "design-orchestrator cannot run python3"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
