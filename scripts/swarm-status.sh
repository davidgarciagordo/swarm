#!/usr/bin/env bash
# scripts/swarm-status.sh — /swarm:status (spec §11): current run, tier, registered agents,
# summary lines, open findings and recent runs. Deterministic: not a single model turn.
#
# Exit contract (ruling 12): 0 = normal · 1 = no .swarm/ · 2 = there is data this script CANNOT
# parse deterministically (it prints everything it could, plus one "unparseable: …" line per
# case). 2 is what triggers the bounded fallback in commands/status.md.
# It never degrades silently to "tier: ?": unreadable data is SAID.
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
degraded=0

if [ ! -d "$SWARM_ROOT" ]; then
  echo "swarm: no .swarm/ in $SWARM_ROOT — run /swarm:init in this repo first" >&2
  exit 1
fi

RUN_ROOT="$SWARM_ROOT/run"
current=""
[ -f "$RUN_ROOT/current" ] && current="$(cat "$RUN_ROOT/current" 2>/dev/null)"

if [ -z "$current" ] || [ ! -d "$RUN_ROOT/$current" ]; then
  echo "swarm: no runs recorded yet (.swarm/ initialised, no /swarm:run closed)"
else
  python3 - "$RUN_ROOT/$current" "$current" <<'PYEOF'
import json, os, sys

run_dir, run_id = sys.argv[1], sys.argv[2]

tier = started = "?"
degraded = False
run_json = os.path.join(run_dir, "run.json")
if os.path.isfile(run_json):
    try:
        with open(run_json) as fh:
            data = json.load(fh)
        tier = data.get("tier", "?")
        started = data.get("started", "?")
    except (ValueError, OSError) as exc:
        # A truncated run.json (a run interrupted mid-write) or one from another plugin version
        # is exactly the residual a script cannot resolve and a reader can: say it, never
        # show a silent "tier: ?".
        print("unparseable: %s (%s)" % (run_json, exc))
        degraded = True

print("run: %s · tier: %s · started: %s" % (run_id, tier, started))

agents_dir = os.path.join(run_dir, "agents")
rows = []
if os.path.isdir(agents_dir):
    for name in sorted(os.listdir(agents_dir)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(agents_dir, name)) as fh:
                a = json.load(fh)
        except (ValueError, OSError):
            continue
        rows.append((a.get("domain", "?"), a.get("agent", name[:-5]), a.get("owner", "?")))
print("registered agents: %d" % len(rows))
for domain, agent, owner in sorted(rows):
    print("  - %-14s %s (launched by %s)" % (domain, agent, owner))

summary = os.path.join(run_dir, "summary.md")
if os.path.isfile(summary):
    with open(summary) as fh:
        lines = [l.rstrip("\n") for l in fh if l.strip()]
    print("run summary (%d lines):" % len(lines))
    for l in lines:
        print("  %s" % l)
else:
    print("run summary: (no lines yet)")

if degraded:
    sys.exit(2)
PYEOF
  [ $? -eq 2 ] && degraded=2
fi

python3 - "$SWARM_ROOT" <<'PYEOF'
import os, re, sys
from collections import Counter

swarm_root = sys.argv[1]
findings_dir = os.path.join(swarm_root, "findings")
open_by_agent = Counter()
open_by_tag = Counter()
total_open = 0
unparsed = []
if os.path.isdir(findings_dir):
    for name in sorted(os.listdir(findings_dir)):
        if not name.endswith(".md"):
            continue
        bad = 0
        with open(os.path.join(findings_dir, name)) as fh:
            for line in fh:
                m = re.search(r"\[key:([^|\]]+)\|([^|\]]+)\|", line)
                if not m:
                    # a line that STARTS like an entry but has no metadata header (a hand-edited
                    # file, or an entry from a future version): the count would come out low and
                    # nobody would notice. Say it.
                    if line.startswith("- ["):
                        bad += 1
                    continue
                if "[status:open]" not in line:
                    continue
                total_open += 1
                open_by_agent[m.group(1)] += 1
                open_by_tag[m.group(2)] += 1
        if bad:
            unparsed.append((name, bad))
for name, bad in unparsed:
    print("unparseable: %d entries in findings/%s without a [key:…] header" % (bad, name))
by_tag = ", ".join("%s: %d" % (t, n) for t, n in sorted(open_by_tag.items())) or "—"
print("open findings: %d (%s)" % (total_open, by_tag))
for agent, n in sorted(open_by_agent.items()):
    print("  - %-22s %d" % (agent, n))

run_root = os.path.join(swarm_root, "run")
recents = []
if os.path.isdir(run_root):
    import json
    for name in os.listdir(run_root):
        d = os.path.join(run_root, name)
        rj = os.path.join(d, "run.json")
        if not os.path.isdir(d) or not os.path.isfile(rj):
            continue
        try:
            with open(rj) as fh:
                data = json.load(fh)
        except (ValueError, OSError):
            continue
        recents.append((data.get("started", ""), name, data.get("tier", "?")))
recents.sort(reverse=True)
print("recent runs: %d" % len(recents))
for started, name, tier in recents[:5]:
    print("  - %s (%s, %s)" % (name, tier, started))

judgements = os.path.join(swarm_root, "judgements.jsonl")
if os.path.isfile(judgements):
    import json
    scores, bad_j = [], 0
    with open(judgements) as fh:
        for line in fh:
            if not line.strip():
                continue
            try:
                j = json.loads(line)
                scores.append((j["run"], j["stage"], j["artifact_type"], int(j["score"]), j["verdict"]))
            except (ValueError, KeyError, TypeError):
                bad_j += 1
    if bad_j:
        print("unparseable: %d lines of judgements.jsonl" % bad_j)
        unparsed.append(("judgements.jsonl", bad_j))
    print("panel verdicts: %d" % len(scores))
    for run, stage, atype, score, verdict in scores[-5:]:
        print("  - %s %s/%s score=%d %s" % (run, stage, atype, score, verdict))

if unparsed:
    sys.exit(2)
PYEOF
[ $? -eq 2 ] && degraded=2

exit "$degraded"
