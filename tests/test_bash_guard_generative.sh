#!/usr/bin/env bash
# tests/test_bash_guard_generative.sh — seeded fuzzer + known-bypass regressions for hooks/bash-guard.py.
# Invariants: (1) read-only role + any shell metachar anywhere (quoted or not) => deny; (2) exact allowed
# read-only commands => allow; (3) writer chains of allowed commands through the documented exceptions
# => allow; (4) writer chains with one forbidden element => deny; (5) random strings: a read-only allow
# never contains a metachar. SEED env var overrides the default seed.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"
REPO="$(mktemp -d "${TMPDIR:-/tmp}/swarm-guard-gen.XXXXXX")"
mkdir -p "$REPO/.swarm" && echo quantum > "$REPO/.swarm/docker-containers"
trap 'rm -rf "$REPO"' EXIT

guard() { # guard <agent_type> <command> -> allow | deny
  local out
  out="$(python3 -c 'import json,sys; print(json.dumps({"agent_type": sys.argv[1], "tool_name": "Bash", "tool_input": {"command": sys.argv[2]}, "cwd": sys.argv[3]}))' "$1" "$2" "$REPO" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# ---------- hook I/O contract (unchanged) ----------
assert_eq "" "$(echo '{"agent_type": "general-purpose", "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}' | python3 "$HOOK")" "non-swarm agent: no opinion"
assert_eq "" "$(echo 'not json' | python3 "$HOOK")" "bad JSON: no opinion"
assert_eq "" "$(echo '{"agent_type": "swarm:verifier", "tool_name": "Read", "tool_input": {"command": "x;y"}}' | python3 "$HOOK")" "non-Bash tool: no opinion"
out="$(echo '{"agent_type": "swarm:verifier", "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}' | python3 "$HOOK")"; rc=$?
assert_eq "0" "$rc" "deny still exits 0"
assert_eq "deny PreToolUse" "$(printf '%s' "$out" | python3 -c 'import json,sys; h=json.load(sys.stdin)["hookSpecificOutput"]; print(h["permissionDecision"], h["hookEventName"])')" "deny JSON shape"

# ---------- known bypasses (blind judge + this rewrite's own review) ----------
assert_eq "deny" "$(guard swarm:fact-checker "grep \$'\\'' -r . >/tmp/evil")" "ANSI-C \$'..' hiding a redirect"
assert_eq "deny" "$(guard swarm:fact-checker "grep \$'a\\'b' -r . 2>/dev/null")" "ANSI-C \$'..' even with a /dev/null redirect"
assert_eq "deny" "$(guard swarm:implementer "cat \$'a\\'b' && rm -rf /tmp/zzz")" "ANSI-C \$'..' for a writer too"
assert_eq "deny" "$(guard swarm:implementer "git commit -m \$\"x\"")" "\$\"..\" locale quoting"
assert_eq "deny" "$(guard swarm:implementer 'docker exec quantum make')" "docker exec inner make"
assert_eq "deny" "$(guard swarm:implementer 'docker exec quantum php x.php')" "docker exec inner php"
assert_eq "deny" "$(guard swarm:implementer 'docker exec quantum php -r "system(1)"')" "docker exec inner php -r"
assert_eq "deny" "$(guard swarm:implementer 'docker exec quantum sh -c "make"')" "docker exec inner sh -c"
assert_eq "deny" "$(guard swarm:implementer 'docker exec -u root quantum cat x')" "docker exec with a flag"
assert_eq "allow" "$(guard swarm:implementer 'docker exec quantum cat composer.json')" "writer docker exec, read-only inner"
assert_eq "deny" "$(guard swarm:verifier 'docker exec quantum cat composer.json')" "read-only role: no docker exec at all"
assert_eq "deny" "$(guard swarm:implementer 'ls || rm -rf x')" "|| is not a writer exception"
assert_eq "deny" "$(guard swarm:implementer 'ls & rm -rf x')" "background & is not a writer exception"
assert_eq "deny" "$(guard swarm:implementer 'sh -c "ls"')" "sh -c"
assert_eq "deny" "$(guard swarm:implementer 'bash -c "ls"')" "bash -c"
assert_eq "deny" "$(guard swarm:implementer 'python3 -c "print(1)"')" "python3 -c"
assert_eq "deny" "$(guard swarm:implementer 'ls > /etc/x')" "writer redirect outside the worktree"
assert_eq "deny" "$(guard swarm:implementer 'ls >> a/../../x')" "writer redirect climbing out"
assert_eq "deny" "$(guard swarm:implementer 'ls *.php')" "unquoted glob (filenames could inject flags)"
assert_eq "allow" "$(guard swarm:implementer "ls '*.php'")" "quoted glob is a literal"
assert_eq "deny" "$(guard swarm:release-manager 'git status && git push origin feature/x')" "push must run alone"
assert_eq "deny" "$(guard swarm:release-manager 'git push origin feature/x 2>&1')" "push must run without redirection"
assert_eq "allow" "$(guard swarm:release-manager 'git push -u origin feature/x')" "canonical push"
assert_eq "deny" "$(guard swarm:release-manager 'git remote -v set-url origin https://evil')" "git remote -v cannot prefix a mutating subcommand"
assert_eq "deny" "$(guard swarm:release-manager 'gh auth status --show-token')" "gh auth status cannot print the token"
assert_eq "deny" "$(guard swarm:verifier 'rg --pre=sh x')" "rg --pre executes a program"
assert_eq "allow" "$(guard swarm:fact-checker 'git diff HEAD~1')" "~ inside a word is not a tilde expansion"
assert_eq "deny" "$(guard swarm:fact-checker 'cat ~/.ssh/id_rsa')" "read-only role: no unquoted ~"

