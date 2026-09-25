#!/usr/bin/env bash
# tests/test_req_check_advisory.sh — req-check.sh --advisory (/swarm:doctor): model tiers and
# stale origin/HEAD worktree base. Advisory never fails: always exit 0.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
RC="$PLUGIN_ROOT/scripts/req-check.sh"

fixture="$(make_fixture)"
SR="$fixture/.swarm"; mkdir -p "$SR"

assert_eq "0" "$(python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get('advisory') == ['models','worktree-base'] else 1)" "$PLUGIN_ROOT/requirements.json"; echo $?)" "requirements.json declares both advisory checks"

# no origin/HEAD: skipped, effective model per tier printed
out="$("$RC" --advisory --root "$fixture" --swarm-root "$SR")"
assert_eq "0" "$?" "advisory exits 0"
assert_eq "0" "$(echo "$out" | grep -q '^models: judgement -> opus ' && echo 0 || echo 1)" "judgement effective model printed"
assert_eq "0" "$(echo "$out" | grep -q '^models: standard -> sonnet ' && echo 0 || echo 1)" "standard effective model printed"
assert_eq "0" "$(echo "$out" | grep -q '^models: mechanical -> sonnet ' && echo 0 || echo 1)" "mechanical effective model printed"
assert_eq "0" "$(echo "$out" | grep -q 'no origin/HEAD' && echo 0 || echo 1)" "no origin/HEAD -> skipped"

# unavailable candidate -> WARN, still exit 0, effective model moves on
printf 'opus\n' > "$SR/models.unavailable"
out="$("$RC" --advisory --root "$fixture" --swarm-root "$SR")"
assert_eq "0" "$?" "advisory still exits 0 with unavailable models"
assert_eq "0" "$(echo "$out" | grep -q '^models: judgement -> fable ' && echo 0 || echo 1)" "effective judgement skips unavailable"
assert_eq "0" "$(echo "$out" | grep -q '^WARN models: judgement .*opus' && echo 0 || echo 1)" "unavailable candidate warned"

# isolate from the real user settings (a baseRef there would hide the stale warning)
export CLAUDE_CONFIG_DIR="$fixture/fake-user-claude"

# origin/HEAD behind HEAD -> WARN + snippet; never writes user settings
(
  cd "$fixture" || exit 1
  git update-ref refs/remotes/origin/main HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  echo x > extra.txt && git add extra.txt && git commit -qm "chore: ahead"
)
out="$("$RC" --advisory --root "$fixture" --swarm-root "$SR")"
assert_eq "0" "$?" "stale base still exits 0"
assert_eq "0" "$(echo "$out" | grep -q '^WARN worktree-base: origin/HEAD is 1 commit(s) behind HEAD' && echo 0 || echo 1)" "stale origin/HEAD warned with count"
assert_eq "0" "$(echo "$out" | grep -qF '{ "worktree": { "baseRef": "head" } }' && echo 0 || echo 1)" "baseRef snippet printed"
assert_eq "1" "$([ -e "$fixture/.claude/settings.json" ] && echo 0 || echo 1)" "doctor never writes .claude/settings.json"

# baseRef head already configured -> ok
mkdir -p "$fixture/.claude"
echo '{"worktree":{"baseRef":"head"}}' > "$fixture/.claude/settings.json"
out="$("$RC" --advisory --root "$fixture" --swarm-root "$SR")"
assert_eq "0" "$(echo "$out" | grep -q '^worktree-base: ok .*baseRef head set' && echo 0 || echo 1)" "configured baseRef -> ok"
assert_eq "1" "$(echo "$out" | grep -q '^WARN worktree-base' && echo 0 || echo 1)" "configured baseRef -> no warning"

# baseRef head in the USER settings -> ok too; a project baseRef overrides it
rm -rf "$fixture/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"worktree":{"baseRef":"head"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
out="$("$RC" --advisory --root "$fixture" --swarm-root "$SR")"
assert_eq "0" "$(echo "$out" | grep -q "^worktree-base: ok .*baseRef head set in $CLAUDE_CONFIG_DIR/settings.json" && echo 0 || echo 1)" "user-level baseRef head -> ok"
mkdir -p "$fixture/.claude"
echo '{"worktree":{"baseRef":"fresh"}}' > "$fixture/.claude/settings.json"
out="$("$RC" --advisory --root "$fixture" --swarm-root "$SR")"
assert_eq "0" "$(echo "$out" | grep -q '^WARN worktree-base' && echo 0 || echo 1)" "project baseRef fresh overrides user head -> warning"
rm -f "$CLAUDE_CONFIG_DIR/settings.json"

# origin/HEAD up to date -> ok
rm -rf "$fixture/.claude"
( cd "$fixture" && git update-ref refs/remotes/origin/main HEAD )
out="$("$RC" --advisory --root "$fixture" --swarm-root "$SR")"
assert_eq "0" "$(echo "$out" | grep -q '^worktree-base: ok (origin/HEAD contains HEAD)' && echo 0 || echo 1)" "fresh origin/HEAD -> ok"

# default (non-advisory) JSON contract unchanged
out="$("$RC" --root "$fixture")"
assert_eq "0" "$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if set(d)=={'ok','missing_required','missing_optional','checked'} else 1)" "$out"; echo $?)" "default JSON report keys unchanged"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
