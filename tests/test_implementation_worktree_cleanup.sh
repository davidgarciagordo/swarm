#!/usr/bin/env bash
# tests/test_implementation_worktree_cleanup.sh — implementation-orchestrator's own worktree
# safety net (fase 5a final review, I1/I3/I4/I5). `tests/test_worktree_cleanup.sh` only covers
# discovery-orchestrator's spiker worktree; this file covers the equivalent guarantees for
# implementer's worktree, which has a materially different shape:
#   - discovery-orchestrator's spiker cleanup command is documented TWICE (1bis path + cut-rule
#     timeout path, both literal `git worktree remove …`);
#   - implementation-orchestrator instead has ONE shared "## Limpieza del worktree" section that
#     every terminal path (from step 2 of the sequence onward) POINTS AT by name — so the honest
#     assertion here is "the literal command appears once, and is referenced from every documented
#     terminal path", not "the literal command appears N times".
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/implementation-orchestrator.md"

body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
first_line_of() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }

assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/implementation-orchestrator.md exists"
[ -f "$F" ] || { echo "FATAL: file missing"; exit 1; }
b="$(body "$F")"

# ---------- 1. master/main branch guard exists and comes BEFORE the git merge instruction ----------
guard_line="$(first_line_of "$F" 'Si el resultado es `master` o `main`, NO ejecutes')"
merge_line="$(first_line_of "$F" 'git merge worktree-agent-<agentId del paso 2>')"
assert_eq "0" "$([ -n "$guard_line" ] && echo 0 || echo 1)" "master/main branch guard text exists"
assert_eq "0" "$([ -n "$merge_line" ] && echo 0 || echo 1)" "git merge worktree-agent-<agentId> instruction exists"
if [ -n "$guard_line" ] && [ -n "$merge_line" ]; then
  assert_eq "0" "$([ "$guard_line" -lt "$merge_line" ] && echo 0 || echo 1)" "branch guard (line $guard_line) appears BEFORE the git merge instruction (line $merge_line)"
fi
# the guard checks the literal 2-name blacklist (master/main) — parked as-is by the review, not a positive "expected branch" check
assert_eq "0" "$(has "$b" 'HEAD` es literalmente `master` o `main`')" "Salida wording matches what the guard actually checks (2-name blacklist), not a laxer 'expected branch' framing"

# ---------- 2. cleanup: ONE shared section, referenced from every documented terminal path ----------
assert_eq "0" "$(has "$b" '## Limpieza del worktree')" "orchestrator body has a dedicated worktree-cleanup section"
assert_eq "1" "$(grep -cF 'git worktree remove <repo-root>/.claude/worktrees/agent-' "$F")" "the literal cleanup command appears exactly ONCE (one shared section, unlike discovery-orchestrator's two inline copies)"

# every terminal path from step 2 onward must point at the shared section by name
for path_marker in \
  'el worktree (ver "## Limpieza del worktree" más abajo).** Si `BLOCKED`' \
  'otro camino terminal (ver "## Limpieza del worktree" más abajo, mismo fallo blando' \
  'limpia el worktree (ver "## Limpieza del worktree" más' \
  '"## Limpieza del worktree" más abajo) y tu veredicto final es `BLOCKED <hallazgo concreto>`' \
  'salta directamente a "## Limpieza del worktree" y tu veredicto es `BLOCKED merge en master' \
  'sigue el camino normal de "## Limpieza del worktree" más abajo'
do
  assert_eq "0" "$(has "$b" "$path_marker")" "terminal path references the shared cleanup section: ${path_marker:0:40}…"
done
# 6 references + 1 section header = 7 total mentions of the section name
assert_eq "7" "$(grep -cF 'Limpieza del worktree' "$F")" "cleanup section is named exactly 7 times: 1 header + 6 terminal-path pointers (implementer BLOCKED, cut-rule timeout, quality-fixer KO, reviewer KO/breaker-BLOCKED, master-guard trip, merge-conflict)"

# ---------- 3. I3: repo root resolved once, absolute paths built from it ----------
assert_eq "0" "$(has "$b" 'git rev-parse --show-toplevel')" "orchestrator resolves the repo root via git rev-parse --show-toplevel (I3)"
assert_eq "1" "$(grep -cF 'git rev-parse --show-toplevel' "$F")" "repo root resolved exactly once"
assert_eq "0" "$(has "$b" '<repo-root>/.claude/worktrees/agent-')" "worktree paths are built from <repo-root>, genuinely absolute"
# the worktree value passed to quality-fixer/reviewer and the cleanup command must both use the
# <repo-root>-anchored form — count how many times each construct appears as an actual VALUE
assert_eq "0" "$(has "$b" 'worktree: <repo-root>/.claude/worktrees/agent-<agentId del paso 2>')" "quality-fixer's worktree: header value is <repo-root>-anchored, not bare-relative"

# ---------- 4. I4: git merge conflict is a documented terminal path ----------
assert_eq "0" "$(has "$b" 'git merge --abort')" "merge conflict handling aborts the merge (I4)"
assert_eq "0" "$(has "$b" 'KO merge con conflicto')" "merge conflict has its own KO verdict, distinct from a clean merge"

# ---------- 5. I5: cut-rule for an implementer that never returns ----------
assert_eq "0" "$(has "$b" 'Regla de corte')" "implementation-orchestrator documents a cut-rule (I5, mirrors discovery-orchestrator's spiker timeout)"
assert_eq "0" "$(has "$b" 'KO implementer: sin respuesta')" "cut-rule names its own terminal verdict"
assert_eq "0" "$(has "$b" 'maxTurns: 25')" "cut-rule is anchored to the orchestrator's own maxTurns ceiling, not an unbounded wait"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
