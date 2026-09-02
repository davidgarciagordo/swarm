#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
SKILL_FILE="$PLUGIN_ROOT/skills/swarm-protocol/SKILL.md"

assert_eq "0" "$( [ -f "$SKILL_FILE" ]; echo $? )" "SKILL.md exists"
assert_file_contains "$SKILL_FILE" "evidence: files=" "mentions evidence contract format"
assert_file_contains "$SKILL_FILE" "run/adhoc" "mentions adhoc run mode"
assert_file_contains "$SKILL_FILE" "mailbox" "mentions mailbox"
assert_file_contains "$SKILL_FILE" "SWARM_ROOT" "mentions SWARM_ROOT"
assert_file_contains "$PLUGIN_ROOT/skills/swarm-protocol/SKILL.md" '^tier: ' "SKILL.md §2 documents the optional tier: header line (fase 2)"
assert_file_contains "$PLUGIN_ROOT/skills/swarm-protocol/SKILL.md" '^objective: ' "SKILL.md §2 documents the objective: header line (fase 2, P2-b)"

# bug real (sonda 2026-09-02): $RUN/$SWARM_ROOT no existen entre llamadas Bash (sin export, sin
# hook que los inyecte) — ningún ejemplo copiable debe usarlos como si fueran variables de shell.
assert_eq "1" "$(grep -c '\${RUN:-adhoc}"' "$SKILL_FILE"; true)" "no example still expands \${RUN:-adhoc} as a real shell variable (only the explanatory §1 mention remains)"
assert_eq "0" "$(grep -cE '"\$RUN"' "$SKILL_FILE"; true)" "no example uses bare \"\$RUN\" as a real shell variable"
assert_file_contains "$SKILL_FILE" "PLACEHOLDERS" "SKILL.md §1 explicitly warns SWARM_ROOT/RUN in examples are placeholders, not real shell vars"
assert_eq "0" "$(grep -icE 'sustituye literalmente' "$SKILL_FILE" >/dev/null; echo $?)" "SKILL.md §1 documents the literal-substitution rule (matches agents/orchestrator.md §2.1)"

# bug real: SWARM_ROOT=<valor> con continuación de línea \\ lo deniega bash-guard (shlex trocea la
# continuación en un token '\n' fuera de cualquier allowlist) -- el ejemplo de §3 debe ser una sola
# línea real, no solo visualmente (el fence puede seguir usando \\ SOLO donde de verdad pasa el guard).
GUARD="$PLUGIN_ROOT/hooks/bash-guard.py"
swarm_root_example="$(awk '/^SWARM_ROOT=.*mem-files\.sh. query/{print; exit}' "$SKILL_FILE")"
assert_eq "0" "$([ -n "$swarm_root_example" ]; echo $?)" "SKILL.md §3 still has the SWARM_ROOT= worktree example"
if [ -n "$swarm_root_example" ]; then
  guard_out="$(printf '{"agent_type": "swarm:value-critic", "tool_name": "Bash", "tool_input": {"command": %s}}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$swarm_root_example")" | python3 "$GUARD")"
  assert_eq "" "$guard_out" "SKILL.md §3 SWARM_ROOT= example is on one line and passes bash-guard (was denied as multiline)"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
