#!/usr/bin/env bash
# scripts/swarm-findings.sh — /swarm:findings [agent|tag] [--all] (spec §11): filtered query over
# .swarm/findings/. Deterministic, no model.
#
# The filter is validated HERE (not in the command's prose): a slash command does not go through
# hooks/bash-guard.py, so the user's argument has to fail closed in the script itself.
#
# Exit contract (ruling 12): 0 = normal · 1 = no .swarm/ · 64 = invalid filter (user error, handled
# by the script) · 2 = there are entries that cannot be parsed deterministically. Only 2 triggers
# the bounded fallback in skills/findings/SKILL.md.
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"

filter=""
show_all=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) show_all=1; shift ;;
    -*) echo "usage: swarm-findings.sh [agent|TAG] [--all]" >&2; exit 64 ;;
    *)
      if [ -n "$filter" ]; then
        echo "swarm: one filter only (agent or TAG)" >&2
        exit 64
      fi
      filter="$1"; shift ;;
  esac
done

if [ -n "$filter" ]; then
  case "$filter" in
    *[!A-Za-z0-9_-]*|"")
      echo "swarm: invalid filter '$filter' — only [A-Za-z0-9_-]" >&2
      exit 64
      ;;
  esac
fi

if [ ! -d "$SWARM_ROOT" ]; then
  echo "swarm: no .swarm/ in $SWARM_ROOT — run /swarm:init in this repo first" >&2
  exit 1
fi

python3 - "$SWARM_ROOT" "$filter" "$show_all" <<'PYEOF'
import os, re, sys

swarm_root, flt, show_all = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
findings_dir = os.path.join(swarm_root, "findings")
KEY_RE = re.compile(r"\[key:([^|\]]+)\|([^|\]]+)\|([^\]]*)\]")
STATUS_RE = re.compile(r"\[status:(\w+)\]")
CAP = 50

rows = []
unparsed = 0
if os.path.isdir(findings_dir):
    for name in sorted(os.listdir(findings_dir)):
        if not name.endswith(".md"):
            continue
        with open(os.path.join(findings_dir, name)) as fh:
            for line in fh:
                m = KEY_RE.search(line)
                if not m:
                    # a line shaped like an entry but without the metadata header cannot be
                    # filtered or classified deterministically. It is counted and reported
                    # (ruling 12) instead of silently vanishing from the listing.
                    if line.startswith("- ["):
                        unparsed += 1
                    continue
                agent, tag = m.group(1), m.group(2)
                sm = STATUS_RE.search(line)
                status = sm.group(1) if sm else "open"
                if not show_all and status != "open":
                    continue
                if flt and flt != agent and flt != tag:
                    continue
                # the readable body starts after the metadata header's last "] "
                body = line.rstrip("\n")
                idx = body.rfind("] ")
                body = body[idx + 2:] if idx != -1 else body
                rows.append((agent, tag, status, body))

scope = "all" if show_all else "open"
label = ("filter %s · " % flt) if flt else ""
print("findings (%s%s): %d" % (label, scope, len(rows)))
for agent, tag, status, body in rows[:CAP]:
    mark = "" if status == "open" else " [%s]" % status
    print("  - %-22s %s%s" % (agent, body, mark))
if len(rows) > CAP:
    print("  … and %d more (narrow with /swarm:findings <agent|TAG>)" % (len(rows) - CAP))
if unparsed:
    print("unparseable: %d entries without a [key:…] header (cannot be filtered)" % unparsed)
    sys.exit(2)
PYEOF
rc=$?

exit "$rc"
