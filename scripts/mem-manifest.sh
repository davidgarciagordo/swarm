#!/usr/bin/env bash
# scripts/mem-manifest.sh — per-run manifest management
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$SCRIPT_DIR/mem-lock.sh"

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
export SWARM_ROOT

_with_lock() {
  "$LOCK_SCRIPT" acquire || return 1
  trap '"$LOCK_SCRIPT" release' EXIT INT TERM
  "$@"
  local rc=$?
  # Explicit release on the normal path, on top of the trap's release on
  # INT/TERM/unexpected EXIT. A double release is intentional and harmless:
  # rmdir on an already-removed lock dir just no-ops.
  "$LOCK_SCRIPT" release
  trap - EXIT INT TERM
  return $rc
}

cmd_open() {
  local tier=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier) tier="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  case "$tier" in
    light|full) ;;
    *) echo "usage: mem-manifest.sh open --tier light|full" >&2; return 64 ;;
  esac
  local run_id
  run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  local run_dir="$SWARM_ROOT/run/$run_id"
  mkdir -p "$run_dir/agents" "$run_dir/mailbox" "$run_dir/retries"
  local started
  started="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  python3 -c "
import json, sys
data = {'id': sys.argv[1], 'tier': sys.argv[2], 'started': sys.argv[3]}
with open(sys.argv[4], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$run_id" "$tier" "$started" "$run_dir/run.json"
  printf '%s' "$run_id" > "$SWARM_ROOT/run/current"
  echo "$run_id"
  return 0
}

_register() {
  local run="" agent="" domain="" area="" owner=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run="$2"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      --domain) domain="$2"; shift 2 ;;
      --area) area="$2"; shift 2 ;;
      --owner) owner="$2"; shift 2 ;;
      *) echo "swarm: mem-manifest.sh register — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$run" ] || [ -z "$agent" ] || [ -z "$domain" ] || [ -z "$area" ] || [ -z "$owner" ]; then
    echo "swarm: mem-manifest.sh register — missing required arg" >&2
    return 64
  fi
  local dir="$SWARM_ROOT/run/$run/agents"
  mkdir -p "$dir"
  python3 -c "
import json, sys
data = {'agent': sys.argv[1], 'domain': sys.argv[2], 'area': sys.argv[3], 'owner': sys.argv[4]}
with open(sys.argv[5], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$agent" "$domain" "$area" "$owner" "$dir/${agent}.json"
  echo "registered"
  return 0
}

_summary() {
  local run="" line=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run="$2"; shift 2 ;;
      --line) line="$2"; shift 2 ;;
      *) echo "swarm: mem-manifest.sh summary — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$run" ] || [ -z "$line" ]; then
    echo "swarm: mem-manifest.sh summary — missing required arg" >&2
    return 64
  fi
  local dir="$SWARM_ROOT/run/$run"
  mkdir -p "$dir"
  echo "$line" >> "$dir/summary.md"
  echo "written"
  return 0
}

cmd_current() {
  local f="$SWARM_ROOT/run/current"
  [ -f "$f" ] || return 1
  cat "$f"
  return 0
}

# _gc_started_for RUN_DIR — echoes the ISO 'started' timestamp from a run's
# run.json, or nothing if it can't be read.
_gc_started_for() {
  local run_json="$1/run.json"
  [ -f "$run_json" ] || return 0
  python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('started',''))" "$run_json" 2>/dev/null
}

cmd_gc() {
  local keep=10
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep) keep="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local run_root="$SWARM_ROOT/run"
  [ -d "$run_root" ] || return 0

  # The run pointed to by "current" is the active/in-progress run: it is
  # never a gc candidate (like "adhoc") and never consumes the --keep
  # budget, regardless of its age relative to other runs.
  local current_run=""
  [ -f "$run_root/current" ] && current_run="$(cat "$run_root/current" 2>/dev/null)"

  local tmp_list
  tmp_list="$(mktemp)"
  local d name started
  for d in "$run_root"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    [ "$name" = "adhoc" ] && continue
    [ -n "$current_run" ] && [ "$name" = "$current_run" ] && continue
    started="$(_gc_started_for "$d")"
    [ -n "$started" ] || continue
    echo "$started|$name" >> "$tmp_list"
  done

  local total
  total="$(sort "$tmp_list" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$total" -gt "$keep" ]; then
    local to_remove=$((total - keep))
    sort "$tmp_list" | head -n "$to_remove" | while IFS='|' read -r started name; do
      rm -rf "${run_root:?}/${name}"
    done
  fi
  rm -f "$tmp_list"
  echo "gc: kept newest $keep run(s)"
  return 0
}

case "${1:-}" in
  open) shift; cmd_open "$@" ;;
  register) shift; _with_lock _register "$@" ;;
  summary) shift; _with_lock _summary "$@" ;;
  current) shift; cmd_current "$@" ;;
  gc) shift; _with_lock cmd_gc "$@" ;;
  *)
    echo "usage: mem-manifest.sh {open|register|summary|current|gc} ..." >&2
    exit 64
    ;;
esac
