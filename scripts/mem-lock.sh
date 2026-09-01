#!/usr/bin/env bash
# scripts/mem-lock.sh — atomic mkdir-based lock (macOS bash 3.2, no flock)
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
LOCK_DIR="$SWARM_ROOT/.lock.d"
STALE_SECONDS=30
TIMEOUT_SECONDS=10
SLEEP_INTERVAL=0.05

_now() { date +%s; }

_lock_mtime() {
  # Single stat attempt, no test-then-read gap (TOCTOU): try BSD/macOS stat
  # first, fall back to GNU stat only if the first produced no output.
  local mtime
  mtime="$(stat -f %m "$LOCK_DIR" 2>/dev/null)"
  if [ -z "$mtime" ]; then
    mtime="$(stat -c %Y "$LOCK_DIR" 2>/dev/null)"
  fi
  [ -n "$mtime" ] || return 1
  echo "$mtime"
}

_reclaim_if_stale() {
  [ -d "$LOCK_DIR" ] || return 0
  local mtime now age
  mtime="$(_lock_mtime)"
  if [ -z "$mtime" ]; then
    # mtime unreadable: indistinguishable from "the dir just legitimately
    # vanished" (e.g. the holder released between our -d check and this
    # stat). Never treat unknown as stale — skip this cycle, don't rmdir.
    return 0
  fi
  now="$(_now)"
  age=$((now - mtime))
  if [ "$age" -gt "$STALE_SECONDS" ]; then
    echo "swarm: mem-lock.sh — lock stale (${age}s) at $LOCK_DIR, reclaiming" >&2
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
}

cmd_acquire() {
  mkdir -p "$SWARM_ROOT"
  local start elapsed
  start="$(_now)"
  while true; do
    _reclaim_if_stale
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      return 0
    fi
    elapsed=$(( $(_now) - start ))
    if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
      echo "swarm: mem-lock.sh — timeout after ${TIMEOUT_SECONDS}s waiting for $LOCK_DIR" >&2
      return 1
    fi
    sleep "$SLEEP_INTERVAL"
  done
}

cmd_release() {
  rmdir "$LOCK_DIR" 2>/dev/null
  return 0
}

# CLI dispatch only when executed directly, not when sourced (e.g. by tests
# that want to unit-test internal functions like _reclaim_if_stale).
if [ "${BASH_SOURCE:-$0}" = "$0" ]; then
  case "${1:-}" in
    acquire) cmd_acquire ;;
    release) cmd_release ;;
    *)
      echo "usage: mem-lock.sh {acquire|release}" >&2
      exit 64
      ;;
  esac
fi