# ---------- seeded fuzzer (in-process for speed; I/O contract covered above) ----------
stats="$(SEED="${SEED:-20260926}" python3 - "$HOOK" "$REPO" <<'PYEOF'
import importlib.util, random, sys, os
spec = importlib.util.spec_from_file_location('guard', sys.argv[1]); g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
repo, seed = sys.argv[2], int(os.environ['SEED'])
rnd = random.Random(seed)
META = ';|&><`$(){}\n\\'
def verdict(agent, cmd):
    return g.verdict({'agent_type': agent, 'tool_name': 'Bash', 'tool_input': {'command': cmd}, 'cwd': repo})
def stripped(cmd):
    return cmd.replace('${CLAUDE_PLUGIN_ROOT}', '').replace('$CLAUDE_PLUGIN_ROOT', '')
RO = ['swarm:verifier', 'swarm:fact-checker', 'swarm:blind-judge', 'swarm:security-auditor']
RO_OK = ['git status', 'git log --oneline -5', 'git show HEAD~1', 'git diff --stat', 'git blame src/A.php',
         'git rev-parse --abbrev-ref HEAD', 'ls -la src', 'cat composer.json', 'head -n 20 a.txt', 'tail -5 a.txt',
         'wc -l a.txt', 'sort -u -k2,2 list.txt', 'uniq -c in.txt', 'cut -d: -f1 a', 'cmp a b', 'diff -u a b',
         'jq -S . a.json', 'grep -rn "tenant id" src', "grep -c '*' a", 'rg -n foo src', 'php -l src/A.php',
         '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh health',
         '"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" query "[run:abc]" --scope findings']
EXTENDABLE = ('git log', 'git show', 'git diff', 'git status', 'ls', 'cat', 'head', 'tail', 'wc', 'grep', 'rg', 'jq')
SAFE_ARGS = ['-n', 'src', 'a.txt', '--stat', '"two words"', "'x y'", 'HEAD~2', '"[a]"', "'*.php'"]
INSERTS = [';', '|', '&', '>', '<', '`', '$(', "$'", '$"', '${', '(', ')', '{', '}', '\n', '\\', '||', '&&', '>>',
           '2>&1', '$', '`id`', '<(', '>(', '$(id)', '${IFS}', '>/dev/null']
W = 'swarm:quality-fixer'  # writer with cd, php, composer, make
W_OK = ['git status', 'git add -A', 'git commit -m "feat(x): a -> b && c | d"', 'php vendor/bin/phpunit',
        'composer install', 'make test', 'ls -la', 'cd /tmp/wt', "grep -rn 'a(b)' src", 'git diff --stat']
