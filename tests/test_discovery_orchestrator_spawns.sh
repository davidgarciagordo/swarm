#!/usr/bin/env bash
# tests/test_discovery_orchestrator_spawns.sh — tercera aplicación de la lección de fase 1:
# un orquestador que lanza hojas que NO preexisten necesita Agent(<hojas>) en su frontmatter;
# SendMessage solo alcanza agentes ya vivos. discovery-orchestrator lanza CUATRO hojas en una
# tanda: las cuatro tienen que estar dentro del paréntesis de Agent(...).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/discovery-orchestrator.md"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/discovery-orchestrator.md exists"
[ -f "$F" ] || { exit 1; }

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
tools="$(echo "$front" | grep '^tools:')"
agent_clause="$(echo "$tools" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p')"
assert_eq "1" "$([ -z "$agent_clause" ] && echo 0 || echo 1)" "tools: has an Agent(...) clause"
for leaf in value-critic research-analyst options-generator feasibility-spiker; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF "$leaf" && echo 0 || echo 1)" "Agent(...) includes $leaf"
done
assert_eq "0" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: includes SendMessage"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools: NEVER AskUserQuestion (spec §3.2 rule 7)"
assert_eq "0" "$(echo "$front" | grep -q '^model: inherit$' && echo 0 || echo 1)" "model inherit (model tiers: no agent names a model)"
assert_eq "0" "$(echo "$front" | grep -q '^tier: judgement$' && echo 0 || echo 1)" "tier judgement (orchestrates)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 15$' && echo 0 || echo 1)" "maxTurns 15 (spec §7)"
assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "foreground (only foreground subagents may spawn, spec §3.1)"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qF 'do NOT pre-exist' && echo 0 || echo 1)" "body documents that the leaves do not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'same batch' && echo 0 || echo 1)" "body: the four leaves go in the same message (roster snapshot)"
assert_eq "0" "$(echo "$body" | grep -qF 'scripts/model-resolve.sh' && echo 0 || echo 1)" "body resolves each leaf's model with model-resolve.sh"
assert_eq "0" "$(echo "$body" | grep -qF 'WAITING <n>' && echo 0 || echo 1)" "body ends a turn with WAITING <n> while background leaves run"
assert_eq "0" "$(echo "$body" | grep -qF 'pending: <leaf-1>' && echo 0 || echo 1)" "WAITING names the pending leaves"
assert_eq "0" "$(echo "$body" | grep -qF 'veracity: before writing unverified' && echo 0 || echo 1)" "every leaf gets the veracity line"
assert_eq "0" "$(echo "$body" | grep -qF 'SendMessage(to: "orchestrator"' && echo 0 || echo 1)" "owner messages are forwarded to the root"
assert_eq "0" "$(echo "$body" | grep -qF -- '- Q1 [' && echo 0 || echo 1)" "body defines the - Q<n> [header] batch line format"
assert_eq "0" "$(echo "$body" | grep -qF 'rec:' && echo 0 || echo 1)" "batch lines carry rec: <letter>"
assert_eq "0" "$(echo "$body" | grep -qF 'mem-manifest.sh" summary' && echo 0 || echo 1)" "body mirrors the batch into run summary"
assert_eq "0" "$(echo "$body" | grep -qF 'mem-manifest.sh" register' && echo 0 || echo 1)" "body registers each leaf in the run manifest (spec §5)"
assert_eq "0" "$(echo "$body" | grep -qF 'operation: spike --question' && echo 0 || echo 1)" "body passes a concrete question to the spiker"

# allowlist real
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:discovery-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh summary --run adhoc --line \"- Q1 [Valor] · x · A) a · B) b · rec: A\""}}
EOF
)"
assert_eq "" "$out" "discovery-orchestrator can mirror batch lines via mem-manifest.sh summary"
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:discovery-orchestrator", "tool_name": "Bash", "tool_input": {"command": "python3 x.py"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "discovery-orchestrator cannot run python3"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
