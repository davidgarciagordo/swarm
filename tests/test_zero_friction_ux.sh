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
assert_eq "allow" "$(guard swarm:orchestrator '\"${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh\"')" "swarm:orchestrator can run the real auto-init command from §2.1"

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
assert_eq "0" "$(has "$section_21" 'posiblemente a medias')" "§2.1 falls back to BLOCKED if swarm-init.sh itself fails, instead of silently proceeding to open a run against a half-made .swarm/"

# --- vocabulary substitution table exists, anchored to OUR exact new text (§4.0bis), not to the
# pre-existing verdict words DONE/BLOCKED/KO/OK which already appear dozens of times in this file
# for unrelated reasons (verdict syntax throughout) and would pass identically without the table ---
assert_eq "0" "$(has "$body" '4.0bis Traducción de vocabulario')" "§4.0bis vocabulary-translation section exists"
assert_eq "0" "$(has "$body" 'Listo:')" "vocabulary table maps DONE -> 'Listo:'"
assert_eq "0" "$(has "$body" 'No he podido continuar:')" "vocabulary table maps BLOCKED -> 'No he podido continuar:'"
assert_eq "0" "$(has "$body" 'Algo no salió bien:')" "vocabulary table maps KO -> 'Algo no salió bien:'"
assert_eq "0" "$(has "$body" 'Todo en orden.')" "vocabulary table maps OK -> 'Todo en orden.'"
assert_eq "0" "$(has "$body" 'lenguaje llano')" "orchestrator has a plain-language instruction for its own output"

# --- §1.0bis Paso 3's own AskUserQuestion example got the plain-language treatment too, not just
# the BLOCKED paths (found missing during the pre-publish audit — Task 1's own worked example
# still said "Lo interpreto como" meta-language until this fix) ---
bis_section="$(echo "$body" | awk '/^### 1\.0bis/{p=1} /^### 1\.1 Tiers/{p=0} p')"
assert_eq "1" "$(has "$bis_section" 'Lo interpreto como')" "§1.0bis Paso 3's AskUserQuestion example no longer uses meta-language about the interpretation process"
assert_eq "0" "$(has "$bis_section" 'Estilo, siempre en lenguaje llano')" "§1.0bis Paso 3 has its own explicit plain-language style instruction, matching discovery §5.3's"

# ===== Task 2: discovery-orchestrator.md + release-manager.md =====
DF="$PLUGIN_ROOT/agents/discovery-orchestrator.md"
dbody="$(awk '/^---$/{n++; next} n>=2{print}' "$DF")"
assert_eq "0" "$(has "$dbody" 'lenguaje llano')" "discovery-orchestrator has the plain-language question style instruction"
assert_eq "0" "$(has "$dbody" 'rec: <letra>')" "discovery-orchestrator still instructs correctly populating rec: to point at the recommended option"
assert_eq "1" "$(has "$dbody" '(recomendada)')" "discovery-orchestrator does NOT instruct embedding a (recomendada) suffix in the option text — marking is the root's §5.3 job, not duplicated here"
assert_eq "0" "$(has "$dbody" 'orchestrator.md §5.3')" "discovery-orchestrator points to the root's existing §5.3 mechanism as the single place the recommended option gets marked"

RF="$PLUGIN_ROOT/agents/release-manager.md"
rbody="$(awk '/^---$/{n++; next} n>=2{print}' "$RF")"
assert_eq "0" "$(has "$rbody" 'lenguaje llano')" "release-manager has the plain-language message style instruction"

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
