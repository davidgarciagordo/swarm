#!/usr/bin/env bash
# tests/test_discovery_agents.sh — contrato de los agentes del dominio discovery (spec §7
# "Discovery", §3.2 regla 7). Crece por tarea: T2 añade value-critic + options-generator,
# T3 research-analyst, T4 feasibility-spiker, T5 discovery-orchestrator.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

fm() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
guard() { # guard <agent_type> <command> -> "allow" | "deny"
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# ---------- contrato común a TODO agente del dominio (regla 7: nadie pregunta al owner) ----------
check_common() { # check_common <name> <model> <maxTurns>
  local f="$PLUGIN_ROOT/agents/$1.md" name="$1"
  assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/$name.md exists"
  [ -f "$f" ] || return
  local front tools
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"
  assert_eq "0" "$(echo "$front" | grep -q "^model: $2\$" && echo 0 || echo 1)" "$name model is $2 (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q "^maxTurns: $3\$" && echo 0 || echo 1)" "$name maxTurns is $3 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "$name NEVER has AskUserQuestion (spec §3.2 rule 7)"
  assert_eq "0" "$(has "$tools" 'SendMessage')" "$name has SendMessage (peer-to-peer §5)"
  assert_eq "0" "$(has "$tools" 'Read')" "$name has Read"
  assert_eq "0" "$(has "$(body "$f")" 'discovery --line')" "$name body documents --file discovery --line <ordinal>"
  assert_eq "0" "$(has "$(body "$f")" 'AskUserQuestion')" "$name body says explicitly it never asks the owner"
}

# ---------- T2: value-critic + options-generator ----------
for leaf in value-critic options-generator; do
  f="$PLUGIN_ROOT/agents/$leaf.md"
  case "$leaf" in
    value-critic) check_common "$leaf" opus 8 ;;
    options-generator) check_common "$leaf" opus 10 ;;
  esac
  [ -f "$f" ] || continue
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"
  assert_eq "1" "$(has "$tools" 'Write')" "$leaf is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "$leaf is read-only: no Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "$leaf is a leaf: spawns nobody"
  assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "$leaf is foreground (spec §7)"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "$leaf has no worktree"
  assert_eq "allow" "$(guard "swarm:$leaf" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent x --tag VALUE --file discovery --line 1 --run adhoc --text t --fix f')" "$leaf can write findings via mem-files.sh"
  assert_eq "allow" "$(guard "swarm:$leaf" 'cat .swarm/context-pack.md')" "$leaf can cat the pack"
  assert_eq "deny" "$(guard "swarm:$leaf" 'python3 x.py')" "$leaf cannot run python3"
  assert_eq "deny" "$(guard "swarm:$leaf" 'rm -rf .swarm')" "$leaf cannot rm"
done
assert_eq "0" "$(has "$(body "$PLUGIN_ROOT/agents/value-critic.md" 2>/dev/null)" 'decisions.md')" "value-critic reads decisions.md so it never re-asks a decided question"
assert_eq "0" "$(has "$(body "$PLUGIN_ROOT/agents/options-generator.md" 2>/dev/null)" 'YAGNI')" "options-generator states YAGNI discipline"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
