#!/usr/bin/env bash
# scripts/review-dedup.sh — deterministic helper of the review panel (no model involved).
# Policy: skills/swarm-protocol/judgement.md. Caller: agents/review-orchestrator.md.
#
#   review-dedup.sh lenses --artifact-type plan|diff|report --tier light|full [--working-methods]
#       prints the lens AGENT names to launch, one per line, in a fixed order.
#   review-dedup.sh dedup [--blocking] [<finding line>...]
#       reads finding lines (args, or stdin when there are none), normalizes them to
#       `TAG · where · Pn problem → fix`, drops duplicates (same TAG + same where + same problem
#       text, case/space/punctuation-insensitive), keeps the most severe copy, prints them sorted
#       P1→P3 (stable). A DIFFERENT problem at the same file:line is kept. --blocking prints only P1.
#       Non-finding lines (verdict, evidence, `- warn:`…) are ignored.
#   review-dedup.sh record --swarm-root <abs> --run <id> --stage <s> --artifact-type <t>
#                          --score <0-10> --verdict OK|KO --lenses <a,b> --model <id>
#       appends one JSON line to <swarm-root>/judgements.jsonl. KO iff score < 7 (enforced).
#       Read back by /swarm:status (scripts/swarm-status.sh); gitignored by swarm-init.sh.
#   review-dedup.sh round --swarm-root <abs> --run <id> --stage <s> --artifact <path>
#       increments <swarm-root>/run/<run>/review/<stage>.<artifact-key>.round (under mem-lock.sh)
#       and prints the new round number. Past 2 it prints `exceeded: round <n> > 2` and exits 1:
#       the panel's round limit never depends on the caller remembering a `round:` header.
#   review-dedup.sh reset --swarm-root <abs> --run <id> --stage <s> --artifact <path>
#       deletes that counter; called when a review ends OK, so a later review of the same
#       stage + artifact starts again at round 1.
# Exit: 0 ok · 1 round limit exceeded · 64 usage/validation error.
set -u

usage() { echo "review-dedup.sh: $1" >&2; exit 64; }

