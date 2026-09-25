#!/usr/bin/env bash
# tests/test_analysis_agents.sh — contrato de los agentes del dominio analysis (spec §7 "Análisis
# (read-only)", §2 principio 7). Crece por tarea: T2 opportunity-analyst+architecture-auditor,
# T3 security-auditor+vulnerability-scanner, T4 performance-analyst+data-model-auditor,
# T5 analysis-orchestrator.
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

# check_leaf <name> <tier> <maxTurns> <tag>
check_leaf() {
  local f="$PLUGIN_ROOT/agents/$1.md" name="$1" tag="$4"
  assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/$name.md exists"
  [ -f "$f" ] || return
  local front tools b
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: inherit$' && echo 0 || echo 1)" "$name model is inherit (MODEL TIERS contract)"
  assert_eq "0" "$(echo "$front" | grep -q "^tier: $2\$" && echo 0 || echo 1)" "$name tier is $2 (MODEL TIERS contract)"
  assert_eq "0" "$(echo "$front" | grep -q "^maxTurns: $3\$" && echo 0 || echo 1)" "$name maxTurns is $3 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "$name NEVER has AskUserQuestion"
  assert_eq "1" "$(has "$tools" 'Write')" "$name is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "$name is read-only: no Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "$name is a leaf: spawns nobody"
  assert_eq "0" "$(has "$tools" 'SendMessage')" "$name has SendMessage (peer-to-peer §5)"
  assert_eq "0" "$(has "$tools" 'Read')" "$name has Read"
  assert_eq "0" "$(has "$tools" 'Grep')" "$name has Grep"
  assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "$name is foreground (spec §7)"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "$name has no worktree (read-only, no spike)"
  assert_eq "0" "$(echo "$front" | grep -q '^skills: \[swarm-protocol\]$' && echo 0 || echo 1)" "$name preloads swarm-protocol"
  assert_eq "0" "$(has "$b" "$tag ·")" "$name documents its own tag ($tag) in an output example"
  assert_eq "0" "$(has "$b" 'sanitization')" "$name documents the sanitization rule for repo code it quotes"
  assert_eq "allow" "$(guard "swarm:$name" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent '"$name"' --tag '"$tag"' --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "$name can write findings"
  assert_eq "deny" "$(guard "swarm:$name" 'python3 x.py')" "$name cannot run python3"
}

# ---------- T2: opportunity-analyst + architecture-auditor ----------
check_leaf opportunity-analyst judgement 15 OPP
check_leaf architecture-auditor judgement 15 ARCH
f="$PLUGIN_ROOT/agents/opportunity-analyst.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'ROI')" "opportunity-analyst documents ROI framing (spec §7)"
f="$PLUGIN_ROOT/agents/architecture-auditor.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'invariant')" "architecture-auditor documents architectural invariants (spec §7)"


# ---------- T3: security-auditor + vulnerability-scanner ----------
check_leaf security-auditor judgement 15 SEC
f="$PLUGIN_ROOT/agents/security-auditor.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'tenant')" "security-auditor documents tenant/data isolation (spec §7)"

f="$PLUGIN_ROOT/agents/vulnerability-scanner.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/vulnerability-scanner.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: inherit$' && echo 0 || echo 1)" "vulnerability-scanner model is inherit (MODEL TIERS contract)"
  assert_eq "0" "$(echo "$front" | grep -q '^tier: mechanical$' && echo 0 || echo 1)" "vulnerability-scanner tier is mechanical always (MODEL TIERS contract)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 10$' && echo 0 || echo 1)" "vulnerability-scanner maxTurns is 10 (spec §7)"
  assert_eq "1" "$(has "$tools" 'Write')" "vulnerability-scanner is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "vulnerability-scanner NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Grep')" "vulnerability-scanner has Grep (its deterministic scan tool)"
  assert_eq "0" "$(has "$b" 'VULN ·')" "vulnerability-scanner documents its tag (VULN)"
  assert_eq "0" "$(has "$b" 'no pack')" "vulnerability-scanner documents its degraded no-pack behavior (spec §8)"
  assert_eq "allow" "$(guard "swarm:vulnerability-scanner" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent vulnerability-scanner --tag VULN --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "vulnerability-scanner can write findings"
fi


# ---------- T4: performance-analyst + data-model-auditor (judgement, auditors/lenses) ----------
check_leaf performance-analyst judgement 15 PERF
f="$PLUGIN_ROOT/agents/performance-analyst.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'N+1')" "performance-analyst documents N+1 queries (spec §7)"

check_leaf data-model-auditor judgement 15 DATA
f="$PLUGIN_ROOT/agents/data-model-auditor.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'migrat')" "data-model-auditor documents schema/migration drift (spec §7)"


# ---------- T6: solid-auditor (SOLID/design-principle violations, cross-language by design) ----------
check_leaf solid-auditor judgement 15 SOLID
f="$PLUGIN_ROOT/agents/solid-auditor.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'SRP')" "solid-auditor documents SRP (spec §7)"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'architecture-auditor')" "solid-auditor documents its boundary vs architecture-auditor"

# header lines sent by analysis-orchestrator: `scope: infra` (infra row) and `review-findings:` (round 2)
for a in architecture-auditor security-auditor performance-analyst vulnerability-scanner; do
  assert_eq "0" "$(has "$(body "$PLUGIN_ROOT/agents/$a.md")" 'scope: infra')" "$a documents the scope: infra header line"
done
for a in architecture-auditor security-auditor performance-analyst vulnerability-scanner opportunity-analyst data-model-auditor solid-auditor; do
  assert_eq "0" "$(has "$(body "$PLUGIN_ROOT/agents/$a.md")" 'review-findings:')" "$a documents the round-2 review-findings header line"
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
