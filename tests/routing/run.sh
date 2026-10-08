#!/usr/bin/env bash
# tests/routing/run.sh — routing evals: run a real /swarm:run headless and assert which agents it spawned.
# NOT part of tests/run.sh: every case spends real money (cases.json `budget_usd` caps it).
#
#   tests/routing/run.sh <case-name>|--list      (uses the plugin in THIS checkout via --plugin-dir)
# Exit: 0 all assertions hold · 1 an assertion failed · 2 the run itself failed · 64 usage.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$DIR/../.." && pwd)"
CASES="$DIR/cases.json"

[ $# -eq 1 ] || { echo "usage: tests/routing/run.sh <case-name>|--list" >&2; exit 64; }
if [ "$1" = "--list" ]; then
  python3 -c 'import json,sys; [print("%-22s $%s  %s" % (c["name"], c["budget_usd"], c["goal"][:70])) for c in json.load(open(sys.argv[1]))["cases"]]' "$CASES"
  exit 0
fi
CASE="$1"
GOAL="$(python3 -c 'import json,sys; m=[c for c in json.load(open(sys.argv[1]))["cases"] if c["name"]==sys.argv[2]]; print(m[0]["goal"] if m else "")' "$CASES" "$CASE")"
BUDGET="$(python3 -c 'import json,sys; m=[c for c in json.load(open(sys.argv[1]))["cases"] if c["name"]==sys.argv[2]]; print(m[0]["budget_usd"] if m else "")' "$CASES" "$CASE")"
[ -n "$GOAL" ] || { echo "routing: unknown case '$CASE' (--list)" >&2; exit 64; }

# scratch repo: a tiny tool with a README, committed, so sizing has something real to probe
REPO="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/swarm-routing.XXXXXX")" && pwd -P)"
(
  cd "$REPO" || exit 1
  git init -q && git config user.email "test@swarm.local" && git config user.name "swarm-tests"
  printf '# listr\n\nA small CLI that lists the files of a directory as a table.\n' > README.md
  printf '#!/usr/bin/env python3\nimport os, sys\n\n\ndef main(path="."):\n    for name in sorted(os.listdir(path)):\n        print(name)\n\n\nif __name__ == "__main__":\n    main(*sys.argv[1:])\n' > listr.py
  git add -A && git commit -q -m "chore: initial commit"
) || { echo "routing: cannot create the scratch repo" >&2; exit 2; }

OUT="$REPO/.routing-result.json"
echo "routing: case=$CASE budget=\$$BUDGET repo=$REPO"
( cd "$REPO" && claude -p "/swarm:run $GOAL" --plugin-dir "$PLUGIN_ROOT" --output-format json \
    --max-budget-usd "$BUDGET" --permission-mode acceptEdits \
    --allowedTools Agent Bash Read Grep Glob Edit Write WebSearch WebFetch SendMessage Skill ) > "$OUT" 2> "$REPO/.routing-stderr.txt"
RC=$?
SESSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("session_id",""))' "$OUT" 2>/dev/null)"
[ -n "$SESSION" ] || { echo "routing: the run produced no session id (claude exit $RC); see $REPO/.routing-stderr.txt" >&2; exit 2; }
COST="$("$PLUGIN_ROOT/scripts/swarm-cost.sh" --repo "$REPO" --session "$SESSION")" || { echo "routing: no transcripts for $SESSION" >&2; exit 2; }
echo "$COST"

printf '%s\n' "$COST" > "$REPO/.routing-cost.txt"
JUDGEMENT="$("$PLUGIN_ROOT/scripts/model-resolve.sh" judgement)"

python3 - "$CASES" "$CASE" "$OUT" "$REPO" "$JUDGEMENT" <<'PYEOF'
import collections, json, os, sys

cases, name, out, repo, judgement = sys.argv[1:6]
case = [c for c in json.load(open(cases))['cases'] if c['name'] == name][0]
result = json.load(open(out))
agents, models = collections.Counter(), {}
for line in open(os.path.join(repo, '.routing-cost.txt')):
    cols = line.split()
    if cols and cols[0].startswith(('swarm:', 'working-methods:')):
        agents[cols[0]] += 1
        models.setdefault(cols[0], cols[1])
fails = []
for a in case.get('require', []):
    if not agents[a]:
        fails.append('required agent never ran: %s' % a)
for a in case.get('forbid', []):
    if agents[a]:
        fails.append('forbidden agent ran: %s x%d' % (a, agents[a]))
for a, n in case.get('at_most', {}).items():
    if agents[a] > n:
        fails.append('%s ran %d times, at most %d' % (a, agents[a], n))
if 'max_agents' in case and sum(agents.values()) > case['max_agents']:
    fails.append('%d agents ran, at most %d' % (sum(agents.values()), case['max_agents']))
if case.get('no_swarm_dir') and os.path.exists(os.path.join(repo, '.swarm')):
    fails.append('.swarm/ was created on a read-only goal')
if case.get('root_on_judgement_model') and judgement != 'inherit':
    root = models.get('swarm:orchestrator', '')
    if judgement not in root:
        fails.append('root ran on %s, judgement tier resolves to %s' % (root or 'nothing', judgement))
print('routing: cost=$%s agents=%d' % (result.get('total_cost_usd', '?'), sum(agents.values())))
for f in fails:
    print('FAIL: ' + f)
print('routing: %s %s' % (name, 'FAILED' if fails else 'passed'))
sys.exit(1 if fails else 0)
PYEOF
