#!/usr/bin/env bash
# tests/test_review_panel.sh — review panel contract (skills/swarm-protocol/judgement.md):
# lens selection per artifact-type/tier, deterministic dedup, refuter step, blind judge,
# one retry then escalate, judgements.jsonl append.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
S="$PLUGIN_ROOT/scripts/review-dedup.sh"
RO="$PLUGIN_ROOT/agents/review-orchestrator.md"
POLICY="$PLUGIN_ROOT/skills/swarm-protocol/judgement.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/swarm-panel.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
fm() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
lenses() { "$S" lenses "$@" | tr '\n' ' ' | sed 's/ $//'; }

# ---------- lens selection (deterministic) ----------
assert_eq "fact-checker grill-engineer" "$(lenses --artifact-type plan --tier light)" "light plan: fact-checker + defect-hunter only"
assert_eq "fact-checker grill-engineer" "$(lenses --artifact-type diff --tier light)" "light diff: fact-checker + defect-hunter only"
assert_eq "fact-checker grill-engineer" "$(lenses --artifact-type report --tier light)" "light report: fact-checker + defect-hunter only"
assert_eq "completeness-critic grill-engineer grill-architect grill-operator fact-checker simplicity-critic" \
  "$(lenses --artifact-type plan --tier full)" "full plan: all 6 lenses"
assert_eq "grill-engineer grill-architect fact-checker completeness-critic" \
  "$(lenses --artifact-type diff --tier full)" "full diff: defect-hunter, rules-auditor, fact-checker, completeness-critic"
assert_eq "fact-checker completeness-critic" "$(lenses --artifact-type report --tier full)" "full report: fact-checker + completeness-critic"
wm="$(lenses --artifact-type plan --tier full --working-methods)"
assert_eq "completeness-critic working-methods:grill-engineer working-methods:grill-architect working-methods:grill-operator fact-checker simplicity-critic" \
  "$wm" "working-methods replaces the 3 grill lenses"
assert_eq "1" "$(echo " $wm " | grep -qE ' grill-(engineer|architect|operator) ' && echo 0 || echo 1)" "never both lens families in one panel"
assert_exit 64 "invalid artifact-type rejected" "$S" lenses --artifact-type essay --tier full 2>/dev/null
assert_exit 64 "invalid tier rejected" "$S" lenses --artifact-type plan --tier medium 2>/dev/null

# ---------- lens / leaf agents: exist, tier judgement, no model name, one TAG each ----------
for pair in completeness-critic:MISSING fact-checker:FACT simplicity-critic:SIMPLER \
            grill-engineer:DEFECT grill-architect:RULES grill-operator:OPERATOR refuter:UPHELD blind-judge:score; do
  a="${pair%%:*}"; tag="${pair#*:}"; f="$PLUGIN_ROOT/agents/$a.md"
  assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/$a.md exists"
  [ -f "$f" ] || continue
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"
  assert_eq "0" "$(echo "$front" | grep -q '^model: inherit$' && echo 0 || echo 1)" "$a model: inherit"
  assert_eq "0" "$(echo "$front" | grep -q '^tier: judgement$' && echo 0 || echo 1)" "$a tier: judgement"
  assert_eq "1" "$(has "$tools" 'Write')" "$a is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "$a is read-only: no Edit"
  assert_eq "1" "$(has "$tools" 'Agent(')" "$a is a leaf: spawns nothing"
  assert_eq "0" "$(grep -qF "$tag" "$f" && echo 0 || echo 1)" "$a documents its output marker $tag"
done
for a in grill-engineer grill-architect grill-operator; do
  assert_eq "0" "$(grep -qF "working-methods:$a" "$PLUGIN_ROOT/agents/$a.md" && echo 0 || echo 1)" "$a keeps the interop rule (replaced by working-methods:$a, never both)"
