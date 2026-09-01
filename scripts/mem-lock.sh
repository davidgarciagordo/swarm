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
  if stat -f %m "$LOCK_DIR" >/dev/null 2>&1; then
    stat -f %m "$LOCK_DIR"
  else
    stat -c %Y "$LOCK_DIR" 2>/dev/null
  fi
}

_reclaim_if_stale() {
  [ -d "$LOCK_DIR" ] || return 0
  local mtime now age
  mtime="$(_lock_mtime 2>/dev/null || echo 0)"
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

case "${1:-}" in
  acquire) cmd_acquire ;;
  release) cmd_release ;;
  *)
    echo "usage: mem-lock.sh {acquire|release}" >&2
    exit 64
    ;;
esac
