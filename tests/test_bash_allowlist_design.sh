#!/usr/bin/env bash
# tests/test_bash_allowlist_design.sh — los 4 agentes del dominio design (spec §7 "Diseño") tienen
# su entrada en hooks/bash-allowlist.json: read-only Bash (planner escribe el plan vía el tool
# Write nativo, NUNCA vía Bash — su allowlist de Bash es la misma read-only que los demás).
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

for agent in planner pattern-advisor domain-modeler design-orchestrator; do
  assert_eq "allow" "$(guard "swarm:$agent" 'cat .swarm/context-pack.md')" "$agent can cat the pack"
  assert_eq "allow" "$(guard "swarm:$agent" 'grep -rn TODO src')" "$agent can grep the repo"
  assert_eq "allow" "$(guard "swarm:$agent" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent x --tag X --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "$agent can write findings via mem-files.sh"
  assert_eq "deny" "$(guard "swarm:$agent" 'find . -name x')" "$agent cannot find (differentiates from default fallback)"
  assert_eq "deny" "$(guard "swarm:$agent" 'python3 x.py')" "$agent cannot run python3"
  assert_eq "deny" "$(guard "swarm:$agent" 'rm -rf .swarm')" "$agent cannot rm"
  assert_eq "deny" "$(guard "swarm:$agent" 'echo hi')" "$agent cannot echo"
done

assert_eq "allow" "$(guard "swarm:design-orchestrator" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh register --run adhoc --agent planner --domain design --area . --owner design-orchestrator')" "design-orchestrator can register leaves in the manifest"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
