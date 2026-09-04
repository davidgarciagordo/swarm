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

has_file() { # has_file <path> <pattern> -> "0" (found) | "1" (not found)
  grep -qF -- "$2" "$1" && echo 0 || echo 1
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

# --- C1 fix-of-a-fix (Opus review of f1722a6): the url= re-verification must compare the PUSH url,
# not the fetch url — `git push` uses remote.<name>.pushurl when it is set, and it can diverge from
# what `git remote -v`/`git remote get-url` (no flag) prints. Comparing the fetch url would let a
# pushurl planted between phase A and phase B go undetected: same fetch url on both sides (matches,
# no discrepancy), but the push lands somewhere else entirely.
assert_eq "allow" "$(guard swarm:release-manager 'git remote get-url --push --all origin')" "release-manager can read ALL push urls (reuses the existing bare git remote entry, no new allowlist entry needed)"
# --- C1' fix-of-a-fix-of-a-fix (2nd Opus review of e4616b8): `--push` WITHOUT `--all` only prints the
# FIRST push url — but remote.<name>.pushurl (and, absent that, remote.<name>.url) is MULTI-VALUED in
# git, and `git push` pushes to ALL of them. A second `pushurl` line added between phase A and phase B
# defeats a bare `--push` comparison exactly like a bare (no-flag) comparison was defeated by a single
# pushurl in the previous round: the first line stays the same benign url (matches, no discrepancy),
# while the push ALSO lands on the second, attacker-controlled destination.
assert_eq "deny"  "$(guard swarm:release-manager 'git config --get-all remote.origin.pushurl')" "git config is denied outright (write-capable command family) — --all on get-url is the only available route, confirmed"

# --- fixture 1: single pushurl — fetch vs push still diverge (previous round's regression stays covered)
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/swarm-pushurl-fixture.XXXXXX")"
(
  cd "$fixture_dir" || exit 1
  git init -q
  git remote add origin https://github.com/owner/repo.git
  git config remote.origin.pushurl git@evil.example.com:attacker/repo.git
)
fetch_url="$(git -C "$fixture_dir" remote get-url origin)"
push_url="$(git -C "$fixture_dir" remote get-url --push --all origin)"
assert_eq "1" "$([ "$fetch_url" != "$push_url" ] && echo 1 || echo 0)" "fixture: with pushurl set, fetch and push URLs really do diverge — comparing the fetch url would have approved a push to $push_url while showing the owner $fetch_url"
assert_eq "https://github.com/owner/repo.git" "$fetch_url" "fixture: fetch url is the benign one the owner would see if the doc compared the wrong url"
assert_eq "git@evil.example.com:attacker/repo.git" "$push_url" "fixture: push url is where git push actually goes — this is what release-manager.md now mandates comparing"
rm -rf "$fixture_dir"

# --- fixture 2 (NEW, C1'): TWO pushurls — `--push` alone (no --all) only prints the FIRST, silently
# hiding the second, attacker-added destination. `--push --all` is the only form that reveals both, and
# release-manager.md's rule is: more than one line → BLOCKED, never "compare against the first".
fixture2_dir="$(mktemp -d "${TMPDIR:-/tmp}/swarm-pushurl-multi-fixture.XXXXXX")"
(
  cd "$fixture2_dir" || exit 1
  git init -q
  git remote add origin https://github.com/owner/repo.git
  git config --add remote.origin.pushurl git@legit.example.com:owner/repo.git
  git config --add remote.origin.pushurl git@evil.example.com:attacker/repo.git
)
push_first_only="$(git -C "$fixture2_dir" remote get-url --push origin)"
push_all_lines="$(git -C "$fixture2_dir" remote get-url --push --all origin)"
push_all_count="$(echo "$push_all_lines" | wc -l | tr -d ' ')"
assert_eq "git@legit.example.com:owner/repo.git" "$push_first_only" "fixture: --push WITHOUT --all silently prints only the first (benign) destination — this is the exact gap that let a second pushurl through undetected"
assert_eq "2" "$push_all_count" "fixture: --push --all reveals BOTH destinations — this is what phase A/B must use to see the attacker's added pushurl"
assert_eq "0" "$(echo "$push_all_lines" | grep -qF 'evil.example.com' && echo 0 || echo 1)" "fixture: the attacker's destination is only visible with --all, never with bare --push"
rm -rf "$fixture2_dir"

# --- and the doc itself: both phase A (source of url=) and phase B (re-verification) must say
# --push --all, literally, and the multi-line case must be a named BLOCKED/discrepancia — a prose
# regression here is exactly what both rounds of the reviewer's finding were.
push_all_cmd_occurrences="$(grep -c 'git remote get-url --push --all origin' "$PLUGIN_ROOT/agents/release-manager.md")"
[ "$push_all_cmd_occurrences" -ge 2 ] && push_all_ok=0 || push_all_ok=1
assert_eq "0" "$push_all_ok" "release-manager.md prescribes 'git remote get-url --push --all origin' literally at least twice (phase A preview source, phase B re-verification) — found $push_all_cmd_occurrences"
assert_eq "0" "$(has_file "$PLUGIN_ROOT/agents/release-manager.md" 'BLOCKED remoto con varios destinos de push')" "documents the new BLOCKED verdict for a remote with more than one push destination"
assert_eq "0" "$(has_file "$PLUGIN_ROOT/agents/release-manager.md" 'destinos de push')" "documents the discrepancia line naming the destination COUNT, not trying to encode multiple URLs into url="
# no leftover single-line "git remote get-url --push origin" (missing --all) as a standalone fenced
# command anywhere — checked WITHOUT a trailing '$' anchor bug: trims each line fully and compares it
# for EXACT equality against the vulnerable form, so trailing text on the same line cannot hide a match.
bare_push_leftover="$(awk '{ line=$0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line); if (line == "git remote get-url --push origin") print }' "$PLUGIN_ROOT/agents/release-manager.md" | wc -l | tr -d ' ')"
assert_eq "0" "$bare_push_leftover" "no leftover standalone 'git remote get-url --push origin' command (missing --all) anywhere in release-manager.md"

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