done
assert_eq "0" "$(grep -qF 'rules-auditor' "$PLUGIN_ROOT/agents/grill-architect.md" && echo 0 || echo 1)" "grill-architect is the rules-auditor lens"
assert_eq "0" "$(grep -qF 'defect-hunter' "$PLUGIN_ROOT/agents/grill-engineer.md" && echo 0 || echo 1)" "grill-engineer is the defect-hunter lens"
assert_eq "0" "$(grep -qF 'Lens `operator`' "$PLUGIN_ROOT/agents/grill-operator.md" && echo 0 || echo 1)" "grill-operator is the operator lens"
assert_eq "0" "$(grep -qiF 'unverified' "$PLUGIN_ROOT/agents/fact-checker.md" && echo 0 || echo 1)" "fact-checker flags 'unverified' claims that were cheaply verifiable"

# ---------- review-orchestrator wiring ----------
front="$(fm "$RO")"; tools="$(echo "$front" | grep '^tools:')"
agent_clause=",$(echo "$tools" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p' | tr -d ' '),"
for a in completeness-critic fact-checker simplicity-critic grill-architect grill-operator grill-engineer \
         working-methods:grill-architect working-methods:grill-operator working-methods:grill-engineer refuter blind-judge; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF ",$a," && echo 0 || echo 1)" "review-orchestrator Agent(...) includes $a"
done
assert_eq "0" "$(echo "$front" | grep -q '^model: inherit$' && echo 0 || echo 1)" "review-orchestrator model: inherit"
assert_eq "0" "$(echo "$front" | grep -q '^tier: judgement$' && echo 0 || echo 1)" "review-orchestrator tier: judgement"
assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "review-orchestrator never asks the owner"
ro_body="$(cat "$RO")"
assert_eq "0" "$(has "$ro_body" 'review-dedup.sh" lenses')" "lens selection goes through the script, not judgment"
assert_eq "0" "$(has "$ro_body" 'ONE batch')" "lenses launched in ONE batch"
assert_eq "0" "$(has "$ro_body" 'review-dedup.sh" dedup')" "dedup goes through the script"
assert_eq "0" "$(has "$ro_body" 'model-resolve.sh" judgement')" "models resolved with model-resolve.sh"
assert_eq "0" "$(has "$ro_body" -- '--mark-unavailable')" "missing model: mark unavailable and retry"

# ---------- dedup ----------
out="$("$S" dedup "OK" "evidence: files=1 cmds=0 turns=1/10" \
  "- DEFECT · src/a.php:22 · P2 Race again. → uuid" \
  "DEFECT · src/a.php:22 · P1 race again → lock" \
  "DEFECT · src/a.php:22 · P2 unbounded query → paginate" \
  "RULES · src/a.php:22 · P3 naming → rename" \
  "FACT · README.md:4 · claim wrong → fix" \
  "OPERATOR · P1 · export flow · empty file → warn")"
assert_eq "5" "$(echo "$out" | grep -c .)" "same TAG + file:line + problem collapse; other TAG or other problem on the same line kept; non-findings ignored"
assert_eq "DEFECT · src/a.php:22 · P1 race again → lock" "$(echo "$out" | grep '^DEFECT' | head -1)" "the most severe duplicate wins"
assert_eq "DEFECT · src/a.php:22 · P2 unbounded query → paginate" "$(echo "$out" | grep '^DEFECT' | tail -1)" "a different defect at the same file:line is never dropped"
assert_eq "FACT · README.md:4 · P1 claim wrong → fix" "$(echo "$out" | grep '^FACT')" "missing severity is treated as P1 (never hidden)"
assert_eq "OPERATOR · export flow · P1 empty file → warn" "$(echo "$out" | grep '^OPERATOR')" "prefixed working-methods form is normalized"
assert_eq "RULES · src/a.php:22 · P3 naming → rename" "$(echo "$out" | tail -1)" "output sorted P1 first, P3 last"
blk="$(printf '%s\n' "DEFECT · a.php:1 · P2 x → y" "MISSING · plan.md:3 · P1 no rollback → add" | "$S" dedup --blocking)"
assert_eq "MISSING · plan.md:3 · P1 no rollback → add" "$blk" "--blocking keeps only P1 (stdin input)"
assert_eq "" "$("$S" dedup </dev/null)" "empty input, empty output"
unp="$("$S" dedup "DEFECT · src/a.php:1 · P1 no arrow here" "defect · a.php:2 · P1 lower tag → fix" "DEFECT · a.php:3 · P2 ok → fix")"
assert_eq "2" "$(echo "$unp" | grep -c '^- warn: unparsed finding: ')" "malformed findings are surfaced as unparsed, never dropped"
assert_eq "0" "$(has "$unp" 'DEFECT · a.php:3 · P2 ok → fix')" "well-formed findings still parse alongside unparsed ones"
assert_eq "0" "$(has "$ro_body" 'unparsed finding')" "review-orchestrator treats unparsed findings as findings"

