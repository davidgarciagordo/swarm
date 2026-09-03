#!/usr/bin/env bash
# tests/test_design_agents.sh — contrato de los agentes del dominio design (spec §7 "Diseño").
# Crece por tarea: T2 pattern-advisor+domain-modeler, T3 planner, T4 design-orchestrator.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

fm() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

check_readonly_leaf() { # check_readonly_leaf <name> <model> <maxTurns> <tag>
  local f="$PLUGIN_ROOT/agents/$1.md" name="$1" tag="$4"
  assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/$name.md exists"
  [ -f "$f" ] || return
  local front tools b
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q "^model: $2\$" && echo 0 || echo 1)" "$name model is $2 (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q "^maxTurns: $3\$" && echo 0 || echo 1)" "$name maxTurns is $3 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "$name NEVER has AskUserQuestion"
  assert_eq "1" "$(has "$tools" 'Write')" "$name is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "$name is read-only: no Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "$name is a leaf: spawns nobody"
  assert_eq "0" "$(has "$tools" 'SendMessage')" "$name has SendMessage"
  assert_eq "0" "$(has "$tools" 'Read')" "$name has Read"
  assert_eq "0" "$(has "$tools" 'Grep')" "$name has Grep"
  assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "$name is foreground"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "$name has no worktree"
  assert_eq "0" "$(echo "$front" | grep -q '^skills: \[swarm-protocol\]$' && echo 0 || echo 1)" "$name preloads swarm-protocol"
  assert_eq "0" "$(has "$b" "$tag ·")" "$name documents its own tag ($tag) in an output example"
  assert_eq "0" "$(has "$b" 'saneado')" "$name documents the sanitization rule for repo code it quotes"
  assert_eq "allow" "$(guard "swarm:$name" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent '"$name"' --tag '"$tag"' --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "$name can write findings"
  assert_eq "deny" "$(guard "swarm:$name" 'python3 x.py')" "$name cannot run python3"
}

# ---------- T2: pattern-advisor + domain-modeler ----------
check_readonly_leaf pattern-advisor opus 10 PATTERN
f="$PLUGIN_ROOT/agents/pattern-advisor.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'reuse')" "pattern-advisor documents the reuse|introduce verdict (spec §7)"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'introduce')" "pattern-advisor documents the introduce verdict (spec §7)"

check_readonly_leaf domain-modeler opus 15 MODEL
f="$PLUGIN_ROOT/agents/domain-modeler.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'invariante')" "domain-modeler documents invariants (spec §7)"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'agregado')" "domain-modeler documents aggregates (spec §7)"


# ---------- T3: planner (único leaf del dominio con Write/Edit) ----------
f="$PLUGIN_ROOT/agents/planner.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/planner.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: opus$' && echo 0 || echo 1)" "planner model is opus (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 20$' && echo 0 || echo 1)" "planner maxTurns is 20 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "planner NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Write')" "planner HAS Write (the one exception in this domain)"
  assert_eq "0" "$(has "$tools" 'Edit')" "planner HAS Edit (revises its own draft)"
  assert_eq "1" "$(has "$tools" 'Agent')" "planner is a leaf: spawns nobody"
  assert_eq "0" "$(has "$tools" 'SendMessage')" "planner has SendMessage"
  assert_eq "0" "$(has "$b" 'docs/superpowers/plans/')" "planner documents writing to docs/superpowers/plans/"
  assert_eq "0" "$(has "$b" '**Objective:**')" "planner documents the Objective: header line for idempotency"
  assert_eq "0" "$(has "$b" '**Grill:** pendiente')" "planner's template writes the Grill: pendiente marker"
  assert_eq "0" "$(has "$b" 'arbitrado')" "planner documents flipping the Grill marker to arbitrado on close"
  assert_eq "0" "$(has "$b" 'saneado')" "planner documents the sanitization rule for anything it DOES put in a shell arg"
  assert_eq "allow" "$(guard "swarm:planner" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent planner --tag PLAN --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "planner can write findings"
  assert_eq "deny" "$(guard "swarm:planner" 'python3 x.py')" "planner cannot run python3"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
