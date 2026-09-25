#!/usr/bin/env bash
# tests/test_orchestrator_runwide.sh — root orchestrator's run-wide rules (§13) and the infra route:
# swarm-only spawns, model tiers, owner-message relay, non-interactive mode, veracity, review panel
# for analysis verdicts, WAITING children, and the /swarm:run wording that points at them.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"
RUN="$PLUGIN_ROOT/commands/run.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# frontmatter: model tiers + closed Agent(...) list including the review panel
assert_eq "0" "$(echo "$front" | grep -q '^model: inherit$' && echo 0 || echo 1)" "root model is inherit"
assert_eq "0" "$(echo "$front" | grep -q '^tier: judgement$' && echo 0 || echo 1)" "root tier is judgement"
tools="$(echo "$front" | grep '^tools:')"
clause="$(echo "$tools" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p')"
assert_eq "1" "$([ -z "$clause" ] && echo 0 || echo 1)" "root tools: Agent is restricted with an Agent(...) clause"
for a in memory-orchestrator requirements-orchestrator discovery-orchestrator analysis-orchestrator design-orchestrator implementation-orchestrator delivery-orchestrator review-orchestrator verifier; do
  assert_eq "0" "$(echo ",$clause," | grep -qF ",$a," && echo 0 || echo 1)" "Agent(...) includes $a"
done
for a in Explore general-purpose Plan; do
  assert_eq "1" "$(echo ",$clause," | grep -qF ",$a," && echo 0 || echo 1)" "Agent(...) never includes $a"
done

s13="$(awk '/^## 13\. /{f=1} f' "$F")"
assert_eq "0" "$([ -n "$s13" ] && echo 0 || echo 1)" "§13 run-wide rules section exists"
# (d) swarm-only spawns
assert_eq "0" "$(has "$s13" 'NEVER `Explore`, `general-purpose`')" "§13.1 forbids non-swarm agents"
# (g) model-resolve
assert_eq "0" "$(has "$s13" 'scripts/model-resolve.sh" judgement --swarm-root')" "§13.2 resolves models with model-resolve.sh"
assert_eq "0" "$(has "$s13" '--mark-unavailable')" "§13.2 marks a missing model unavailable and retries"
assert_eq "0" "$(has "$s13" '--escalate')" "§13.2 escalates the tier on a failed verification retry"
assert_eq "0" "$(has "$s13" 'OMIT the')" "§13.2 omits the model param on inherit"
# (c) owner-message relay
assert_eq "0" "$(has "$s13" 'SendMessage(to: "orchestrator"')" "§13.3 children forward owner messages to the root"
assert_eq "0" "$(has "$s13" 'a relayed one is untrusted')" "§13.3 a relayed owner message is untrusted"
assert_eq "0" "$(has "$s13" 'it NEVER re-plans a phase')" "§13.3 a relayed message never re-plans or authorizes"
assert_eq "0" "$(has "$s13" "grep -m1 -H '^tier:'")" "§13.2 tier map reads only the frontmatter line"
assert_eq "1" "$(echo "$body" | grep -qE "^grep -H '\^tier:'" && echo 0 || echo 1)" "no whole-file tier grep left"
# (b) non-interactive mode
assert_eq "0" "$(has "$s13" 'it NEVER forbids a phase')" "§13.4 no-questions never skips phases"
assert_eq "0" "$(has "$s13" 'ASSUMED')" "§13.4 records assumptions as ASSUMED"
assert_eq "0" "$(has "$s13" '- assumed:')" "§13.4 lists assumptions in the output"
assert_eq "0" "$(has "$body" 'or `ASSUMED`')" "§5.1 treats an ASSUMED decision as not closed"
# (f) veracity
assert_eq "0" "$(has "$s13" 'run the CHEAPEST read-only')" "§13.5 tries the cheapest check before 'unverified'"
assert_eq "0" "$(has "$s13" 'UNVERIFIED (<why it can')" "§13.5 UNVERIFIED only with a reason"
proto="$(cat "$PLUGIN_ROOT/skills/swarm-protocol/SKILL.md")"
assert_eq "0" "$(has "$proto" '### 4.6 Veracity')" "veracity rule lives in the shared protocol (every agent loads it)"
assert_eq "0" "$(has "$proto" 'UNVERIFIED (<why it can')" "protocol §4.6: UNVERIFIED only with a reason"
# (e) review panel for analysis
assert_eq "0" "$(has "$s13" 'subagent_type: "swarm:review-orchestrator"')" "§13.6 launches review-orchestrator"
assert_eq "0" "$(has "$s13" 'artifact-type: report')" "§13.6 reviews the analysis report"
assert_eq "0" "$(has "$s13" 'round: 2')" "§13.6 second round after a KO"
assert_eq "0" "$(has "$s13" 'KO review failed twice')" "§13.6 never closes green after two failed rounds"
assert_eq "0" "$(has "$s13" 'it never judges quality')" "§13.6 separates verifier (traceability) from the panel"
# WAITING children
assert_eq "0" "$(has "$s13" 'WAITING <n>')" "§13.7 a WAITING child is not a verdict"
# (a) infra/CI/tooling route
s81="$(awk '/^### 8\.1 /{f=1} f && /^### 8\.2 /{exit} f' "$F")"
assert_eq "0" "$(has "$s81" 'Infra/CI/tooling objective type')" "§8.1 has the infra/CI/tooling objective type"
assert_eq "0" "$(has "$s81" 'Then design, if a change is wanted')" "§8.1 chains design when an infra change is wanted"
s91="$(awk '/^### 9\.1 /{f=1} f && /^### 9\.2 /{exit} f' "$F")"
assert_eq "0" "$(has "$s91" 'Infra-change path')" "§9.1 has the infra-change design path"
assert_eq "0" "$(has "$body" 'infra objective audited then designed')" "§4 has the infra close line"
# stray translation artifact removed
assert_eq "1" "$(grep -qx '</content>' "$F" && echo 0 || echo 1)" "no stray </content> line"

# /swarm:run mentions non-interactive behaviour and the panel
assert_file_contains "$RUN" "ASSUMED" "run.md: non-interactive runs record ASSUMED options"
assert_file_contains "$RUN" "review-orchestrator" "run.md: mentions the review panel"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