# ---------- refuter step ----------
R="$PLUGIN_ROOT/agents/refuter.md"
assert_eq "0" "$(grep -qF 'REFUTED' "$R" && echo 0 || echo 1)" "refuter can refute"
assert_eq "0" "$(grep -qF -- '--tag REFUTED' "$R" && echo 0 || echo 1)" "refuter persists every refutation with its reason"
assert_eq "0" "$(grep -qF 'Never add a new finding' "$R" && echo 0 || echo 1)" "refuter never adds findings"
assert_eq "0" "$(has "$ro_body" 'dedup --blocking')" "only blocking findings go to the refuter"
assert_eq "0" "$(has "$ro_body" 'No P1 ⇒ skip this step')" "no refuter when there is no P1"

# ---------- judge blindness ----------
# the fenced block of section 5 that carries `operation: judge` is the judge's whole launch prompt
tpl="$(awk '/^## 5\. Blind judge/{s=1; next} s && /^## /{exit}
  s && /^```/ { if (b) { if (blk ~ /operation: judge/) { printf "%s", blk; exit } b=0; blk="" } else b=1; next }
  s && b { blk = blk $0 "\n" }' "$RO")"
assert_eq "0" "$(has "$tpl" 'operation: judge')" "judge launch template found"
for need in 'artifact:' 'objective:' 'findings:'; do
  assert_eq "0" "$(has "$tpl" "$need")" "judge template carries $need"
done
for leak in producer model reasoning self-assessment implementer planner grill lens refuted; do
  assert_eq "1" "$(echo "$tpl" | grep -qiF -- "$leak" && echo 0 || echo 1)" "judge template does NOT carry '$leak'"
done
jt="$(fm "$PLUGIN_ROOT/agents/blind-judge.md" | grep '^tools:')"
assert_eq "1" "$(has "$jt" 'SendMessage')" "blind-judge cannot ask anyone about the producer (no SendMessage)"
assert_eq "0" "$(has "$ro_body" -- '--avoid <producer-model>')" "judge model prefers a candidate different from the producer"
assert_eq "0" "$(grep -qF '3 claims' "$PLUGIN_ROOT/agents/blind-judge.md" && echo 0 || echo 1)" "judge re-verifies the 3 most load-bearing claims itself"
assert_eq "0" "$(grep -qF 'KO iff score < 7' "$PLUGIN_ROOT/agents/blind-judge.md" && echo 0 || echo 1)" "KO iff score < 7"

# ---------- one retry, then escalate ----------
assert_eq "0" "$(has "$ro_body" 'round: 2')" "a round-1 KO leads to one more round"
assert_eq "0" "$(has "$ro_body" 'BLOCKED review KO after 2 rounds')" "a round-2 KO escalates (BLOCKED to the caller)"
assert_eq "0" "$(has "$ro_body" 'Never a third round')" "never a third round"
assert_eq "0" "$(grep -qF -- '--escalate' "$POLICY" && echo 0 || echo 1)" "policy: the caller's retry uses the escalated tier"
for c in design-orchestrator implementation-orchestrator; do
  assert_eq "0" "$(grep -qF 'BLOCKED review KO after 2 rounds' "$PLUGIN_ROOT/agents/$c.md" && echo 0 || echo 1)" "$c stops after the second KO"
done
assert_eq "0" "$(grep -qF 'No overlap with `verifier`' "$POLICY" && echo 0 || echo 1)" "policy states no overlap with verifier"

# ---------- judgements.jsonl ----------
SR="$TMP/.swarm"; mkdir -p "$SR"
assert_eq "recorded" "$("$S" record --swarm-root "$SR" --run r-1 --stage design --artifact-type plan --score 8 --verdict OK --lenses fact-checker,grill-engineer --model opus)" "record OK"
"$S" record --swarm-root "$SR" --run r-1 --stage implementation --artifact-type diff --score 5 --verdict KO --lenses fact-checker --model inherit >/dev/null
assert_eq "2" "$(wc -l < "$SR/judgements.jsonl" | tr -d ' ')" "every score is appended (OK and KO)"
keys="$(python3 -c 'import json,sys
for l in open(sys.argv[1]):
    d=json.loads(l); print(",".join(sorted(d)), d["score"], d["verdict"])' "$SR/judgements.jsonl" | tail -1)"
assert_eq "artifact_type,lenses,model,run,score,stage,verdict 5 KO" "$keys" "lines are valid JSON with the contract keys"
assert_exit 64 "score < 7 cannot be OK" "$S" record --swarm-root "$SR" --run r-1 --stage x --artifact-type plan --score 6 --verdict OK --lenses a --model opus 2>/dev/null
assert_exit 64 "score >= 7 cannot be KO" "$S" record --swarm-root "$SR" --run r-1 --stage x --artifact-type plan --score 7 --verdict KO --lenses a --model opus 2>/dev/null
assert_exit 64 "unsafe characters rejected" "$S" record --swarm-root "$SR" --run 'r"1' --stage x --artifact-type plan --score 9 --verdict OK --lenses a --model opus 2>/dev/null
assert_exit 64 "missing flag rejected" "$S" record --swarm-root "$SR" --run r-1 --stage x 2>/dev/null
assert_eq "2" "$(wc -l < "$SR/judgements.jsonl" | tr -d ' ')" "rejected records write nothing"

# ---------- round counter (the limit never depends on the caller's header) ----------
A1=/w/plan-a.md; A2=/w/plan-b.md
assert_eq "1" "$("$S" round --swarm-root "$SR" --run r-1 --stage design --artifact "$A1")" "first review round of a stage"
assert_eq "2" "$("$S" round --swarm-root "$SR" --run r-1 --stage design --artifact "$A1")" "second review round"
assert_exit 1 "a third round is refused" "$S" round --swarm-root "$SR" --run r-1 --stage design --artifact "$A1"
assert_eq "1" "$("$S" round --swarm-root "$SR" --run r-1 --stage analysis --artifact "$A1")" "rounds are counted per stage"
assert_eq "1" "$("$S" round --swarm-root "$SR" --run r-1 --stage design --artifact "$A2")" "rounds are counted per artifact"
assert_eq "reset" "$("$S" reset --swarm-root "$SR" --run r-1 --stage design --artifact "$A1")" "reset after an OK review"
assert_eq "1" "$("$S" round --swarm-root "$SR" --run r-1 --stage design --artifact "$A1")" "after reset, a new review of the same stage starts at round 1"
assert_exit 64 "round rejects a path-like stage" "$S" round --swarm-root "$SR" --run r-1 --stage ../x --artifact "$A1"
assert_exit 64 "round requires --artifact" "$S" round --swarm-root "$SR" --run r-1 --stage design
assert_eq "1" "$([ -d "$SR/.lock.d" ] && echo 0 || echo 1)" "the round lock is released"
assert_eq "0" "$(has "$ro_body" 'review-dedup.sh" reset')" "review-orchestrator resets the counter on OK"
assert_eq "0" "$(has "$ro_body" 'BLOCKED missing stage')" "stage: is mandatory (no artifact-type fallback)"
assert_eq "0" "$(has "$ro_body" 'review-dedup.sh" round')" "review-orchestrator takes its round from the counter"
assert_eq "1" "$(has "$ro_body" '--stage design --artifact-type plan')" "record example uses placeholders, not design/plan"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
