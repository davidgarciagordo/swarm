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
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"
guard() { # guard <agent_type> <command> -> "allow" | "deny"
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# ===== hooks/bash-allowlist.json: swarm:orchestrator can actually run the auto-init command =====
# §2.1 (below) tells the orchestrator to run this exact command when `.swarm/` is missing — the
# guard must not deny its own documented auto-init path (was denied before this fix: only
# scripts/mem-*.sh and scripts/mem-lock.sh were allowlisted for swarm:orchestrator).
assert_eq "allow" "$(guard swarm:orchestrator '"${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh"')" "swarm:orchestrator can run the real auto-init command from §2.1"

# ===== Task 1: agents/orchestrator.md =====
F="$PLUGIN_ROOT/agents/orchestrator.md"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"

# --- auto-init replaces the hard BLOCKED for the "not found" case ---
assert_eq "0" "$(has "$body" 'SWARM_ROOT not found')" "§2.1 distinguishes the not-found stderr text (auto-init path)"
assert_eq "0" "$(has "$body" 'SWARM_ROOT not writable')" "§2.1 distinguishes the not-writable stderr text (still-block path)"
assert_eq "0" "$(has "$body" 'BLOCKED falta /swarm:init')" "the not-writable case still has a real BLOCKED path (must not vanish entirely)"

# The invocation must live inside §2.1 itself (not a stray prose mention elsewhere), it must be
# the REAL literal invocation (not a reimplementation), and it must come AFTER the not-found stderr
# text within that section — i.e. it's the auto-init branch's actual command, not just a nearby
# comment. Isolate the §2.1 section text first so a match anywhere else in the file can't satisfy
# this.
section_21="$(awk '/^### 2\.1 Health-gate/{f=1} f{print; if(/^### 2\.2/) exit}' "$F")"
not_found_pos="$(echo "$section_21" | grep -n 'SWARM_ROOT not found' | head -1 | cut -d: -f1)"
invoke_pos="$(echo "$section_21" | grep -nF '"${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh"' | head -1 | cut -d: -f1)"
assert_eq "0" "$([ -n "$not_found_pos" ] && [ -n "$invoke_pos" ] && [ "$invoke_pos" -gt "$not_found_pos" ] && echo 0 || echo 1)" "§2.1's not-found branch invokes the real init script literally (scripts/swarm-init.sh), in the right place, not a reimplementation or stray mention"

# --- auto-init failure falls back to a real BLOCKED instead of proceeding on half-made .swarm/ ---
assert_eq "0" "$(has "$section_21" 'BLOCKED falta /swarm:init')" "§2.1 falls back to BLOCKED if swarm-init.sh itself fails, instead of silently proceeding"

# --- vocabulary substitution table exists, anchored to OUR exact new text (§4.0bis), not to the
# pre-existing verdict words DONE/BLOCKED/KO/OK which already appear dozens of times in this file
# for unrelated reasons (verdict syntax throughout) and would pass identically without the table ---
assert_eq "0" "$(has "$body" '4.0bis Traducción de vocabulario')" "§4.0bis vocabulary-translation section exists"
assert_eq "0" "$(has "$body" 'Listo:')" "vocabulary table maps DONE -> 'Listo:'"
assert_eq "0" "$(has "$body" 'No he podido continuar:')" "vocabulary table maps BLOCKED -> 'No he podido continuar:'"
assert_eq "0" "$(has "$body" 'Algo no salió bien:')" "vocabulary table maps KO -> 'Algo no salió bien:'"
assert_eq "0" "$(has "$body" 'Todo en orden.')" "vocabulary table maps OK -> 'Todo en orden.'"
assert_eq "0" "$(has "$body" 'lenguaje llano')" "orchestrator has a plain-language instruction for its own output"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
