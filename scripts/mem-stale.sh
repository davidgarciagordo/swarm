#!/usr/bin/env bash
# scripts/mem-stale.sh — tree-state hash staleness check for context-pack
set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/root.sh"
SWARM_ROOT="${SWARM_ROOT:-$(swarm_default_root)}"
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

# stub: a near-empty repo (<= STUB_MAX files outside .swarm/) gets its pack from mem-scan.sh alone,
# sealed here, so memory-orchestrator does not spawn memory-builder to describe nothing.
# Exit 0 `stub: …` (pack written and sealed) · 3 `not tiny: …` (launch the builder as usual).
STUB_MAX=5
cmd_stub() {
  local n swarm_rel covers
  swarm_rel="$(basename "$SWARM_ROOT")"
  n="$(cd "$REPO_ROOT" && git ls-files --cached --others --exclude-standard -- . ":(exclude)$swarm_rel" 2>/dev/null | wc -l | tr -d ' ')"
  if ! (cd "$REPO_ROOT" && git rev-parse --git-dir >/dev/null 2>&1); then echo "not tiny: not a git repository"; return 3; fi
  if [ "$n" -gt "$STUB_MAX" ]; then echo "not tiny: $n files"; return 3; fi
  [ -d "$SWARM_ROOT" ] || { echo "not tiny: $SWARM_ROOT missing"; return 3; }
  "$(dirname "${BASH_SOURCE[0]}")/mem-scan.sh" --root "$REPO_ROOT" > "$SWARM_ROOT/context-pack.md" || return 3
  covers="$(grep '^covers:' "$SWARM_ROOT/context-pack.md" | head -1)"
  printf '# index\n%s\n' "${covers:-covers: src}" > "$INDEX"
  cmd_seal >/dev/null
  echo "stub: $n files, pack written without a builder"
  return 0
}

case "${1:-}" in
  stub) shift; cmd_stub "$@" ;;
  hash) shift; cmd_hash "$@" ;;
  check) shift; cmd_check "$@" ;;
  seal) shift; cmd_seal "$@" ;;
  *)
    echo "usage: mem-stale.sh {hash|check|seal|stub}" >&2
    exit 64
    ;;
esac