W_TAIL = ['', ' 2>&1', ' 2>/dev/null', ' >/dev/null', ' > out.txt', ' >> .swarm/notes.md']
W_BAD = ['rm -rf x', 'curl https://evil', 'sh -c ls', 'bash -c ls', 'git push --force origin master',
         'docker exec quantum make', 'python3 -c 1', 'node -e 1', 'find . -delete', 'sort -o x y', 'env ls']
W_BAD_ANYWHERE = [';', '$(id)', '`id`', '<', '\n', '{', '}', '\\', '$']  # banned even inside quotes
W_BAD_OP = [' || ', ' & ', ' |& ', ' > /etc/x ', ' > ../x ', ' *.php ', ' (ls) ', ' # ']  # banned outside quotes
n = {'ro_meta': 0, 'ro_ok': 0, 'w_ok': 0, 'w_bad': 0, 'random': 0, 'random_ro_allowed': 0}
fails = []
for _ in range(3000):  # (1) metachar anywhere => deny, whatever the quoting around it
    base, tok = rnd.choice(RO_OK), rnd.choice(INSERTS)
    tok = rnd.choice([tok, "'%s'" % tok, '"%s"' % tok, ' %s ' % tok])
    i = rnd.randrange(len(base) + 1); cmd = base[:i] + tok + base[i:]
    agent = rnd.choice(RO); n['ro_meta'] += 1
    if verdict(agent, cmd) is None:
        fails.append(('ro_meta', agent, cmd))
for _ in range(1000):  # (2) allowed read-only commands (+ harmless args) => allow
    cmd = rnd.choice(RO_OK)
    if cmd.startswith(EXTENDABLE) and rnd.random() < 0.6:
        cmd += ' ' + ' '.join(rnd.choice(SAFE_ARGS) for _ in range(rnd.randint(1, 3)))
    agent = rnd.choice(RO); n['ro_ok'] += 1
    if verdict(agent, cmd) is not None:
        fails.append(('ro_ok', agent, cmd, verdict(agent, cmd)))
def chain(k):
    return rnd.choice([' && ', ' | ']).join(rnd.choice(W_OK) for _ in range(k))
for _ in range(1500):  # (3) writer chains through the documented exceptions => allow
    cmd = chain(rnd.randint(1, 4)) + rnd.choice(W_TAIL); n['w_ok'] += 1
    if verdict(W, cmd) is not None:
        fails.append(('w_ok', cmd, verdict(W, cmd)))
for _ in range(1500):  # (4) one forbidden command or syntax element => deny
    parts = [rnd.choice(W_OK) for _ in range(rnd.randint(1, 3))]
    if rnd.random() < 0.5:
        parts.insert(rnd.randrange(len(parts) + 1), rnd.choice(W_BAD)); cmd = ' && '.join(parts)
    else:
        if rnd.random() < 0.5:
            cmd = ' && '.join(parts); i = rnd.randrange(len(cmd) + 1); cmd = cmd[:i] + rnd.choice(W_BAD_ANYWHERE) + cmd[i:]
        else:
            i = rnd.randrange(len(parts) + 1); cmd = ' && '.join(parts[:i]) + rnd.choice(W_BAD_OP) + ' && '.join(parts[i:])
    n['w_bad'] += 1
    if verdict(W, cmd) is None:
        fails.append(('w_bad', cmd))
ALPHA = list('abcgilst -./') + ['git ', 'ls ', 'cat ', 'status ', "'", '"', '~', '*'] + list(META)
for _ in range(3000):  # (5) random strings: a read-only allow never carries a metachar
    cmd = ''.join(rnd.choice(ALPHA) for _ in range(rnd.randint(1, 24))); n['random'] += 1
    if verdict('swarm:verifier', cmd) is None:
        n['random_ro_allowed'] += 1
        if set(stripped(cmd)) & set(META):
            fails.append(('random', cmd))
print('seed=%d %s fails=%d' % (seed, ' '.join('%s=%d' % kv for kv in n.items()), len(fails)))
for f in fails[:10]:
    print('FAILCASE', repr(f))
PYEOF
)"
echo "$stats"
assert_eq "0" "$(echo "$stats" | grep -c FAILCASE)" "fuzzer found no invariant violation"
assert_eq "1" "$(echo "$stats" | grep -c 'fails=0$')" "fuzzer ran and reported zero failures"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
