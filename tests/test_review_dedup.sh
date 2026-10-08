#!/usr/bin/env bash
# tests/test_review_dedup.sh — scripts/review-dedup.sh behaviour: deterministic lens selection per
# artifact-type/tier, dedup/normalization of lens findings, judgements.jsonl append, round counter.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
S="$PLUGIN_ROOT/scripts/review-dedup.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/swarm-panel.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
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
# --swarm-root is a path the script writes under: only an existing `.swarm` dir, no `..`/`.` component
mkdir -p "$TMP/notswarm"
assert_exit 64 "record refuses a --swarm-root that is not .swarm" "$S" record --swarm-root "$TMP/notswarm" --run r-1 --stage x --artifact-type plan --score 9 --verdict OK --lenses a --model m
assert_exit 64 "round refuses a --swarm-root that climbs out" "$S" round --swarm-root "$SR/../" --run r-1 --stage x --artifact "$A1"
assert_eq "0" "$(ls -A "$TMP/notswarm" | wc -l | tr -d ' ')" "nothing written outside .swarm/"


# every lens the script can select is an agent review-orchestrator is allowed to spawn
clause=",$(awk '/^---$/{n++; next} n==1 && /^tools:/{print; exit}' "$PLUGIN_ROOT/agents/review-orchestrator.md" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p' | tr -d ' '),"
for t in plan diff report; do for tier in light full; do for wm in "" --working-methods; do
  for lens in $("$S" lenses --artifact-type $t --tier $tier $wm); do
    assert_eq "0" "$(echo "$clause" | grep -qF ",$lens," && echo 0 || echo 1)" "lens $lens ($t/$tier$wm) is in review-orchestrator's Agent(...)"
  done
done; done; done

# prior: round 1's blocking findings are stored per stage + artifact and read back for the round-2 delta review
P1A="DEFECT · docs/plan.md:69 · P1 arithmetic contradicts line 41 → recompute"
P1B="MISSING · docs/plan.md:133 · P1 no fallback → add manual fallback"
assert_eq "" "$("$S" prior --swarm-root "$SR" --run r-9 --stage design --artifact "$A1")" "prior prints nothing before a save"
assert_eq "saved" "$("$S" prior --swarm-root "$SR" --run r-9 --stage design --artifact "$A1" --save "$P1A" --save "$P1B")" "prior --save stores the lines"
assert_eq "$P1A
$P1B" "$("$S" prior --swarm-root "$SR" --run r-9 --stage design --artifact "$A1")" "prior prints the saved lines verbatim"
assert_eq "" "$("$S" prior --swarm-root "$SR" --run r-9 --stage design --artifact "$A1.other")" "prior is per artifact"
"$S" round --swarm-root "$SR" --run r-9 --stage design --artifact "$A1" --save x >/dev/null 2>&1
assert_eq "64" "$?" "--save is refused outside prior"
"$S" reset --swarm-root "$SR" --run r-9 --stage design --artifact "$A1" >/dev/null
assert_eq "" "$("$S" prior --swarm-root "$SR" --run r-9 --stage design --artifact "$A1")" "reset drops the prior findings"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
