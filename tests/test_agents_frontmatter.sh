#!/usr/bin/env bash
# tests/test_agents_frontmatter.sh — contrato de frontmatter para TODO agents/*.md
# (spec §3.1, skills/swarm-protocol/SKILL.md §7). Glob dinámico: cubre los agentes de
# hoy y cualquier agente futuro (orchestrator de Task 12, hojas de fases posteriores).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

for f in "$PLUGIN_ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$f")"

  assert_eq "0" "$(echo "$frontmatter" | grep -q '^name:' && echo 0 || echo 1)" "$name has name"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^description:' && echo 0 || echo 1)" "$name has description"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^model:' && echo 0 || echo 1)" "$name has model"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^tools:' && echo 0 || echo 1)" "$name has tools"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^maxTurns:' && echo 0 || echo 1)" "$name has maxTurns"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^memory:' && echo 0 || echo 1)" "$name has memory"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^skills:' && echo 0 || echo 1)" "$name has skills"

  # verifier is read-only and never invokes SendMessage (it's never called by a domain, only by root).
  # grill-architect/operator/engineer are the same shape: read-only judges that receive their
  # target's path directly in the launch prompt, never talk to memory-orchestrator or a sibling —
  # same contract as working-methods' external grill-* lenses, which also have no SendMessage.
  case "$name" in
    verifier.md|grill-architect.md|grill-operator.md|grill-engineer.md) ;;
    *)
      assert_eq "0" "$(echo "$frontmatter" | grep -q 'SendMessage' && echo 0 || echo 1)" "$name tools include SendMessage"
      ;;
  esac

  assert_eq "1" "$(echo "$frontmatter" | grep -q '^hooks:' && echo 0 || echo 1)" "$name frontmatter has no hooks:"
  assert_eq "1" "$(echo "$frontmatter" | grep -q '^mcpServers:' && echo 0 || echo 1)" "$name frontmatter has no mcpServers:"
  assert_eq "1" "$(echo "$frontmatter" | grep -q '^permissionMode:' && echo 0 || echo 1)" "$name frontmatter has no permissionMode:"
  assert_eq "1" "$(echo "$frontmatter" | grep -q 'Bash(' && echo 0 || echo 1)" "$name frontmatter has no Bash( subcommand syntax"
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
