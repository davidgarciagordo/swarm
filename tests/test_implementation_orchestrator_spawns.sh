#!/usr/bin/env bash
# tests/test_implementation_orchestrator_spawns.sh — sexta aplicación de la lección de fase 1:
# un orquestador que lanza hojas que NO preexisten necesita Agent(<hojas>) en su frontmatter.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

F="$PLUGIN_ROOT/agents/implementation-orchestrator.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/implementation-orchestrator.md exists"
[ -f "$F" ] || { exit 1; }

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
tools="$(echo "$front" | grep '^tools:')"
agent_clause="$(echo "$tools" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p')"
assert_eq "1" "$([ -z "$agent_clause" ] && echo 0 || echo 1)" "tools: has an Agent(...) clause"
for leaf in test-writer implementer quality-fixer reviewer migration-engineer doc-writer; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF "$leaf" && echo 0 || echo 1)" "Agent(...) includes $leaf"
done
assert_eq "0" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: includes SendMessage"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools: NEVER AskUserQuestion"
assert_eq "1" "$(echo "$tools" | grep -qF 'Write' && echo 0 || echo 1)" "tools: no Write (implementer/test-writer write, not the orchestrator)"
assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "model sonnet (spec §7)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 25$' && echo 0 || echo 1)" "maxTurns 25 (spec §7)"
assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "foreground (only foreground subagents may spawn)"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qF 'No preexiste' && echo 0 || echo 1)" "body documents that leaves do not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'UNA fase' && echo 0 || echo 1)" "body documents it handles ONE phase per invocation"
assert_eq "0" "$(echo "$body" | grep -qF 'ANTES de fusionar' && echo 0 || echo 1)" "body documents the review gate happens BEFORE merge"
assert_eq "0" "$(echo "$body" | grep -qF 'git merge' && echo 0 || echo 1)" "body documents the local merge mechanism"
assert_eq "0" "$(echo "$body" | grep -qF 'NUNCA a `master`' && echo 0 || echo 1)" "body documents the merge is always local, never to master/shared branch"
assert_eq "0" "$(echo "$body" | grep -qF 'Máximo 2 rondas' && echo 0 || echo 1)" "body documents the 2-round fix-loop cap"

out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:implementation-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git merge worktree-agent-abc"}}
EOF2
)"
assert_eq "" "$out" "implementation-orchestrator can git merge"
out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:implementation-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git push origin master"}}
EOF2
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "implementation-orchestrator cannot push"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
