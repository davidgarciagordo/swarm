#!/usr/bin/env bash
# tests/test_bash_allowlist_delivery.sh — allowlist de los 3 agentes del dominio delivery (fase 6),
# y la aserción estructural que importa: `git push` y `gh` existen en UN solo agente de todo el
# plugin. Un futuro autor que copie/pegue una entrada de allowlist rompe este test, no la producción.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"
ALLOWLIST="$PLUGIN_ROOT/hooks/bash-allowlist.json"

guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# --- release-manager: lee el repo, corre la suite del pack, empuja UNA rama, abre UN PR ---
assert_eq "allow" "$(guard swarm:release-manager 'git status --porcelain')" "release-manager can read the working tree state"
assert_eq "allow" "$(guard swarm:release-manager 'git remote -v')" "release-manager can list remotes"
assert_eq "allow" "$(guard swarm:release-manager 'git rev-parse --abbrev-ref HEAD')" "release-manager can read the current branch"
assert_eq "allow" "$(guard swarm:release-manager 'git log --no-merges --format=%s master..HEAD')" "release-manager can read the commit list"
assert_eq "allow" "$(guard swarm:release-manager 'php vendor/bin/phpunit')" "release-manager can run the pack test command"
assert_eq "allow" "$(guard swarm:release-manager 'composer test')" "release-manager can run composer test"
assert_eq "allow" "$(guard swarm:release-manager 'npm test')" "release-manager can run npm test"
assert_eq "allow" "$(guard swarm:release-manager 'make test')" "release-manager can run make test"
assert_eq "deny"  "$(guard swarm:release-manager 'php src/anything.php')" "release-manager does NOT get bare php (ruling 13)"
assert_eq "deny"  "$(guard swarm:release-manager 'composer install')" "release-manager does not touch dependencies"
assert_eq "deny"  "$(guard swarm:release-manager 'npm run build')" "release-manager does not get npm run (arbitrary scripts)"
assert_eq "deny"  "$(guard swarm:release-manager 'git commit -m x')" "release-manager NEVER creates commits (ruling 5)"
assert_eq "deny"  "$(guard swarm:release-manager 'git add -A')" "release-manager never stages anything"
assert_eq "deny"  "$(guard swarm:release-manager 'git merge feature/x')" "release-manager never merges"
assert_eq "deny"  "$(guard swarm:release-manager 'git checkout feature/x')" "release-manager never moves the working tree"
assert_eq "deny"  "$(guard swarm:release-manager 'git switch -c release/x')" "release-manager never creates/switches branches"
assert_eq "deny"  "$(guard swarm:release-manager 'git tag v1.0.0')" "release-manager creates no tags in v1"
assert_eq "deny"  "$(guard swarm:release-manager 'git worktree remove /tmp/x')" "release-manager owns no worktree"
# bootstrap de remoto (ruling 3): las dos formas mutantes que necesita, y nada más
assert_eq "allow" "$(guard swarm:release-manager 'gh repo create owner/repo --private --source=. --remote=origin --push')" "release-manager can create the repo the owner approved"
assert_eq "allow" "$(guard swarm:release-manager 'git remote add origin https://example.com/x.git')" "release-manager can add the origin the owner approved"
assert_eq "deny"  "$(guard swarm:release-manager 'gh repo delete owner/repo')" "…and nothing else under gh repo"
assert_eq "deny"  "$(guard swarm:release-manager 'git remote set-url origin https://example.com/x.git')" "…and never rewrites an existing remote URL (ruling 14)"

# --- backlog fix: SSH identity diagnosis reads ~/.ssh/config (read-only, additive to ruling 14) ---
# `cat`/`grep` are bare, argument-unrestricted allowlist entries for release-manager already (same
# as ls/head/tail) — reading ~/.ssh/config needs no new allowlist entry, it reuses these verbatim.
assert_eq "allow" "$(guard swarm:release-manager 'cat ~/.ssh/config')" "release-manager can read ~/.ssh/config for the SSH-alias hint (reuses the existing bare cat entry)"
assert_eq "allow" "$(guard swarm:release-manager 'grep Host ~/.ssh/config')" "…and can grep it too (reuses the existing bare grep entry)"
# it stays READ-only: nothing writes to it, and command injection chained after it still denies via
# the same segment-splitting machinery the guard already uses for every other command.
assert_eq "deny"  "$(guard swarm:release-manager 'cat ~/.ssh/config; rm -rf /')" "chaining a destructive command after the ssh-config read is still denied (segment splitting)"
assert_eq "deny"  "$(guard swarm:release-manager 'cat ~/.ssh/config && git push --force origin master')" "…and chaining a force-push after it is still denied (canonical gate, independent of the allowlist)"
assert_eq "deny"  "$(guard swarm:release-manager 'echo evil > ~/.ssh/config')" "release-manager has no write/redirection tool that could touch ~/.ssh/config"

# --- delivery-orchestrator: secuencia, no ejecuta trabajo de hoja (spec §3.2 regla 4) ---
assert_eq "allow" "$(guard swarm:delivery-orchestrator 'git status --porcelain')" "delivery-orchestrator can read state"
assert_eq "allow" "$(guard swarm:delivery-orchestrator 'git rev-parse --show-toplevel')" "delivery-orchestrator can anchor to the repo root"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git push origin feature/x')" "delivery-orchestrator has NO push"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'gh pr create --base master --head feature/x')" "delivery-orchestrator opens no PR itself"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git merge feature/x')" "delivery-orchestrator merges nothing"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git commit -m x')" "delivery-orchestrator commits nothing"

# --- handoff-writer: read-only + Write nativo, cero mutación por shell ---
assert_eq "allow" "$(guard swarm:handoff-writer 'git log --oneline -20')" "handoff-writer can read recent history"
assert_eq "allow" "$(guard swarm:handoff-writer 'ls docs/superpowers/handoffs')" "handoff-writer can look for the handoffs directory"
assert_eq "deny"  "$(guard swarm:handoff-writer 'git add -A')" "handoff-writer never stages (ruling 9)"
assert_eq "deny"  "$(guard swarm:handoff-writer 'git commit -m x')" "handoff-writer never commits (ruling 9)"
assert_eq "deny"  "$(guard swarm:handoff-writer 'git push origin feature/x')" "handoff-writer never pushes"
assert_eq "deny"  "$(guard swarm:handoff-writer 'composer install')" "handoff-writer touches no package manager"

# --- aserción estructural: el privilegio vive en UN solo sitio ---
holders="$(python3 - "$ALLOWLIST" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
buckets = dict(data.get('agents', {}))
buckets['default'] = data.get('default', [])
for name, prefixes in sorted(buckets.items()):
    for p in prefixes:
        if p == 'git push' or p == 'gh' or p.startswith('gh '):
            print("%s|%s" % (name, p))
PYEOF
)"
push_holders="$(echo "$holders" | grep -c '|git push$' || true)"
assert_eq "1" "$push_holders" "exactly ONE allowlist entry in the whole plugin grants git push"
assert_eq "0" "$(echo "$holders" | grep '|git push$' | grep -qx 'swarm:release-manager|git push' && echo 0 || echo 1)" "and that entry is swarm:release-manager"
gh_others="$(echo "$holders" | grep '|gh' | grep -v '^swarm:release-manager|' | wc -l | tr -d ' ')"
assert_eq "0" "$gh_others" "no agent other than release-manager gets any gh prefix"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
