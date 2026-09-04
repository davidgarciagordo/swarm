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

assert_eq "0" "$(has "$usage_en" '/swarm:run "')" "USAGE.md quickstart uses the single /swarm:run command"
assert_eq "0" "$(has "$usage_es" '/swarm:run "')" "USAGE.es.md quickstart uses the single /swarm:run command"
assert_eq "0" "$(has "$usage_en" '## 7. Advanced')" "USAGE.md has an Advanced section heading for --tier="
assert_eq "0" "$(has "$usage_es" '## 7. Avanzado')" "USAGE.es.md has an Avanzado section heading for --tier="
assert_eq "0" "$(has "$readme_en" '/swarm:run "')" "README.md quickstart example uses /swarm:run"
assert_eq "0" "$(has "$readme_es" '/swarm:run "')" "README.es.md quickstart example uses /swarm:run"
assert_eq "1" "$(has "$readme_en" '/swarm "')" "README.md no longer uses the non-existent bare /swarm command"
assert_eq "1" "$(has "$readme_es" '/swarm "')" "README.es.md no longer uses the non-existent bare /swarm command"
assert_eq "1" "$(has "$usage_en" 'a.k.a.')" "USAGE.md no longer frames /swarm:run as an alias"
assert_eq "1" "$(has "$usage_es" 'alias de')" "USAGE.es.md no longer frames /swarm:run as an alias"

# --- init.md/doctor.md are NOT deleted (regression guard) ---
assert_eq "0" "$([ -f "$PLUGIN_ROOT/commands/init.md" ] && echo 0 || echo 1)" "commands/init.md still exists (not deleted)"
assert_eq "0" "$([ -f "$PLUGIN_ROOT/commands/doctor.md" ] && echo 0 || echo 1)" "commands/doctor.md still exists (not deleted)"

# --- commands/run.md frontmatter reflects the simple, --tier=-free surface ---
assert_eq "0" "$(has "$cmd_run" 'description: "/swarm:run')" "commands/run.md description names /swarm:run as the entry point"
assert_eq "0" "$(has "$cmd_run" 'argument-hint: "<objetivo>"')" "commands/run.md argument-hint stays --tier=-free (just the goal, power-user detail lives in USAGE.md)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
