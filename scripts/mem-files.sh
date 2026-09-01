#!/usr/bin/env bash
# scripts/mem-files.sh — files backend for swarm memory (.swarm/)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$SCRIPT_DIR/mem-lock.sh"

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
export SWARM_ROOT
REPO_ROOT="$(dirname "$SWARM_ROOT")"

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

_iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_sha8_of_line() {
  local file="$1" line="$2"
  local target="$REPO_ROOT/$file"
  if [ ! -f "$target" ]; then
    echo "00000000"
    return
  fi
  local content
  content="$(sed -n "${line}p" "$target" 2>/dev/null)"
  if [ -z "$content" ]; then
    echo "00000000"
    return
  fi
  printf '%s' "$content" | shasum -a 1 | cut -c1-8
}

cmd_health() {
  if [ ! -d "$SWARM_ROOT" ]; then
    echo "swarm: mem-files.sh health — SWARM_ROOT not found: $SWARM_ROOT" >&2
    return 1
  fi
  if [ ! -w "$SWARM_ROOT" ]; then
    echo "swarm: mem-files.sh health — SWARM_ROOT not writable: $SWARM_ROOT" >&2
    return 1
  fi
  echo "ok"
  return 0
}

_write_finding() {
  local agent="" tag="" file="" line="" run="" text="" fix=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent="$2"; shift 2 ;;
      --tag) tag="$2"; shift 2 ;;
      --file) file="$2"; shift 2 ;;
      --line) line="$2"; shift 2 ;;
      --run) run="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --fix) fix="$2"; shift 2 ;;
      *) echo "swarm: mem-files.sh write finding — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$agent" ] || [ -z "$tag" ] || [ -z "$file" ] || [ -z "$line" ] || [ -z "$run" ] || [ -z "$text" ] || [ -z "$fix" ]; then
    echo "swarm: mem-files.sh write finding — missing required arg" >&2
    return 64
  fi
  mkdir -p "$SWARM_ROOT/findings"
  local out="$SWARM_ROOT/findings/${agent}.md"
  touch "$out"
  local key="key:${agent}|${tag}|${file}:${line}"
  local existing
  existing="$(grep -F "[${key}]" "$out" 2>/dev/null | grep "\[status:open\]" | head -1)"
  if [ -n "$existing" ]; then
    echo "dup"
    return 0
  fi
  local sha
  sha="$(_sha8_of_line "$file" "$line")"
  local entry="- [${key}] [sha:${sha}] [status:open] [run:${run}] ${tag} · ${file}:${line} · ${text} → ${fix}"
  echo "$entry" >> "$out"
  echo "written"
  return 0
}

_write_decision() {
  local text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --text) text="$2"; shift 2 ;;
      *) echo "swarm: mem-files.sh write decision — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$text" ]; then
    echo "swarm: mem-files.sh write decision — missing --text" >&2
    return 64
  fi
  local out="$SWARM_ROOT/decisions.md"
  [ -f "$out" ] || printf '# Decisiones\n' > "$out"
  local today
  today="$(date -u +"%Y-%m-%d")"
  echo "- ${today} · ${text}" >> "$out"
  echo "written"
  return 0
}

_write_mailbox() {
  local to="" from="" run="" text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --to) to="$2"; shift 2 ;;
      --from) from="$2"; shift 2 ;;
      --run) run="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      *) echo "swarm: mem-files.sh write mailbox — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$to" ] || [ -z "$from" ] || [ -z "$run" ] || [ -z "$text" ]; then
    echo "swarm: mem-files.sh write mailbox — missing required arg" >&2
    return 64
  fi
  local dir="$SWARM_ROOT/run/${run}/mailbox"
  mkdir -p "$dir"
  local out="$dir/${to}.md"
  touch "$out"
  echo "- [from:${from}] [ts:$(_iso_now)] ${text}" >> "$out"
  echo "written"
  return 0
}

cmd_write() {
  local kind="${1:-}"; shift || true
  case "$kind" in
    finding) _with_lock _write_finding "$@" ;;
    decision) _with_lock _write_decision "$@" ;;
    mailbox) _with_lock _write_mailbox "$@" ;;
    *)
      echo "usage: mem-files.sh write {finding|decision|mailbox} ..." >&2
      return 64
      ;;
  esac
}

cmd_query() {
  local pattern="${1:-}"; shift || true
  local scope="all"
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope) scope="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [ -z "$pattern" ]; then
    echo "usage: mem-files.sh query <regex> [--scope findings|decisions|pack|all]" >&2
    return 64
  fi
  local targets
  case "$scope" in
    findings) targets=("$SWARM_ROOT/findings") ;;
    decisions) targets=("$SWARM_ROOT/decisions.md") ;;
    pack) targets=("$SWARM_ROOT/context-pack.md") ;;
    all) targets=("$SWARM_ROOT/findings" "$SWARM_ROOT/decisions.md" "$SWARM_ROOT/context-pack.md") ;;
    *) echo "swarm: mem-files.sh query — unknown scope $scope" >&2; return 64 ;;
  esac
  grep -rEn -- "$pattern" "${targets[@]}" 2>/dev/null | head -20
  return 0
}

case "${1:-}" in
  health) shift; cmd_health "$@" ;;
  write) shift; cmd_write "$@" ;;
  query) shift; cmd_query "$@" ;;
  *)
    echo "usage: mem-files.sh {health|write|query} ..." >&2
    exit 64
    ;;
esac