[ $# -ge 1 ] || usage "missing subcommand (lenses|dedup|record|round|reset)"
SUB="$1"; shift

case "$SUB" in
  lenses)
    ATYPE=""; TIER="full"; WM=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --artifact-type) [ $# -ge 2 ] || usage "--artifact-type requires a value"; ATYPE="$2"; shift 2 ;;
        --tier) [ $# -ge 2 ] || usage "--tier requires a value"; TIER="$2"; shift 2 ;;
        --working-methods) WM=1; shift ;;
        *) usage "unknown argument: $1" ;;
      esac
    done
    # role -> native agent (grill-* keep their file names for compatibility)
    defect="grill-engineer"; rules="grill-architect"; operator="grill-operator"
    if [ "$WM" = 1 ]; then
      defect="working-methods:grill-engineer"; rules="working-methods:grill-architect"
      operator="working-methods:grill-operator"
    fi
    case "$TIER" in
      light)
        case "$ATYPE" in plan|diff|report) ;; *) usage "invalid --artifact-type: '$ATYPE'" ;; esac
        printf '%s\n' fact-checker "$defect" ;;
      full)
        case "$ATYPE" in
          plan)   printf '%s\n' completeness-critic "$defect" "$rules" "$operator" fact-checker simplicity-critic ;;
          diff)   printf '%s\n' "$defect" "$rules" fact-checker completeness-critic ;;
          report) printf '%s\n' fact-checker completeness-critic ;;
          *) usage "invalid --artifact-type: '$ATYPE'" ;;
        esac ;;
      *) usage "invalid --tier: '$TIER' (light|full)" ;;
    esac
    exit 0 ;;

  dedup)
    BLOCKING=0
    if [ "${1:-}" = "--blocking" ]; then BLOCKING=1; shift; fi
    # python's own stdin is the heredoc below, so piped input is turned into args first
    if [ $# -eq 0 ] && [ ! -t 0 ]; then
      while IFS= read -r l || [ -n "$l" ]; do set -- "$@" "$l"; done
    fi
    python3 - "$BLOCKING" "$@" <<'PYEOF'
import re, sys

blocking = sys.argv[1] == "1"
lines = sys.argv[2:]

SEP = re.compile(r"\s*·\s*")
SEV = re.compile(r"^(P[1-3])\b\s*")
WORD = re.compile(r"[^a-z0-9]+")
TAG = re.compile(r"^[A-Z][A-Z0-9_-]*$")
seen, order, unparsed = {}, [], []
for raw in lines:
    line = raw.strip()
    if line.startswith("- "):
        line = line[2:].strip()
    if "·" not in line and "→" not in line:
        continue  # verdict, evidence, warn: not a finding
    if "·" not in line or "→" not in line:
        unparsed.append(line)
        continue
    parts = SEP.split(line, maxsplit=3)
    # external working-methods form, prefixed by the caller: `TAG · Pn · where · problem → fix`
    if len(parts) == 4 and TAG.match(parts[0]) and SEV.match(parts[1] + " "):
        tag, sev, where, rest = parts[0], parts[1], parts[2], parts[3]
    else:
        parts = SEP.split(line, maxsplit=2)
        if len(parts) != 3 or not TAG.match(parts[0]) or SEV.match(parts[0] + " "):
            unparsed.append(line)
            continue
        tag, where, rest = parts
        m = SEV.match(rest)
        # missing severity => P1: an unlabelled finding is checked by the refuter, never hidden
        sev = m.group(1) if m else "P1"
        rest = rest[m.end():] if m else rest
    problem = rest.split("→", 1)[0]
    key = (tag, where, WORD.sub(" ", problem.lower()).strip())
    norm = "%s · %s · %s %s" % (tag, where, sev, rest)
    if key not in seen:
        seen[key] = (sev, norm)
        order.append(key)
    elif sev < seen[key][0]:
        seen[key] = (sev, norm)

out = sorted(order, key=lambda k: (seen[k][0], order.index(k)))
for k in out:
    sev, norm = seen[k]
    if blocking and sev != "P1":
        continue
    print(norm)
# a line that looks like a finding but does not parse is never hidden: the caller treats it as P1
for line in unparsed:
    print("- warn: unparsed finding: %s" % line)
PYEOF
    exit $? ;;

  record)
    SR=""; RUN=""; STAGE=""; ATYPE=""; SCORE=""; VERDICT=""; LENSES=""; MODEL=""
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || usage "$1 requires a value"
      case "$1" in
        --swarm-root) SR="$2" ;;
        --run) RUN="$2" ;;
        --stage) STAGE="$2" ;;
        --artifact-type) ATYPE="$2" ;;
        --score) SCORE="$2" ;;
        --verdict) VERDICT="$2" ;;
        --lenses) LENSES="$2" ;;
        --model) MODEL="$2" ;;
        *) usage "unknown argument: $1" ;;
      esac
      shift 2
    done
    [ -n "$SR" ] && [ -n "$RUN" ] && [ -n "$STAGE" ] && [ -n "$ATYPE" ] && [ -n "$SCORE" ] \
      && [ -n "$VERDICT" ] && [ -n "$LENSES" ] && [ -n "$MODEL" ] || usage "record: all 8 flags are mandatory"
    [ -d "$SR" ] || usage "swarm-root does not exist: $SR"
    case "$ATYPE" in plan|diff|report) ;; *) usage "invalid --artifact-type: '$ATYPE'" ;; esac
    case "$SCORE" in ''|*[!0-9]*) usage "--score must be an integer 0-10" ;; esac
    [ "$SCORE" -le 10 ] || usage "--score must be an integer 0-10"
    case "$VERDICT" in OK|KO) ;; *) usage "--verdict must be OK or KO" ;; esac
    if [ "$SCORE" -lt 7 ] && [ "$VERDICT" = OK ]; then usage "score $SCORE < 7 must be KO"; fi
    if [ "$SCORE" -ge 7 ] && [ "$VERDICT" = KO ]; then usage "score $SCORE >= 7 must be OK"; fi
    # safe charsets: the line is built without a JSON library, so nothing needs escaping
    for pair in "run:$RUN" "stage:$STAGE" "lenses:$LENSES" "model:$MODEL"; do
      val="${pair#*:}"
      case "$val" in *[!A-Za-z0-9._:,-]*) usage "invalid characters in --${pair%%:*}: '$val'" ;; esac
    done
    printf '{"run":"%s","stage":"%s","artifact_type":"%s","score":%s,"verdict":"%s","lenses":"%s","model":"%s"}\n' \
      "$RUN" "$STAGE" "$ATYPE" "$SCORE" "$VERDICT" "$LENSES" "$MODEL" >> "$SR/judgements.jsonl" \
      || usage "cannot append to $SR/judgements.jsonl"
    echo "recorded"
    exit 0 ;;

  round|reset)
    SR=""; RUN=""; STAGE=""; ART=""
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || usage "$1 requires a value"
      case "$1" in
        --swarm-root) SR="$2" ;;
        --run) RUN="$2" ;;
        --stage) STAGE="$2" ;;
        --artifact) ART="$2" ;;
        *) usage "unknown argument: $1" ;;
      esac
      shift 2
    done
    [ -n "$SR" ] && [ -n "$RUN" ] && [ -n "$STAGE" ] && [ -n "$ART" ] \
      || usage "$SUB: --swarm-root, --run, --stage and --artifact are mandatory"
    [ -d "$SR" ] || usage "swarm-root does not exist: $SR"
    for pair in "run:$RUN" "stage:$STAGE"; do
      val="${pair#*:}"
      case "$val" in .*|*[!A-Za-z0-9._-]*) usage "invalid characters in --${pair%%:*}: '$val'" ;; esac
    done
    # one counter per stage AND artifact: two reviews of different artifacts never share it
    AKEY="$(printf '%s' "$ART" | cksum | cut -d' ' -f1)"
    RDIR="$SR/run/$RUN/review"
    RFILE="$RDIR/$STAGE.$AKEY.round"
    mkdir -p "$RDIR" || usage "cannot create $RDIR"
    LOCK="$(dirname "$0")/mem-lock.sh"
    SWARM_ROOT="$SR" "$LOCK" acquire || usage "cannot acquire the swarm lock"
    trap 'SWARM_ROOT="$SR" "$LOCK" release' EXIT INT TERM
    if [ "$SUB" = reset ]; then
      rm -f "$RFILE" || usage "cannot delete $RFILE"
      echo "reset"
      exit 0
    fi
    N=0
    [ -f "$RFILE" ] && N="$(cat "$RFILE")"
    case "$N" in ''|*[!0-9]*) N=0 ;; esac
    N=$((N + 1))
    printf '%s\n' "$N" > "$RFILE" || usage "cannot write $RFILE"
    if [ "$N" -gt 2 ]; then echo "exceeded: round $N > 2"; exit 1; fi
    echo "$N"
    exit 0 ;;

  *) usage "unknown subcommand: $SUB (lenses|dedup|record|round|reset)" ;;
esac
