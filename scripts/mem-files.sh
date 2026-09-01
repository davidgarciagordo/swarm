#!/usr/bin/env bash
# scripts/mem-files.sh — Backend de memoria basado en ficheros con lock atómico (mkdir spin).
set -euo pipefail

acquire_lock() {
  local lock_dir="$1/.lock.d"
  local timeout=10
  local start
  start=$(date +%s)
  while ! mkdir "$lock_dir" 2>/dev/null; do
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge $timeout ]; then
      # Recuperación de lock huérfano tras timeout
      rmdir "$lock_dir" 2>/dev/null || true
    fi
    sleep 0.05 2>/dev/null || sleep 1
  done
}

release_lock() {
  local lock_dir="$1/.lock.d"
  rmdir "$lock_dir" 2>/dev/null || true
}

cmd="${1:-}"

case "$cmd" in
  health)
    SWARM_ROOT="${2:-.swarm}"
    mkdir -p "$SWARM_ROOT"
    [ -d "$SWARM_ROOT" ] && exit 0 || exit 1
    ;;

  write)
    subcmd="${2:-}"
    case "$subcmd" in
      finding)
        agent="${3:-}"
        finding="${4:-}"
        SWARM_ROOT="${5:-.swarm}"
        [ -n "$agent" ] && [ -n "$finding" ] || { echo "Uso: mem-files.sh write finding <agent> <finding> [swarm_root]" >&2; exit 1; }

        mkdir -p "$SWARM_ROOT/findings"
        acquire_lock "$SWARM_ROOT"
        trap 'release_lock "$SWARM_ROOT"' EXIT

        target="$SWARM_ROOT/findings/${agent}.md"
        python3 - "$target" "$finding" <<'PYEOF'
import sys, os, re

target, finding = sys.argv[1], sys.argv[2]
lines = []
if os.path.exists(target):
    with open(target, 'r', encoding='utf-8') as f:
        lines = f.readlines()

m = re.search(r'\[key:[^\]]+\]', finding)
key = m.group(0) if m else None

replaced = False
new_lines = []
if key:
    for line in lines:
        if key in line:
            new_lines.append(finding + '\n')
            replaced = True
        else:
            new_lines.append(line)

if not replaced:
    new_lines.append(finding + '\n')

tmp_target = f"{target}.tmp.{os.getpid()}"
with open(tmp_target, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
os.replace(tmp_target, target)
PYEOF

        release_lock "$SWARM_ROOT"
        trap - EXIT
        ;;

      decision)
        decision="${3:-}"
        SWARM_ROOT="${4:-.swarm}"
        [ -n "$decision" ] || { echo "Uso: mem-files.sh write decision <decision> [swarm_root]" >&2; exit 1; }

        mkdir -p "$SWARM_ROOT"
        acquire_lock "$SWARM_ROOT"
        trap 'release_lock "$SWARM_ROOT"' EXIT

        target="$SWARM_ROOT/decisions.md"
        echo "$decision" >> "$target"

        release_lock "$SWARM_ROOT"
        trap - EXIT
        ;;

      *)
        echo "Subcomando write desconocido: $subcmd" >&2
        exit 1
        ;;
    esac
    ;;

  query)
    query="${2:-}"
    SWARM_ROOT="${3:-.swarm}"
    [ -n "$query" ] || { echo "Uso: mem-files.sh query <query> [swarm_root]" >&2; exit 1; }

    if [ -d "$SWARM_ROOT" ]; then
      grep -rn -- "$query" "$SWARM_ROOT" 2>/dev/null || true
    fi
    ;;

  *)
    echo "Uso: mem-files.sh {health|write|query} ..." >&2
    exit 1
    ;;
esac
