#!/usr/bin/env bash
# scripts/mem-curate.sh — ciclo de vida de findings + GC de runs (spec §10)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$SCRIPT_DIR/mem-lock.sh"
MANIFEST_SCRIPT="$SCRIPT_DIR/mem-manifest.sh"
SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
export SWARM_ROOT
REPO_ROOT="$(dirname "$SWARM_ROOT")"

_with_lock() {
  "$LOCK_SCRIPT" acquire || return 1
  trap '"$LOCK_SCRIPT" release' EXIT INT TERM
  "$@"
  local rc=$?
  "$LOCK_SCRIPT" release
  trap - EXIT INT TERM
  return $rc
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

_resolve_one_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  local tmp today
  tmp="$(mktemp "${f}.XXXXXX")"
  today="$(date -u +"%Y-%m-%d")"
  while IFS= read -r line; do
    case "$line" in
      '- [key:'*'[status:open]'*)
        local file_line cited_file cited_line old_sha new_sha
        file_line="$(echo "$line" | sed -n 's/.*\] \[sha:[0-9a-f]*\] \[status:open\] \[run:[^]]*\] .* · \([^ ]*\) ·.*/\1/p')"
        cited_file="${file_line%%:*}"
        cited_line="${file_line##*:}"
        old_sha="$(echo "$line" | sed -n 's/.*\[sha:\([0-9a-f]*\)\].*/\1/p')"
        if [ -n "$cited_file" ] && [ -n "$cited_line" ]; then
          new_sha="$(_sha8_of_line "$cited_file" "$cited_line")"
        else
          new_sha="$old_sha"
        fi
        if [ "$old_sha" != "$new_sha" ]; then
          echo "$line" | sed "s/\[status:open\]/[status:resolved] [resolved:${today}]/" >> "$tmp"
        else
          echo "$line" >> "$tmp"
        fi
        ;;
      *)
        echo "$line" >> "$tmp"
        ;;
    esac
  done < "$f"
  mv "$tmp" "$f"
  return 0
}

_resolve() {
  local dir="$SWARM_ROOT/findings"
  [ -d "$dir" ] || return 0
  local f
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    _resolve_one_file "$f"
  done
  echo "resolved"
  return 0
}

_prune_one_file() {
  local f="$1" cutoff_epoch="$2"
  [ -f "$f" ] || return 0
  local tmp
  tmp="$(mktemp "${f}.XXXXXX")"
  while IFS= read -r line; do
    case "$line" in
      '- [key:'*'[status:resolved]'*'[resolved:'*)
        local resolved_date resolved_epoch
        resolved_date="$(echo "$line" | sed -n 's/.*\[resolved:\([0-9-]*\)\].*/\1/p')"
        resolved_epoch="$(date -j -f "%Y-%m-%d" "$resolved_date" +%s 2>/dev/null || date -d "$resolved_date" +%s 2>/dev/null || echo 0)"
        if [ "$resolved_epoch" -gt 0 ] && [ "$resolved_epoch" -lt "$cutoff_epoch" ]; then
          :
        else
          echo "$line" >> "$tmp"
        fi
        ;;
      *)
        echo "$line" >> "$tmp"
        ;;
    esac
  done < "$f"
  mv "$tmp" "$f"
  return 0
}

_prune() {
  local days=30
  while [ $# -gt 0 ]; do
    case "$1" in
      --days) days="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local dir="$SWARM_ROOT/findings"
  [ -d "$dir" ] || return 0
  local now cutoff_epoch
  now="$(date +%s)"
  cutoff_epoch=$((now - days * 86400))
  local f
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    _prune_one_file "$f" "$cutoff_epoch"
  done
  echo "pruned"
  return 0
}

cmd_gc() {
  "$MANIFEST_SCRIPT" gc --keep 10
}

case "${1:-}" in
  resolve) shift; _with_lock _resolve "$@" ;;
  prune) shift; _with_lock _prune "$@" ;;
  gc) shift; cmd_gc "$@" ;;
  *)
    echo "usage: mem-curate.sh {resolve|prune --days N|gc}" >&2
    exit 64
    ;;
esac
