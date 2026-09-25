#!/usr/bin/env bash
# scripts/model-resolve.sh — deterministic tier -> model id resolution (no model involved).
#
#   model-resolve.sh <tier> [--swarm-root <abs .swarm>] [--avoid <id>]
#       prints the first candidate of <tier> not listed (live) in <swarm-root>/models.unavailable,
#       else `inherit`. --avoid <id> (blind judge): prefer an available candidate != <id>; if none
#       exists prints `inherit` + a stderr note. --avoid inherit means the producer's model is
#       UNKNOWN (it ran on the session model): prints the plain resolution + a stderr note, since
#       independence cannot be proven.
#   model-resolve.sh --mark-unavailable <id> [--swarm-root <abs .swarm>]
#       appends `<id> <epoch> <run-id>` to <swarm-root>/models.unavailable (idempotent while live).
#       A stamped entry expires after SWARM_MODEL_UNAVAILABLE_TTL seconds (default 86400, minimum 1); a bare
#       hand-written `<id>` line never expires. <swarm-root> must be an EXISTING directory named
#       `.swarm` (never created here), so a stray path cannot plant files elsewhere.
#   model-resolve.sh --escalate <tier> [--swarm-root <abs .swarm>]
#       prints the next tier up whose resolved model DIFFERS from <tier>'s (a retry on the same
#       model is not an escalation); judgement escalates to itself.
#   model-resolve.sh --show [--swarm-root <abs .swarm>]
#       one line per tier: `<tier> <effective-id> candidates=<a,b,c> unavailable=<x,y>`.
#
# Config: plugin models.json; <swarm-root>/models.json (same schema) overrides it per key.
# A tier never falls back to another tier's list: exhausted candidates => `inherit`.
# Exit: 0 ok · 64 usage/config error.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWARM_ROOT_ARG="${SWARM_ROOT:-$PWD/.swarm}"
MODE="resolve"
TIER=""
TARGET=""
AVOID=""

usage() { echo "model-resolve.sh: $1" >&2; exit 64; }

while [ $# -gt 0 ]; do
  case "$1" in
    --swarm-root)
      [ $# -ge 2 ] || usage "--swarm-root requires a value"
      SWARM_ROOT_ARG="$2"; shift 2 ;;
    --mark-unavailable)
      [ $# -ge 2 ] || usage "--mark-unavailable requires a model id"
      MODE="mark"; TARGET="$2"; shift 2 ;;
    --escalate)
      [ $# -ge 2 ] || usage "--escalate requires a tier"
      MODE="escalate"; TIER="$2"; shift 2 ;;
    --avoid)
      [ $# -ge 2 ] || usage "--avoid requires a model id"
      AVOID="$2"; shift 2 ;;
    --show)
      MODE="show"; shift ;;
    -*) usage "unknown flag: $1" ;;
    *)
      [ -z "$TIER" ] || usage "only one tier accepted"
      TIER="$1"; shift ;;
  esac
done

if [ "$MODE" = "mark" ]; then
  case "$TARGET" in
    ""|inherit|*[[:space:]]*) usage "invalid model id to mark: '$TARGET'" ;;
  esac
fi

[ "$MODE" = "show" ] || [ "$MODE" = "mark" ] || [ -n "$TIER" ] || usage "missing tier (judgement|standard|mechanical)"

python3 - "$MODE" "$TIER" "$AVOID" "$PLUGIN_ROOT/models.json" "$SWARM_ROOT_ARG" "$TARGET" <<'PYEOF'
import json, os, sys, time

mode, tier, avoid, plugin_cfg, swarm_root, target = sys.argv[1:7]
_ttl = os.environ.get("SWARM_MODEL_UNAVAILABLE_TTL", "")
# clamped to >= 1: TTL=0 would expire every mark the moment it is written
TTL = max(1, int(_ttl)) if _ttl.isdigit() else 86400
TIERS = ("judgement", "standard", "mechanical")


def fail(msg):
    sys.stderr.write("model-resolve.sh: %s\n" % msg)
    sys.exit(64)


