#!/usr/bin/env bash
# tests/test_analysis_orchestrator_spawns.sh — cuarta aplicación de la lección de fase 1: un
# orquestador que lanza hojas que NO preexisten necesita Agent(<hojas>) en su frontmatter.
# analysis-orchestrator selecciona un SUBCONJUNTO de sus 7 hojas según el objetivo (a diferencia
# de discovery, que siempre lanza las 4) — pero las 7 tienen que estar en Agent(...) porque
# cualquiera de ellas puede ser la elegida en un run dado.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

F="$PLUGIN_ROOT/agents/analysis-orchestrator.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/analysis-orchestrator.md exists"
[ -f "$F" ] || { exit 1; }

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
tools="$(echo "$front" | grep '^tools:')"
agent_clause="$(echo "$tools" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p')"
assert_eq "1" "$([ -z "$agent_clause" ] && echo 0 || echo 1)" "tools: has an Agent(...) clause"
for leaf in opportunity-analyst architecture-auditor security-auditor vulnerability-scanner performance-analyst data-model-auditor solid-auditor; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF "$leaf" && echo 0 || echo 1)" "Agent(...) includes $leaf"
done
assert_eq "0" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: includes SendMessage"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools: NEVER AskUserQuestion (spec §3.2 rule 7)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Write' && echo 0 || echo 1)" "tools: read-only, no Write"
assert_eq "1" "$(echo "$tools" | grep -qF 'Edit' && echo 0 || echo 1)" "tools: read-only, no Edit"
assert_eq "0" "$(echo "$front" | grep -q '^model: inherit$' && echo 0 || echo 1)" "model inherit (model tiers: no agent names a model)"
assert_eq "0" "$(echo "$front" | grep -q '^tier: judgement$' && echo 0 || echo 1)" "tier judgement (orchestrates)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 20$' && echo 0 || echo 1)" "maxTurns 20 (spec §7)"
assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "foreground (only foreground subagents may spawn, spec §3.1)"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qF "don't pre-exist" && echo 0 || echo 1)" "body documents that the leaves do not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'same batch' && echo 0 || echo 1)" "body: launched leaves go in the same message (roster snapshot)"
assert_eq "0" "$(echo "$body" | grep -qF 'scripts/model-resolve.sh' && echo 0 || echo 1)" "body resolves each leaf's model with model-resolve.sh"
assert_eq "0" "$(echo "$body" | grep -qF -- '--mark-unavailable' && echo 0 || echo 1)" "body retries a missing model via --mark-unavailable"
assert_eq "0" "$(echo "$body" | grep -qF 'light-tier model downgrade is gone' && echo 0 || echo 1)" "light run tier never weakens a judgement leaf's model"
assert_eq "0" "$(echo "$body" | grep -qF 'scope: infra' && echo 0 || echo 1)" "infra/CI/tooling lens row passes scope: infra"
assert_eq "0" "$(echo "$body" | grep -qF '| infra/CI/tooling:' && echo 0 || echo 1)" "lens table has an infra/CI/tooling row"
assert_eq "0" "$(echo "$body" | grep -qF 'veracity: before writing unverified' && echo 0 || echo 1)" "every lens gets the veracity line"
assert_eq "0" "$(echo "$body" | grep -qF 'ONE message' && echo 0 || echo 1)" "leaves launched in ONE message"
assert_eq "0" "$(echo "$body" | grep -qF 'SendMessage(to: "orchestrator"' && echo 0 || echo 1)" "owner messages are forwarded to the root"
assert_eq "0" "$(echo "$body" | grep -qF 'review-findings:' && echo 0 || echo 1)" "round-2 review findings are forwarded to the lenses"
assert_eq "0" "$(echo "$body" | grep -qF 'mem-manifest.sh" register' && echo 0 || echo 1)" "body registers each launched leaf in the run manifest (spec §5)"
assert_eq "0" "$(echo "$body" | grep -qF "don't re-query" && echo 0 || echo 1)" "body documents it forwards leaf output lines directly instead of re-querying mem-files.sh"
assert_eq "0" "$(echo "$body" | grep -qF '`security-auditor` + `vulnerability-scanner`' && echo 0 || echo 1)" "body documents the lens-selection keyword table (security-shaped objective example)"

# allowlist real
out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:analysis-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh register --run adhoc --agent security-auditor --domain analysis --area . --owner analysis-orchestrator"}}
EOF2
)"
assert_eq "" "$out" "analysis-orchestrator can register a leaf via mem-manifest.sh"
out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:analysis-orchestrator", "tool_name": "Bash", "tool_input": {"command": "python3 x.py"}}
EOF2
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "analysis-orchestrator cannot run python3"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
