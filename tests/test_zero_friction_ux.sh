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

# ===== Task 3: bilingual docs =====
usage_en="$(cat "$PLUGIN_ROOT/docs/USAGE.md" 2>/dev/null)"
usage_es="$(cat "$PLUGIN_ROOT/docs/USAGE.es.md" 2>/dev/null)"
readme_en="$(cat "$PLUGIN_ROOT/README.md" 2>/dev/null)"
readme_es="$(cat "$PLUGIN_ROOT/README.es.md" 2>/dev/null)"
cmd_run="$(cat "$PLUGIN_ROOT/commands/run.md" 2>/dev/null)"

assert_eq "0" "$(has "$usage_en" '/swarm "')" "USAGE.md quickstart uses the single /swarm command"
assert_eq "0" "$(has "$usage_es" '/swarm "')" "USAGE.es.md quickstart uses the single /swarm command"
assert_eq "0" "$(has "$usage_en" 'Advanced')" "USAGE.md has an Advanced section for --tier="
assert_eq "0" "$(has "$usage_es" 'Avanzado')" "USAGE.es.md has an Avanzado section for --tier="
assert_eq "0" "$(has "$readme_en" '/swarm "')" "README.md quickstart example uses /swarm"
assert_eq "0" "$(has "$readme_es" '/swarm "')" "README.es.md quickstart example uses /swarm"

# --- init.md/doctor.md are NOT deleted (regression guard) ---
assert_eq "0" "$([ -f "$PLUGIN_ROOT/commands/init.md" ] && echo 0 || echo 1)" "commands/init.md still exists (not deleted)"
assert_eq "0" "$([ -f "$PLUGIN_ROOT/commands/doctor.md" ] && echo 0 || echo 1)" "commands/doctor.md still exists (not deleted)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
