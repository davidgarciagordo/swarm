#!/usr/bin/env bash
# tests/test_bash_allowlist_analysis.sh — las 8 agentes del dominio analysis (spec §7 "Análisis")
# tienen su entrada en hooks/bash-allowlist.json: read-only, mismo patrón que value-critic (fase
# 2) — git status/log/diff/show/rev-parse, ls/cat/head/tail/wc/grep, scripts/mem-*.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

guard() { # guard <agent_type> <command> -> "allow" | "deny"
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

for agent in opportunity-analyst architecture-auditor security-auditor vulnerability-scanner performance-analyst data-model-auditor solid-auditor analysis-orchestrator; do
  assert_eq "allow" "$(guard "swarm:$agent" 'cat .swarm/context-pack.md')" "$agent can cat the pack"
  assert_eq "allow" "$(guard "swarm:$agent" 'grep -rn TODO src')" "$agent can grep the repo"
  assert_eq "allow" "$(guard "swarm:$agent" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent x --tag X --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "$agent can write findings via mem-files.sh"
  assert_eq "deny" "$(guard "swarm:$agent" 'python3 x.py')" "$agent cannot run python3 (except vulnerability-scanner degraded mode has no exception either — mechanical scan is grep-only)"
  assert_eq "deny" "$(guard "swarm:$agent" 'rm -rf .swarm')" "$agent cannot rm"
  assert_eq "deny" "$(guard "swarm:$agent" 'echo hi')" "$agent cannot echo (not in allowlist)"
  assert_eq "deny" "$(guard "swarm:$agent" 'find . -name x')" "$agent cannot find (differentiates from the 'default' fallback, which DOES allow find — Important finding from task review)"
done

# Regression guard: confirm these 8 agents are NOT silently relying on the "default" fallback
# (which lacks a real per-agent allowlist and would mask a deleted entry) — default allows
# `find`, the 8 real entries deliberately don't, so this is the one command that tells them apart.
assert_eq "allow" "$(guard 'swarm:totally-unknown-agent' 'find . -name x')" "sanity: an agent with NO allowlist entry at all falls back to default, which DOES allow find (confirms the differentiator is real, not a guard bug)"

# analysis-orchestrator additionally needs mem-manifest.sh register/summary (launches leaves, mirrors merged findings)
assert_eq "allow" "$(guard "swarm:analysis-orchestrator" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh register --run adhoc --agent architecture-auditor --domain analysis --area . --owner analysis-orchestrator')" "analysis-orchestrator can register leaves in the manifest"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
