#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

_run_hook() {
  python3 "$HOOK"
}

# 1. allowed `git log --oneline` for any agent -> no output/allow
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:reviewer", "tool_name": "Bash", "tool_input": {"command": "git log --oneline -5"}}
EOF
)"
assert_eq "" "$out" "git log --oneline is allowed, no output"

# 2. `rm -rf /` for swarm:memory-curator -> deny
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-curator", "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "rm -rf / is denied for memory-curator"

# 3. chained `git status && rm x` -> deny (identifies the disallowed second segment)
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git status && rm x"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "chained command with disallowed second segment is denied"
assert_eq "0" "$(echo "$out" | grep -qF 'rm x' && echo 0 || echo 1)" "deny reason names the disallowed segment (rm x)"

# 4. quoted `&&` inside a string is NOT treated as a chain break
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git commit -m \"a && b\""}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "quoted && is not split; whole segment evaluated"
assert_eq "0" "$(echo "$out" | grep -qF 'git commit -m' && echo 0 || echo 1)" "deny reason cites the full unsplit segment, not a fragment"

# 5. non-swarm agent_type or missing agent_type -> no output/allow silently
out="$(_run_hook <<'EOF'
{"agent_type": "some-other-agent", "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
EOF
)"
assert_eq "" "$out" "non-swarm agent_type is not policed"

out="$(_run_hook <<'EOF'
{"tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
EOF
)"
assert_eq "" "$out" "missing agent_type is not policed"

# 6. piped `find . | grep x` where both prefixes allowed -> allow
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-builder", "tool_name": "Bash", "tool_input": {"command": "find . -name '*.php' | grep Foo"}}
EOF
)"
assert_eq "" "$out" "piped find | grep with both segments allowlisted is allowed"

# 7. mem- script invoked via ${CLAUDE_PLUGIN_ROOT} prefix is allowed
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh health"}}
EOF
)"
assert_eq "" "$out" "scripts/mem-*.sh via CLAUDE_PLUGIN_ROOT prefix is allowed"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
