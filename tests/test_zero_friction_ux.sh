#!/usr/bin/env bash
# tests/test_zero_friction_ux.sh — zero-friction UX recalibration
# (docs/superpowers/specs/2026-09-04-zero-friction-ux-design.md): single /swarm entry point with
# transparent auto-init, deterministic vocabulary translation, business-impact-framed gates. Prose
# tests only — this repo's agents are LLM-followed Markdown, not executable code.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# ===== Task 2: discovery-orchestrator.md + release-manager.md =====
DF="$PLUGIN_ROOT/agents/discovery-orchestrator.md"
dbody="$(awk '/^---$/{n++; next} n>=2{print}' "$DF")"
assert_eq "0" "$(has "$dbody" 'lenguaje llano')" "discovery-orchestrator has the plain-language question style instruction"
assert_eq "0" "$(has "$dbody" 'recomendada')" "discovery-orchestrator's questions mark the recommended option explicitly"

RF="$PLUGIN_ROOT/agents/release-manager.md"
rbody="$(awk '/^---$/{n++; next} n>=2{print}' "$RF")"
assert_eq "0" "$(has "$rbody" 'lenguaje llano')" "release-manager has the plain-language message style instruction"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
