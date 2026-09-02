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
#    (find solo lo tiene swarm:memory-curator, el unico agente que lo invoca de verdad:
#     agents/memory-curator.md:54)
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-curator", "tool_name": "Bash", "tool_input": {"command": "find . -name '*.php' | grep Foo"}}
EOF
)"
assert_eq "" "$out" "piped find | grep with both segments allowlisted is allowed"

# 6b. el `find` real del cuerpo de memory-curator (paso 4, trimming de MEMORY.md) sigue pasando
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-curator", "tool_name": "Bash", "tool_input": {"command": "find .claude/agent-memory -name 'MEMORY.md' -size +25k"}}
EOF
)"
assert_eq "" "$out" "legitimate find from memory-curator step 4 is allowed"

# 6c. find con flags peligrosos -> deny aunque `find` este en el allowlist
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-curator", "tool_name": "Bash", "tool_input": {"command": "find . -delete"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "find -delete is denied"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-curator", "tool_name": "Bash", "tool_input": {"command": "find . -exec rm {} +"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "find -exec is denied"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-curator", "tool_name": "Bash", "tool_input": {"command": "find . -execdir rm {} +"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "find -execdir is denied"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-curator", "tool_name": "Bash", "tool_input": {"command": "find . -ok rm {} ;"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "find -ok is denied"

# 6d. `find` retirado de los agentes que NO lo invocan (I1: escape hatch sin uso)
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-builder", "tool_name": "Bash", "tool_input": {"command": "find . -name '*.php'"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "find is denied for memory-builder (never invoked in its body)"

# 6e. python3 / uuidgen ya no son escape hatches para ningun agente (I1)
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-builder", "tool_name": "Bash", "tool_input": {"command": "python3 -c 'import shutil; shutil.rmtree(\".swarm\")'"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "python3 -c is denied for memory-builder"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:orchestrator", "tool_name": "Bash", "tool_input": {"command": "uuidgen"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "uuidgen is denied for orchestrator"

# 7. mem- script invoked via ${CLAUDE_PLUGIN_ROOT} prefix is allowed
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh health"}}
EOF
)"
assert_eq "" "$out" "scripts/mem-*.sh via CLAUDE_PLUGIN_ROOT prefix is allowed"

# 8. prefijo transparente `SWARM_ROOT=<ruta>` (skill swarm-protocol §3): se recorta y se valida
#    el RESTO del segmento con las reglas normales.
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "SWARM_ROOT=/abs/repo/.swarm ${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh health"}}
EOF
)"
assert_eq "" "$out" "SWARM_ROOT= prefix is transparent when the rest is allowlisted"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "SWARM_ROOT=/x rm -rf /"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "SWARM_ROOT= prefix does not launder a disallowed command"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "OTHER_VAR=/x ${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh health"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "only SWARM_ROOT= is a transparent prefix, other env assignments are denied"

# 9. limite de palabra: la primera palabra se compara EXACTA, no por startswith (M1)
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "lsof -i"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "lsof is not matched by the ls prefix"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "ls -la"}}
EOF
)"
assert_eq "" "$out" "ls itself is still allowed"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:orchestrator", "tool_name": "Bash", "tool_input": {"command": "cdrecord dev=/dev/x"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "cdrecord is not matched by the cd prefix"

out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "/opt/evil/mem-pwn"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "a binary whose basename merely starts with mem- is not a scripts/mem-*.sh"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
