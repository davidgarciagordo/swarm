#!/usr/bin/env bash
# scripts/swarm-init.sh — /swarm:init: bootstraps .swarm/ in the target repo (spec §4.6)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
export SWARM_ROOT
REPO_ROOT="$(dirname "$SWARM_ROOT")"
GITIGNORE="$REPO_ROOT/.gitignore"
MARKER="# swarm"

mkdir -p "$SWARM_ROOT/findings" "$SWARM_ROOT/run"

if [ ! -f "$SWARM_ROOT/memory.json" ]; then
  cat > "$SWARM_ROOT/memory.json" <<'JSONEOF'
{
  "backends": [
    { "name": "files", "type": "files", "root": ".swarm", "default": true, "required": true },
    { "name": "claude-mem", "type": "mcp", "server": "plugin_claude-mem_mcp-search", "scope": "historical", "required": false }
  ],
  "policy": {
    "read": ["files", "claude-mem"],
    "write": ["files", "claude-mem"],
    "stale": { "mode": "tree-hash" }
  }
}
JSONEOF
fi

if [ ! -f "$SWARM_ROOT/decisions.md" ]; then
  printf '# Decisiones\n' > "$SWARM_ROOT/decisions.md"
fi

# Per-line idempotent: a repo initialised by an older version gets only the entries it lacks.
if ! { [ -f "$GITIGNORE" ] && grep -qxF "$MARKER" "$GITIGNORE" 2>/dev/null; }; then
  echo "$MARKER" >> "$GITIGNORE"
fi
for entry in .swarm/context-pack.md .swarm/index.md .swarm/findings/ .swarm/run/ .swarm/.lock.d \
  .swarm/models.unavailable .swarm/judgements.jsonl; do
  grep -qxF "$entry" "$GITIGNORE" 2>/dev/null || echo "$entry" >> "$GITIGNORE"
done

if ! "$SCRIPT_DIR/mem-files.sh" health >/dev/null 2>&1; then
  echo "swarm: init — backend 'files' health check failed, aborting" >&2
  exit 1
fi

if [ -z "${CLAUDE_MEM_AVAILABLE:-}" ]; then
  echo "swarm: init — warning: claude-mem not confirmed available (best-effort, non-blocking)" >&2
fi

echo "swarm: init complete"
echo "  .swarm/memory.json      backend 'files' required (ok) + 'claude-mem' best-effort"
echo "  .swarm/decisions.md     skeleton created"
echo "  .gitignore              swarm block added (idempotent)"
exit 0
