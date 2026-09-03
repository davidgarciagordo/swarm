#!/usr/bin/env bash
# tests/test_bash_allowlist_implementation.sh — los 5 agentes del núcleo del dominio
# implementation (spec §7 "Implementación") tienen su entrada en hooks/bash-allowlist.json.
# A diferencia de dominios anteriores, `test-writer`/`implementer`/`quality-fixer` NO son
# read-only: necesitan git add/commit (implementer, quality-fixer) además del set genérico
# de build/test ya usado por feasibility-spiker. `reviewer` sí es read-only (solo git log/diff).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# reviewer: read-only, mismo patrón que analysis/design
for agent in reviewer; do
  assert_eq "allow" "$(guard "swarm:$agent" 'git diff HEAD~1')" "$agent can git diff"
  assert_eq "allow" "$(guard "swarm:$agent" 'cat .swarm/context-pack.md')" "$agent can cat the pack"
  assert_eq "deny" "$(guard "swarm:$agent" 'git commit -m x')" "$agent (read-only) cannot git commit"
  assert_eq "deny" "$(guard "swarm:$agent" 'rm -rf .swarm')" "$agent cannot rm"
done

# test-writer, implementer, quality-fixer: SÍ pueden git add/commit (necesitan capturar su propio trabajo)
for agent in test-writer implementer quality-fixer; do
  assert_eq "allow" "$(guard "swarm:$agent" 'git add -A')" "$agent can git add"
  assert_eq "allow" "$(guard "swarm:$agent" 'git commit -m "wip"')" "$agent can git commit"
  assert_eq "allow" "$(guard "swarm:$agent" 'php vendor/bin/phpunit')" "$agent can run generic test/build tools"
  assert_eq "deny" "$(guard "swarm:$agent" 'git push origin master')" "$agent cannot push (delivery's job, fase 6)"
  assert_eq "deny" "$(guard "swarm:$agent" 'rm -rf /')" "$agent cannot rm -rf /"
done

# solo implementation-orchestrator tiene git merge + git worktree (fusiona/limpia el worktree de implementer)
assert_eq "allow" "$(guard "swarm:implementation-orchestrator" 'git merge worktree-agent-abc123')" "implementation-orchestrator can git merge"
assert_eq "allow" "$(guard "swarm:implementation-orchestrator" 'git worktree remove .claude/worktrees/agent-abc123 --force')" "implementation-orchestrator can git worktree remove"
assert_eq "deny" "$(guard "swarm:implementation-orchestrator" 'git push origin master')" "implementation-orchestrator cannot push"
assert_eq "deny" "$(guard "swarm:test-writer" 'git merge x')" "test-writer (leaf) cannot git merge — only the orchestrator merges"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