def load(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        fail("%s is not valid JSON: %s" % (path, exc))
    if not isinstance(data, dict):
        fail("%s is not a JSON object" % path)
    tiers = data.get("tiers", {})
    esc = data.get("escalation", {})
    if not isinstance(tiers, dict) or not isinstance(esc, dict):
        fail("%s: 'tiers' and 'escalation' must be objects" % path)
    for name, cands in tiers.items():
        if name not in TIERS:
            fail("%s: unknown tier '%s'" % (path, name))
        if not isinstance(cands, list) or not cands or not all(isinstance(c, str) and c.strip() for c in cands):
            fail("%s: tier '%s' must be a non-empty list of model ids" % (path, name))
    for src, dst in esc.items():
        if src not in TIERS or dst not in TIERS:
            fail("%s: invalid escalation %s -> %s" % (path, src, dst))
    return tiers, esc


tiers, esc = load(plugin_cfg)
override = os.path.join(swarm_root, "models.json")
if os.path.isfile(override):
    o_tiers, o_esc = load(override)
    tiers = dict(tiers, **o_tiers)
    esc = dict(esc, **o_esc)

unav_path = os.path.join(swarm_root, "models.unavailable")
now = int(time.time())


def live_unavailable():
    """Ids marked unavailable and not expired (bare hand-written ids never expire)."""
    out = set()
    if not os.path.isfile(unav_path):
        return out
    with open(unav_path) as fh:
        for line in fh:
            parts = line.split()
            if not parts or parts[0].startswith("#"):
                continue
            if len(parts) >= 2 and parts[1].isdigit() and now - int(parts[1]) >= TTL:
                continue
            out.add(parts[0])
    return out


if mode == "mark":
    real = os.path.realpath(swarm_root)
    if os.path.basename(real) != ".swarm" or not os.path.isdir(real):
        fail("--swarm-root must be an existing .swarm directory: '%s'" % swarm_root)
    if target in live_unavailable():
        print("already: %s" % target)
        sys.exit(0)
    run_id = "adhoc"
    try:
        with open(os.path.join(real, "run", "current")) as fh:
            run_id = fh.read().strip() or "adhoc"
    except OSError:
        pass
    try:
        with open(os.path.join(real, "models.unavailable"), "a") as fh:
            fh.write("%s %d %s\n" % (target, now, run_id))
    except OSError as exc:
        fail("cannot write models.unavailable: %s" % exc)
    print("marked: %s" % target)
    sys.exit(0)

unavailable = live_unavailable()


def available(name):
    return [c for c in tiers.get(name, []) if c == "inherit" or c not in unavailable]


def resolve(name):
    # never crosses into another tier's list: exhausted => inherit (session model)
    cands = available(name)
    return cands[0] if cands else "inherit"


def step_up(name):
    nxt = esc.get(name, name)
    # veracity: escalation only goes UP; a config asking to go down is ignored
    return nxt if TIERS.index(nxt) <= TIERS.index(name) else name


if mode == "escalate":
    if tier not in TIERS:
        fail("unknown tier '%s' (judgement|standard|mechanical)" % tier)
    current = resolve(tier)
    nxt, seen = step_up(tier), {tier}
    # a retry on the SAME model is not an escalation: keep climbing while the model is unchanged
    while resolve(nxt) == current and nxt not in seen:
        seen.add(nxt)
        nxt = step_up(nxt)
    print(nxt)
    sys.exit(0)

if mode == "show":
    for name in TIERS:
        cands = tiers.get(name, [])
        gone = [c for c in cands if c in unavailable]
        print("%s %s candidates=%s unavailable=%s" % (
            name, resolve(name), ",".join(cands), ",".join(gone) or "-"))
    sys.exit(0)

if tier not in TIERS:
    fail("unknown tier '%s' (judgement|standard|mechanical)" % tier)

if avoid == "inherit":
    sys.stderr.write("note: producer model is inherit (unknown session model); judge independence not guaranteed\n")
    print(resolve(tier))
    sys.exit(0)

if avoid:
    independent = [c for c in available(tier) if c != "inherit" and c != avoid]
    if independent:
        print(independent[0])
    else:
        sys.stderr.write("note: no %s candidate independent of '%s'; judge runs on inherit\n" % (tier, avoid))
        print("inherit")
    sys.exit(0)

print(resolve(tier))
PYEOF
