#!/usr/bin/env bash
# scripts/swarm-init.sh — /swarm:init: bootstrap de .swarm/ en el repo target (spec §4.6)
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

if [ -f "$GITIGNORE" ] && grep -qF "$MARKER" "$GITIGNORE" 2>/dev/null; then
  :
else
  {
    echo "$MARKER"
    echo ".swarm/context-pack.md"
    echo ".swarm/index.md"
    echo ".swarm/findings/"
    echo ".swarm/run/"
    echo ".swarm/.lock.d"
  } >> "$GITIGNORE"
fi

if ! "$SCRIPT_DIR/mem-files.sh" health >/dev/null 2>&1; then
  echo "swarm: init — backend 'files' health check falló, abortando" >&2
  exit 1
fi

if [ -z "${CLAUDE_MEM_AVAILABLE:-}" ]; then
  echo "swarm: init — aviso: claude-mem no confirmado disponible (best-effort, no bloquea)" >&2
fi

echo "swarm: init completo"
echo "  .swarm/memory.json      backend 'files' requerido (ok) + 'claude-mem' best-effort"
echo "  .swarm/decisions.md     esqueleto creado"
echo "  .gitignore              bloque swarm añadido/idempotente"
exit 0
