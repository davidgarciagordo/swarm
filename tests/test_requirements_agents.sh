#!/usr/bin/env bash
# tests/test_requirements_agents.sh — contrato de las hojas del dominio requirements añadidas en
# fase 5b (spec §7 "Requisitos"). Crece por tarea: T3 dependency-auditor, T4 dependency-installer.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

fm() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# ---------- T3: dependency-auditor ----------
f="$PLUGIN_ROOT/agents/dependency-auditor.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/dependency-auditor.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "dependency-auditor model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 12$' && echo 0 || echo 1)" "dependency-auditor maxTurns is 12 (spec §7)"
  assert_eq "1" "$(has "$tools" 'Write')" "dependency-auditor is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "dependency-auditor is read-only: no Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "dependency-auditor is a leaf: spawns nobody"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "dependency-auditor never asks the owner"
  assert_eq "0" "$(has "$tools" 'SendMessage')" "dependency-auditor has SendMessage (peer-to-peer §5)"
  assert_eq "0" "$(has "$b" 'pack:')" "dependency-auditor documents the pack: header line"
  assert_eq "0" "$(has "$b" 'scan-deps')" "dependency-auditor uses the pack scan-deps key"
  assert_eq "0" "$(has "$b" 'outdated')" "dependency-auditor uses the pack outdated key"
  assert_eq "0" "$(has "$b" 'licenses')" "dependency-auditor covers licenses (spec §7)"
  assert_eq "0" "$(has "$b" 'sin pack')" "dependency-auditor documents the no-pack fallback (spec §8)"
  assert_eq "0" "$(has "$b" 'DEP ·')" "dependency-auditor documents its DEP finding tag"
  assert_eq "0" "$(has "$b" 'nunca instala')" "dependency-auditor states it never installs anything"
fi

# ---------- T4: dependency-installer (MUTANTE — gate de aprobación) ----------
f="$PLUGIN_ROOT/agents/dependency-installer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/dependency-installer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "dependency-installer model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 10$' && echo 0 || echo 1)" "dependency-installer maxTurns is 10 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "dependency-installer never asks the owner itself (§3.2 rule 7)"
  assert_eq "1" "$(has "$tools" 'Agent')" "dependency-installer is a leaf: spawns nobody"
  assert_eq "0" "$(has "$b" 'approved:')" "dependency-installer documents the approved: header line"
  assert_eq "0" "$(has "$b" 'BLOCKED sin aprobación del owner')" "dependency-installer BLOCKs without explicit approval"
  assert_eq "0" "$(has "$b" 'nunca commiteas')" "dependency-installer never commits (ruling 3)"
  assert_eq "0" "$(has "$b" 'brew')" "dependency-installer explains why OS packages are out of scope"
  assert_eq "0" "$(has "$b" 'literal')" "dependency-installer installs only literally approved package ids"
  # el par auditor/installer no puede confundirse: uno lee, el otro escribe
  assert_eq "1" "$(has "$b" 'composer remove')" "dependency-installer does not document uninstalling (ruling 4)"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
