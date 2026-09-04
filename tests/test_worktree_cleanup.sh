#!/usr/bin/env bash
# tests/test_worktree_cleanup.sh — el worktree de `feasibility-spiker` NO se descarta solo.
#
# Fuga real observada en el smoke de fase 2: un `/swarm:run --tier=full` lanzó al spiker
# (`isolation: worktree`), el spike corrió y su finding se persistió bien, pero el worktree que la
# plataforma le creó (`.claude/worktrees/agent-<agentId>`) quedó huérfano en `git worktree list`
# al cerrar el run. La plataforma solo auto-limpia el worktree de un subagente que NO cambió nada,
# y un spike SIEMPRE escribe su `spike/`. El dueño de la limpieza es `discovery-orchestrator`:
# es quien lanza al spiker (y por tanto conoce su `agentId`) y quien recibe su reporte final.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
guard() { # guard <agent_type> <command> -> "allow" | "deny"
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# ---------- 1. discovery-orchestrator documenta captura de agentId + borrado ----------
ORCH="$PLUGIN_ROOT/agents/discovery-orchestrator.md"
assert_eq "0" "$([ -f "$ORCH" ] && echo 0 || echo 1)" "agents/discovery-orchestrator.md exists"
if [ -f "$ORCH" ]; then
  b="$(body "$ORCH")"
  assert_eq "0" "$(has "$b" 'agentId')" "orchestrator body notes the agentId from the spawn result"
  assert_eq "0" "$(has "$b" '.claude/worktrees/agent-')" "orchestrator body names the worktree path pattern .claude/worktrees/agent-<agentId>"
  assert_eq "0" "$(has "$b" 'git worktree remove')" "orchestrator body removes the spiker worktree with git worktree remove"
  assert_eq "0" "$(has "$b" '--force')" "orchestrator body uses --force (the spike leaves untracked files)"
  assert_eq "0" "$(has "$b" 'DONE')" "orchestrator body ties the cleanup to the spiker reporting DONE"
  assert_eq "0" "$(has "$b" 'BLOCKED')" "orchestrator body ties the cleanup to DONE or BLOCKED"
  assert_eq "0" "$(has "$b" 'memory-orchestrator')" "orchestrator body justifies the cleanup: the finding is already persisted via memory-orchestrator"
  assert_eq "0" "$(has "$b" 'warn: worktree del spiker no borrado')" "cleanup failure is a soft failure: one warn line, never a blocked verdict"
  assert_eq "0" "$(has "$b" 'git worktree')" "orchestrator body documents git worktree in its own bash allowlist"
  # camino descubierto por la review final: spiker lanzado (agentId en mano) que NUNCA reporta y
  # cae por la regla de corte — sin esto, el worktree se fuga igual que antes del fix, por otra vía.
  assert_eq "0" "$(has "$b" 'warn: feasibility-spiker sin respuesta')" "cut-rule timeout path names the spiker warn line"
  assert_eq "2" "$(grep -cF 'git worktree remove .claude/worktrees/agent-' "$ORCH")" "cleanup runs in BOTH paths: on DONE/BLOCKED (1bis) and on cut-rule timeout"
  # `git worktree remove` only deletes the directory, never the `worktree-agent-<agentId>` branch
  # the platform created — orphan branch leak, same shape as the worktree leak this file already
  # covers. discovery-orchestrator must delete it too, in BOTH paths (1bis + cut-rule timeout).
  assert_eq "0" "$(has "$b" 'git branch -D worktree-agent-')" "orchestrator body deletes the orphaned branch left by git worktree remove"
  assert_eq "2" "$(grep -cF 'git branch -D worktree-agent-' "$ORCH")" "branch cleanup runs in BOTH paths: on DONE/BLOCKED (1bis) and on cut-rule timeout"
fi

# ---------- 2. el allowlist real: solo discovery-orchestrator puede `git worktree` ----------
CMD='git worktree remove .claude/worktrees/agent-ae25ffb99d186c453 --force'
assert_eq "allow" "$(guard 'swarm:discovery-orchestrator' "$CMD")" "discovery-orchestrator CAN remove the spiker worktree"
assert_eq "deny"  "$(guard 'swarm:value-critic' "$CMD")"           "value-critic canNOT remove worktrees"
assert_eq "deny"  "$(guard 'swarm:feasibility-spiker' "$CMD")"     "the spiker canNOT remove its own worktree (it runs inside it)"
assert_eq "deny"  "$(guard 'swarm:options-generator' "$CMD")"      "options-generator canNOT remove worktrees"
assert_eq "deny"  "$(guard 'swarm:memory-orchestrator' "$CMD")"    "memory-orchestrator canNOT remove worktrees"
# el permiso es del prefijo de dos palabras `git worktree`, NO un `git` general
assert_eq "deny"  "$(guard 'swarm:discovery-orchestrator' 'git commit -m x')" "discovery-orchestrator still has no general git (commit denied)"
assert_eq "deny"  "$(guard 'swarm:discovery-orchestrator' 'git push')"        "discovery-orchestrator still has no general git (push denied)"
assert_eq "allow" "$(guard 'swarm:discovery-orchestrator' 'git worktree list')" "git worktree list also allowed (same two-word prefix)"

# ---------- 2bis. mismo huérfano, pero de RAMA: `git worktree remove` no borra `worktree-agent-<id>` ----------
CMD_BR='git branch -D worktree-agent-ae25ffb99d186c453'
assert_eq "allow" "$(guard 'swarm:discovery-orchestrator' "$CMD_BR")" "discovery-orchestrator CAN delete the spiker's orphaned branch"
assert_eq "deny"  "$(guard 'swarm:value-critic' "$CMD_BR")"           "value-critic canNOT delete branches"
assert_eq "deny"  "$(guard 'swarm:feasibility-spiker' "$CMD_BR")"     "the spiker canNOT delete its own branch (it runs inside the worktree, its parent does it)"
assert_eq "deny"  "$(guard 'swarm:options-generator' "$CMD_BR")"      "options-generator canNOT delete branches"
assert_eq "deny"  "$(guard 'swarm:discovery-orchestrator' 'git branch -D master')" "discovery-orchestrator cannot delete master via git branch -D"
assert_eq "deny"  "$(guard 'swarm:discovery-orchestrator' 'git branch -D main')"   "discovery-orchestrator cannot delete main via git branch -D"
assert_eq "deny"  "$(guard 'swarm:discovery-orchestrator' 'git branch -d worktree-agent-ae25ffb99d186c453')" "discovery-orchestrator cannot use the lowercase -d form"
assert_eq "deny"  "$(guard 'swarm:discovery-orchestrator' 'git branch -D some-other-branch')" "discovery-orchestrator cannot delete a branch outside the worktree-agent- prefix"
assert_eq "deny"  "$(guard 'swarm:discovery-orchestrator' 'git branch')" "discovery-orchestrator cannot run bare git branch (list)"

# ---------- 3. feasibility-spiker ya NO miente sobre el auto-borrado ----------
SPK="$PLUGIN_ROOT/agents/feasibility-spiker.md"
assert_eq "0" "$([ -f "$SPK" ] && echo 0 || echo 1)" "agents/feasibility-spiker.md exists"
if [ -f "$SPK" ]; then
  b="$(body "$SPK")"
  assert_eq "1" "$(has "$b" 'se descarta solo')" "spiker no longer claims the worktree discards itself (FALSE: auto-cleanup only when nothing changed)"
  assert_eq "0" "$(has "$b" 'discovery-orchestrator')" "spiker attributes the cleanup to its parent discovery-orchestrator"
  assert_eq "0" "$(has "$b" 'git worktree remove')" "spiker names the command its parent runs"
  assert_eq "0" "$(has "$b" 'git branch -D worktree-agent-')" "spiker also names the branch-delete command its parent runs (the worktree remove alone leaves the branch orphaned)"
  assert_eq "0" "$(has "$b" 'No es automático')" "spiker states explicitly that the cleanup is NOT automatic"
fi

# ---------- 4. el comando REAL funciona: add -> untracked file -> remove --force ----------
# Prueba que `git worktree remove <path> --force` borra de verdad un worktree con contenido sin
# commitear (exactamente el estado en el que el spiker deja el suyo), no solo que el guard lo deja
# pasar.
FIX="$(make_fixture)"
WT="$FIX/.claude/worktrees/agent-deadbeef0123456"
(
  cd "$FIX" || exit 1
  git worktree add "$WT" -b spike-throwaway -q 2>/dev/null
  mkdir -p "$WT/spike"
  echo "print('spike')" > "$WT/spike/x.py"
)
assert_eq "0" "$([ -d "$WT" ] && echo 0 || echo 1)" "throwaway worktree created"
assert_eq "0" "$(cd "$FIX" && git worktree list | grep -qF 'agent-deadbeef0123456' && echo 0 || echo 1)" "git worktree list shows the throwaway worktree"
# sin --force git se NIEGA mientras haya ficheros sin commitear: por eso el fix lo lleva
assert_eq "1" "$(cd "$FIX" && git worktree remove "$WT" >/dev/null 2>&1 && echo 0 || echo 1)" "git worktree remove WITHOUT --force refuses (untracked spike files)"
assert_eq "0" "$(cd "$FIX" && git worktree remove "$WT" --force >/dev/null 2>&1 && echo 0 || echo 1)" "git worktree remove --force succeeds"
assert_eq "1" "$([ -d "$WT" ] && echo 0 || echo 1)" "worktree directory is gone from disk"
assert_eq "1" "$(cd "$FIX" && git worktree list | grep -qF 'agent-deadbeef0123456' && echo 0 || echo 1)" "git worktree list no longer shows it — no orphan left"
rm -rf "$FIX"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
