#!/usr/bin/env bash
# scripts/mem-stale.sh — tree-state hash staleness check for context-pack
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
REPO_ROOT="$(dirname "$SWARM_ROOT")"
INDEX="$SWARM_ROOT/index.md"

_covers_dirs() {
  if [ -f "$INDEX" ]; then
    local line
    line="$(grep '^covers:' "$INDEX" 2>/dev/null | head -1 | sed 's/^covers:[[:space:]]*//')"
    if [ -n "$line" ]; then
      echo "$line" | tr ',' ' '
      return
    fi
  fi
  echo "src"
}

cmd_hash() {
  local head_sha status_sha ls_sha dir dirs combined swarm_rel
  head_sha="$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null)"
  [ -z "$head_sha" ] && head_sha="no-head"
  # Exclude SWARM_ROOT itself from the status scan: writing index.md/seal
  # data into it must not change the hash it is judged against.
  swarm_rel="$(basename "$SWARM_ROOT")"
  status_sha="$(cd "$REPO_ROOT" && git status --porcelain -- . ":(exclude)$swarm_rel" 2>/dev/null | shasum -a 1 | cut -c1-40)"
  dirs="$(_covers_dirs)"
  ls_sha=""
  for dir in $dirs; do
    if [ -d "$REPO_ROOT/$dir" ]; then
      ls_sha="${ls_sha}$(cd "$REPO_ROOT" && find "$dir" -type f -exec stat -f '%N %m' {} \; 2>/dev/null | shasum -a 1 | cut -c1-40)"
    fi
  done
  ls_sha="$(printf '%s' "$ls_sha" | shasum -a 1 | cut -c1-40)"
  combined="${head_sha}:${status_sha}:${ls_sha}"
  printf '%s' "$combined" | shasum -a 1 | cut -c1-40
}

cmd_check() {
  if [ ! -f "$INDEX" ]; then
    echo "no pack-index: $INDEX"
    return 2
  fi
  local sealed_hash current_hash
  sealed_hash="$(grep '^tree-hash:' "$INDEX" 2>/dev/null | head -1 | sed 's/^tree-hash:[[:space:]]*//')"
  if [ -z "$sealed_hash" ]; then
    echo "no pack-index: missing tree-hash in $INDEX"
    return 2
  fi
  current_hash="$(cmd_hash)"
  if [ "$sealed_hash" = "$current_hash" ]; then
    echo "fresh: tree-hash matches ($current_hash)"
    return 0
  fi
  echo "stale: tree-hash changed (sealed=$sealed_hash current=$current_hash)"
  return 1
}

cmd_seal() {
  mkdir -p "$SWARM_ROOT"
  local hash iso tmp
  hash="$(cmd_hash)"
  iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp="$(mktemp "$SWARM_ROOT/.index.md.XXXXXX")"
  if [ -f "$INDEX" ]; then
    grep -v '^tree-hash:' "$INDEX" | grep -v '^sealed:' > "$tmp" || true
  else
    printf '# index\ncovers: src\n' > "$tmp"
  fi
  {
    echo "tree-hash: $hash"
    echo "sealed: $iso"
  } >> "$tmp"
  mv "$tmp" "$INDEX"
  echo "sealed: $hash"
  return 0
}

case "${1:-}" in
  hash) shift; cmd_hash "$@" ;;
  check) shift; cmd_check "$@" ;;
  seal) shift; cmd_seal "$@" ;;
  *)
    echo "usage: mem-stale.sh {hash|check|seal}" >&2
    exit 64
    ;;
esac
