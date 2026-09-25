#!/usr/bin/env bash
# tests/test_design_orchestrator_spawns.sh — quinta aplicación de la lección de fase 1: un
# orquestador que lanza hojas que NO preexisten necesita Agent(<hojas>) en su frontmatter. Incluye
# las 3 lentes grill EXTERNAS (working-methods:*) Y las 3 NATIVAS de swarm (grill-architect,
# grill-operator, grill-engineer) — review-orchestrator detecta con `claude plugin list` cuál
# familia usar (nunca ambas) para que swarm funcione standalone Y en conjunto con working-methods,
# nunca solo lo segundo.
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
assert_eq "0" "$(echo "$agent_clause" | grep -qF "review-orchestrator" && echo 0 || echo 1)" "Agent(...) includes review-orchestrator (the review panel replaces the ad-hoc grill x3)"
agent_tokens=",$(echo "$agent_clause" | tr -d ' '),"
for lens in grill-architect grill-operator grill-engineer; do
  assert_eq "1" "$(echo "$agent_tokens" | grep -qF "$lens" && echo 0 || echo 1)" "Agent(...) no longer spawns $lens directly (it runs inside review-orchestrator)"
done
assert_eq "0" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: includes SendMessage"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools: NEVER AskUserQuestion (spec §3.2 rule 7)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Write' && echo 0 || echo 1)" "tools: no Write (delegates to planner)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Edit' && echo 0 || echo 1)" "tools: no Edit"
assert_eq "0" "$(echo "$front" | grep -q '^model: inherit$' && echo 0 || echo 1)" "model inherit (tiers contract)"
assert_eq "0" "$(echo "$front" | grep -q '^tier: judgement$' && echo 0 || echo 1)" "tier judgement (orchestrate/arbitrate)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 20$' && echo 0 || echo 1)" "maxTurns 20 (spec §7)"
assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "foreground"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qiF 'do NOT pre-exist' && echo 0 || echo 1)" "body documents that leaves+lenses do not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'same batch' && echo 0 || echo 1)" "body: pattern-advisor+domain-modeler launched in the same message"
assert_eq "0" "$(echo "$body" | grep -qF 'Idempotency check' && echo 0 || echo 1)" "body documents the idempotency check against existing plans"
assert_eq "0" "$(echo "$body" | grep -qF 'arbitrate' && echo 0 || echo 1)" "body documents it arbitrates grill findings itself (spec: arbitra actas)"
assert_eq "0" "$(echo "$body" | grep -qF '**Grill:** pending' && echo 0 || echo 1)" "body checks the Grill: pending marker before treating a plan as idempotent"
assert_eq "0" "$(echo "$body" | grep -qF '**Grill:** arbitrated' && echo 0 || echo 1)" "body documents flipping the marker to arbitrated as its own final action"
assert_eq "0" "$(echo "$body" | grep -qF 'ONLY in `tier: full`' && echo 0 || echo 1)" "body documents grill only runs in tier full"
assert_eq "0" "$(echo "$body" | grep -qiF 'do NOT forward the grill lines verbatim' && echo 0 || echo 1)" "body explicitly says it does NOT forward grill lines verbatim (unlike analysis-orchestrator)"
assert_eq "0" "$(echo "$body" | grep -qF 'operation: review' && echo 0 || echo 1)" "body launches review-orchestrator with operation: review"
assert_eq "0" "$(echo "$body" | grep -qF 'artifact-type: plan' && echo 0 || echo 1)" "body reviews the plan as artifact-type plan"
assert_eq "0" "$(echo "$body" | grep -qF 'round: 2' && echo 0 || echo 1)" "body documents the second (last) review round"
assert_eq "0" "$(echo "$body" | grep -qF 'BLOCKED review KO after 2 rounds' && echo 0 || echo 1)" "body escalates after 2 KO rounds"
assert_eq "0" "$(echo "$body" | grep -qF 'model-resolve.sh' && echo 0 || echo 1)" "body resolves child models via model-resolve.sh"
assert_eq "0" "$(echo "$body" | grep -qF -- '--escalate' && echo 0 || echo 1)" "body re-runs planner with the escalated tier after a KO"
R="$PLUGIN_ROOT/agents/review-orchestrator.md"
assert_eq "0" "$(grep -qF 'claude plugin list' "$R" && echo 0 || echo 1)" "review-orchestrator detects working-methods via claude plugin list"
assert_eq "0" "$(grep -qiF 'Never mix the two families' "$R" && echo 0 || echo 1)" "review-orchestrator never mixes native and external lenses"

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
out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:design-orchestrator", "tool_name": "Bash", "tool_input": {"command": "claude plugin list"}}
EOF2
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "design-orchestrator no longer runs claude plugin (detection moved to review-orchestrator)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
