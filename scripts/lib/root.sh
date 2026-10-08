#!/usr/bin/env bash
# scripts/lib/root.sh — default SWARM_ROOT for the memory scripts, sourced (never run).
# An explicit SWARM_ROOT always wins. Without it, the nearest ancestor of $PWD that already holds a
# `.swarm/` is used, so a script called from a subdirectory (a run dir, src/…) writes to the repo's
# memory instead of planting a second `.swarm/` there. The walk stops at the repository top (`.git`);
# no `.swarm/` found ⇒ `$PWD/.swarm`, the previous behaviour.
swarm_default_root() {
  local d="$PWD"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -d "$d/.swarm" ]; then printf '%s' "$d/.swarm"; return 0; fi
    [ -e "$d/.git" ] && break
    d="$(dirname "$d")"
  done
  printf '%s' "$PWD/.swarm"
}
