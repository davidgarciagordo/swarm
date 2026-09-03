#!/usr/bin/env bash
# tests/test_implementation_agents.sh — contrato de los agentes del núcleo de implementation
# (spec §7 "Implementación"). Crece por tarea: T2 test-writer, T3 quality-fixer, T4 reviewer,
# T5 implementer, T6 implementation-orchestrator.
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

# ---------- T2: test-writer ----------
f="$PLUGIN_ROOT/agents/test-writer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/test-writer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "test-writer model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 20$' && echo 0 || echo 1)" "test-writer maxTurns is 20 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "test-writer NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Write')" "test-writer HAS Write (writes real test files)"
  assert_eq "0" "$(has "$tools" 'Edit')" "test-writer HAS Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "test-writer is a leaf: spawns nobody"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "test-writer has NO worktree isolation (writes to the run's main checkout)"
  assert_eq "0" "$(has "$b" 'RED')" "test-writer documents confirming RED before committing"
  assert_eq "0" "$(has "$b" 'git commit')" "test-writer documents committing its failing test directly"
  assert_eq "allow" "$(guard "swarm:test-writer" 'git add -A')" "test-writer can git add"
  assert_eq "allow" "$(guard "swarm:test-writer" 'git commit -m x')" "test-writer can git commit"
  assert_eq "deny" "$(guard "swarm:test-writer" 'git push origin master')" "test-writer cannot push"
fi


# ---------- T3: quality-fixer (mecánico, siempre haiku) ----------
f="$PLUGIN_ROOT/agents/quality-fixer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/quality-fixer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: haiku$' && echo 0 || echo 1)" "quality-fixer model is haiku always (spec §7.0, mechanical leaf)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 10$' && echo 0 || echo 1)" "quality-fixer maxTurns is 10 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "quality-fixer NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Edit')" "quality-fixer HAS Edit (parchea residual)"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "quality-fixer has NO worktree isolation of its own (points at implementer's)"
  assert_eq "0" "$(has "$b" 'ruta absoluta')" "quality-fixer documents receiving implementer's worktree as an absolute path"
  assert_eq "0" "$(has "$b" '--fix')" "quality-fixer documents running --fix tools before manual patching"
  assert_eq "allow" "$(guard "swarm:quality-fixer" 'git commit -m x')" "quality-fixer can commit its fixes"
fi


# ---------- T4: reviewer (read-only, gate ANTES del merge) ----------
f="$PLUGIN_ROOT/agents/reviewer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/reviewer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: opus$' && echo 0 || echo 1)" "reviewer model is opus (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 15$' && echo 0 || echo 1)" "reviewer maxTurns is 15 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "reviewer NEVER has AskUserQuestion"
  assert_eq "1" "$(has "$tools" 'Write')" "reviewer is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "reviewer is read-only: no Edit"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "reviewer has NO worktree isolation of its own"
  assert_eq "0" "$(has "$b" 'Critical')" "reviewer documents Critical severity"
  assert_eq "0" "$(has "$b" 'Important')" "reviewer documents Important severity"
  assert_eq "0" "$(has "$b" 'Minor')" "reviewer documents Minor severity"
  assert_eq "0" "$(has "$b" 'ANTES')" "reviewer documents it runs BEFORE the merge, not after"
  assert_eq "deny" "$(guard "swarm:reviewer" 'git commit -m x')" "reviewer (read-only) cannot commit"
fi


# ---------- T5: implementer (isolation: worktree, único código de aplicación real de este dominio) ----------
f="$PLUGIN_ROOT/agents/implementer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/implementer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "implementer model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 30$' && echo 0 || echo 1)" "implementer maxTurns is 30 (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^isolation: worktree$' && echo 0 || echo 1)" "implementer runs in isolation: worktree (spec §7/§9.3)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "implementer NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Write')" "implementer HAS Write (real application code)"
  assert_eq "0" "$(has "$tools" 'Edit')" "implementer HAS Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "implementer is a leaf: spawns nobody (2-level hierarchy, spec §3.2 rule 8)"
  assert_eq "0" "$(has "$b" 'git commit')" "implementer documents committing its own work in its own worktree"
  assert_eq "0" "$(has "$b" 'GREEN')" "implementer documents confirming GREEN before committing"
  assert_eq "0" "$(has "$b" '- [x] Step')" "implementer documents flipping the plan's step checkboxes as part of its commit"
  assert_eq "allow" "$(guard "swarm:implementer" 'git add -A')" "implementer can git add in its own worktree"
  assert_eq "allow" "$(guard "swarm:implementer" 'git commit -m x')" "implementer can git commit"
  assert_eq "deny" "$(guard "swarm:implementer" 'git merge x')" "implementer (leaf) cannot merge — only the orchestrator merges"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
