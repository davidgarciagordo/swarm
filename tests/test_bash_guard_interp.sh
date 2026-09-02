#!/usr/bin/env bash
# tests/test_bash_guard_interp.sh — hooks/bash-guard.py deniega la evaluación inline de código
# (python3 -c, node -e/-p, php -r) aunque el intérprete esté en el allowlist del agente. Motivo:
# feasibility-spiker (fase 2) recibe python3/node/php para correr su spike en un worktree
# desechable; sin esta guarda, `python3 -c 'import os; os.system("rm -rf ~")'` pasaría el
# allowlist. Se prueba contra feasibility-spiker y contra value-critic (que no tiene intérpretes
# en su allowlist, para confirmar que sigue denegado por esa vía).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

A=swarm:feasibility-spiker
assert_eq "allow" "$(guard $A 'python3 spike.py')" "spiker: python3 <file> allowed"
assert_eq "deny"  "$(guard $A 'python3 -c print(1)')" "spiker: python3 -c denied"
assert_eq "deny"  "$(guard $A 'python3 spike.py && python3 -c print(1)')" "spiker: -c denied in any segment"
assert_eq "allow" "$(guard $A 'node spike.js')" "spiker: node <file> allowed"
assert_eq "deny"  "$(guard $A 'node -e 1')" "spiker: node -e denied"
assert_eq "deny"  "$(guard $A 'node -p 1')" "spiker: node -p denied"
assert_eq "deny"  "$(guard $A 'node --eval 1')" "spiker: node --eval denied"
assert_eq "allow" "$(guard $A 'php spike.php')" "spiker: php <file> allowed"
assert_eq "deny"  "$(guard $A 'php -r echo(1);')" "spiker: php -r denied"
assert_eq "deny"  "$(guard $A '/usr/bin/python3 -c print(1)')" "spiker: /usr/bin/python3 denied (not on allowlist by that path — not evidence of the -c check itself)"

# Regresión (hallazgo 1/2 de la review de T4): igualdad exacta de token no basta — estas formas
# son sintaxis válida y documentada de los propios intérpretes y ejecutan código inline igual que
# la forma con espacio. Sin el fix, todas pasaban.
assert_eq "deny"  "$(guard $A 'node --eval=1')" "spiker: node --eval=CODE (pegado con =) denied"
assert_eq "deny"  "$(guard $A 'node --print=1')" "spiker: node --print=CODE (pegado con =) denied"
assert_eq "deny"  "$(guard $A 'node -pe 1')" "spiker: node -pe (cluster de flags cortos) denied"
assert_eq "deny"  "$(guard $A 'python3 -cprint(1)')" "spiker: python3 -cCODE (pegado sin espacio) denied"
assert_eq "deny"  "$(guard $A "php -recho(1);")" "spiker: php -rCODE (pegado sin espacio) denied"
assert_eq "deny"  "$(guard $A 'SWARM_ROOT=/x node -pe 1')" "spiker: interp bypass still denied after SWARM_ROOT= prefix stripping (order-of-checks regression)"
assert_eq "deny"  "$(guard $A 'bash x.sh')" "spiker: bash not in allowlist"
assert_eq "deny"  "$(guard $A 'sh x.sh')" "spiker: sh not in allowlist"
assert_eq "deny"  "$(guard $A 'rm -rf spike')" "spiker: rm not in allowlist"
assert_eq "deny"  "$(guard $A 'git commit -m x')" "spiker: git commit not in allowlist"
assert_eq "deny"  "$(guard $A 'git push')" "spiker: git push not in allowlist"
assert_eq "deny"  "$(guard $A '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write decision --text x')" "spiker: NO direct .swarm writes from a worktree (protocol §3)"
assert_eq "allow" "$(guard $A 'cat /abs/repo/.swarm/context-pack.md')" "spiker: can read the canonical pack by absolute path"
assert_eq "allow" "$(guard $A 'mkdir -p spike')" "spiker: mkdir allowed inside its worktree"
assert_eq "allow" "$(guard $A 'npm test')" "spiker: npm allowed"
assert_eq "allow" "$(guard $A 'composer install')" "spiker: composer allowed"

# La guarda no afecta a agentes que NO tienen el intérprete en su lista (siguen denegados por allowlist).
assert_eq "deny" "$(guard swarm:value-critic 'python3 x.py')" "value-critic: python3 still denied by allowlist"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
