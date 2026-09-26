#!/usr/bin/env python3
"""tests/test_guard.py — hooks/bash-guard.py as a black box: regression table + seeded properties.

Contract under test (the guard's own docstring): deny-by-default for `swarm:*`; `$ ` \\ ; { } <`,
newline and control chars refused anywhere (quoted or not) for everyone, except the literal
`${CLAUDE_PLUGIN_ROOT}`; read-only roles (not in `file_writers`) also refuse `| & > ( )` anywhere;
unquoted globs `* ? [ ]`, `#` and `~` are refused; argv[0] / argv[0:2] must equal an allowlist
entry; a denied part anywhere in a chain denies the whole call. Anything that is not a swarm Bash
call gets no opinion (exit 0, no output).

The regression table tests/fixtures/guard_cases.jsonl was captured from the previous guard's
suite: every old DENY stays a deny (a rewrite may never loosen), old ALLOWs are kept unless the
metachar contract above refuses them, they fell to `default` (no `find`: agents with no entry,
the Bash-less `reviewer` included, get the tightest list), or their `SWARM_ROOT=` names a directory
that is not an existing `.swarm` (three rows, flipped in 0.2: /abs/..., /tmp/x, /absolute/path/...).
"""
import json
import os
import shutil
import string
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swarmtest import ROOT, Suite, guard, guard_raw, parallel, rng  # noqa: E402

S = Suite('guard')
R = rng('guard')
CFG = json.load(open(os.path.join(ROOT, 'hooks', 'bash-allowlist.json')))
WRITERS = set(CFG['file_writers'])
AGENTS = sorted(CFG['agents'])
READ_ONLY = [a for a in AGENTS if a not in WRITERS]
ALL_PREFIXES = set(CFG['default']).union(*[set(v) for v in CFG['agents'].values()])
N = int(os.environ.get('SWARM_FUZZ_N', '60'))  # samples per property


def allow_of(agent):
    return CFG['agents'].get(agent, CFG['default'])


def word(n=None):
    return ''.join(R.choice(string.ascii_lowercase) for _ in range(n or R.randint(3, 8)))


# argv templates that are allowed for any agent whose allowlist holds the prefix
SAFE_FORMS = {
    'git status': lambda: 'git status',
    'git log': lambda: 'git log --oneline -%d' % R.randint(1, 50),
    'git diff': lambda: 'git diff --stat',
    'git show': lambda: 'git show HEAD',
    'git rev-parse': lambda: 'git rev-parse HEAD',
    'ls': lambda: 'ls src/%s' % word(),
    'cat': lambda: 'cat src/%s.php' % word(),
    'head': lambda: 'head -n %d %s.txt' % (R.randint(1, 99), word()),
    'tail': lambda: 'tail -n %d %s.txt' % (R.randint(1, 99), word()),
    'wc': lambda: 'wc -l %s.md' % word(),
    'grep': lambda: 'grep -rn %s src' % word(),
    'jq': lambda: 'jq . %s.json' % word(),
    'cmp': lambda: 'cmp %s %s' % (word(), word()),
    'diff': lambda: 'diff %s %s' % (word(), word()),
    'sort': lambda: 'sort %s.txt' % word(),
    'uniq': lambda: 'uniq %s.txt' % word(),
    'php -l': lambda: 'php -l src/%s.php' % word(),
    'find': lambda: 'find src -name %s.php' % word(),
    'mkdir': lambda: 'mkdir -p %s' % word(),
}


def safe_command(agent):
    forms = [p for p in SAFE_FORMS if p in allow_of(agent)]
    return SAFE_FORMS[R.choice(forms)]() if forms else None


def inject(cmd, piece):
    """Put `piece` at a random word boundary of `cmd` (never before argv[0])."""
    words = cmd.split(' ')
    i = R.randint(1, len(words))
    return ' '.join(words[:i] + [piece] + words[i:])


cases = []  # (agent, command, expected, why)

# ---------- regression table ----------
with open(os.path.join(ROOT, 'tests', 'fixtures', 'guard_cases.jsonl')) as fh:
    for line in fh:
        row = json.loads(line)
        cases.append((row['agent'], row['command'], row['expect'], 'regression'))

# ---------- P1: every agent can run its plain read commands ----------
SR_REPO = tempfile.mkdtemp(prefix='swarm-guard-sr.')
os.makedirs(os.path.join(SR_REPO, '.swarm'))
for _ in range(N):
    agent = R.choice(AGENTS)
    cmd = safe_command(agent)
    if cmd:
        cases.append((agent, cmd, 'allow', 'P1 plain allowlisted command'))
        cases.append((agent, 'SWARM_ROOT=%s/.swarm %s' % (SR_REPO, cmd), 'allow', 'P1 SWARM_ROOT= prefix is transparent'))
        cases.append((agent, 'SWARM_ROOT=.swarm %s' % cmd, 'allow', 'P1 relative SWARM_ROOT= is transparent'))
        cases.append((agent, 'SWARM_ROOT=%s %s' % (R.choice(['/tmp/%s' % word(), '/abs/%s/.swarm' % word(), '../%s/.swarm' % word(),
                                                            '.swarm/../x', '%s/.swarm/../..' % SR_REPO]), cmd),
                      'deny', 'P1 SWARM_ROOT= outside an existing .swarm dir'))

# ---------- P2: heads outside every allowlist are denied for everyone ----------
DANGEROUS = [h for h in ('rm', 'sudo', 'curl', 'wget', 'chmod', 'chown', 'dd', 'eval', 'exec', 'source', 'sh', 'bash',
                         'zsh', 'xargs', 'env', 'nohup', 'mv', 'perl', 'ruby', 'ssh', 'scp', 'nc', 'tee', 'awk', 'sed')
             if not any(p.split(' ')[0] == h for p in ALL_PREFIXES)]
S.check(len(DANGEROUS) >= 15, 'at least 15 dangerous heads stay outside every allowlist (got %s)' % DANGEROUS)
for _ in range(N):
    agent = R.choice(AGENTS)
    cases.append((agent, '%s %s' % (R.choice(DANGEROUS), word()), 'deny', 'P2 dangerous head'))
    cases.append((agent, 'zq%s --help' % word(), 'deny', 'P2 unknown head (deny by default)'))

# ---------- P3: banned-for-everyone syntax, quoted or not ----------
BANNED_ALL = ['; rm -rf %s', '$HOME', '$(id)', '`id`', '"$(id)"', "$'\\x3b'", '\\;', '{a,b}', '<%s', '"a\\"b"',
              '\n%s', '${IFS}', '"%s$USER"', "'a;b'", '"<%s"']
for _ in range(N):
    agent = R.choice(AGENTS)
    base = safe_command(agent)
    if base:
        piece = R.choice(BANNED_ALL)
        piece = piece % word() if '%s' in piece else piece
        cases.append((agent, inject(base, piece), 'deny', 'P3 banned-for-everyone syntax'))

# ---------- P4: read-only roles refuse | & > ( ) anywhere ----------
RO_PIECES = ['| head -5', '&& ls', '& ', '> out.txt', '2>&1', '2>/dev/null', '(ls)', '"(x)"', "'a|b'", '">"', '||', '|&']
for _ in range(N):
    agent = R.choice(READ_ONLY)
    base = safe_command(agent)
    if base:
        cases.append((agent, inject(base, R.choice(RO_PIECES)), 'deny', 'P4 read-only role, | & > ( )'))

# ---------- P5: unquoted globs / comments / tilde ----------
for _ in range(N):
    agent = R.choice(AGENTS)
    base = safe_command(agent)
    if base:
        cases.append((agent, inject(base, R.choice(['*.php', 'a?', '[ab]', '#x', '~', '~root/x'])), 'deny', 'P5 unquoted glob'))

# ---------- P6: one denied part denies the whole chain, writers included ----------
for _ in range(N):
    agent = R.choice(sorted(WRITERS & set(AGENTS)))
    base = safe_command(agent)
    if base:
        tail = '%s %s' % (R.choice(DANGEROUS), word())
        cases.append((agent, R.choice(['%s && %s', '%s | %s']) % (base, tail), 'deny', 'P6 denied part in a chain'))
        cases.append((agent, R.choice(['%s && %s', '%s | %s']) % (tail, base), 'deny', 'P6 denied part in a chain'))

# ---------- P7: pushes only as `git push [-u] <remote> <branch>`, never forced / protected ----------
RM = 'swarm:release-manager'
if RM in CFG['agents']:
    for _ in range(N // 2):
        branch = 'feature/%s' % word()
        cases.append((RM, 'git push origin %s' % branch, 'allow', 'P7 plain push'))
        flag = R.choice(['--force', '-f', '--force-with-lease', '--delete', '--mirror', '--all', '--tags',
                         '--receive-pack=/tmp/x', '--exec=/tmp/x', '--repo=evil', '--prune', '--follow-tags'])
        cases.append((RM, inject('git push origin %s' % branch, flag), 'deny', 'P7 destructive push flag'))
        cases.append((RM, 'git push origin %s' % R.choice(['master', 'main', 'develop', 'HEAD', 'x:main', 'refs/heads/x']),
                      'deny', 'P7 protected/ambiguous destination'))
        cases.append((RM, 'git push origin %s && ls' % branch, 'deny', 'P7 a push never chains'))
    for agent in [a for a in AGENTS if 'git push' not in allow_of(a)][:N // 4]:
        cases.append((agent, 'git push origin feature/%s' % word(), 'deny', 'P7 only release-manager pushes'))

# ---------- P10: read-only escapes the allowlist prefix cannot see (blind-judge 0.2 findings) ----------
RO_ESCAPES = [('rg', 'rg --hostname-bin=vendor/bin/phpunit x'), ('rg', 'rg --hostname-bin vendor/bin/phpunit x'),
              ('npm audit', 'npm audit fix --force'), ('npm audit', 'npm audit --registry=http://evil'),
              ('npm audit', 'npm audit --prefix /tmp'), ('composer audit', 'composer audit --working-dir=/tmp'),
              ('composer audit', 'composer audit -d /tmp'), ('composer show', 'composer show -d/tmp'),
              ('php vendor/bin/phpmd', 'php vendor/bin/phpmd src text x --reportfile out.txt'),
              ('php vendor/bin/phpmd', 'php vendor/bin/phpmd src text x --reportfile-html=o.html'),
              ('php vendor/bin/deptrac', 'php vendor/bin/deptrac analyse --output=x')]
for prefix, cmd in RO_ESCAPES:
    for agent in [a for a in READ_ONLY if prefix in allow_of(a)]:
        cases.append((agent, cmd, 'deny', 'P10 read-only tool escape'))
for agent in [a for a in READ_ONLY if 'npm audit' in allow_of(a)]:
    cases.append((agent, 'npm audit --json', 'allow', 'P10 plain audit still allowed'))
WRITER_ESCAPES = ['cat a > .git/hooks/pre-commit', 'cat a >> ./.git/config', 'cat a > sub/.git/hooks/x',
                  'cat a > .claude/settings.json', 'node -r ./evil.js x.js', 'node --require=./e.js x.js',
                  'node --import ./e.mjs x.js', 'php -d auto_prepend_file=evil.php -l x',
                  'php -dauto_append_file=e.php x.php', 'php -d extension=/tmp/e.so x.php', 'php -B x', 'php -R x']
for cmd in WRITER_ESCAPES:
    cases.append(('swarm:implementer', cmd, 'deny', 'P10 writer escape (git hooks, agent config, preloaded code)'))
for cmd in ['php -d memory_limit=-1 vendor/bin/phpstan', 'node x.js', 'cat a >> .swarm/context-pack.md']:
    cases.append(('swarm:implementer', cmd, 'allow', 'P10 ordinary writer command'))
if RM in CFG['agents']:
    cases.append((RM, 'git push origin feat:dev', 'deny', 'P10 dev is protected'))

cwd_cases = []  # (agent, command, cwd, expected, why)
# ---------- P9: docker exec only into a container the repo lists, read-only inner, writers only ----------
REPO = tempfile.mkdtemp(prefix='swarm-guard-cwd.')
os.makedirs(os.path.join(REPO, '.swarm'))
os.makedirs(os.path.join(REPO, 'sub', 'dir'))
LISTED = ['app%s' % word(2) for _ in range(3)]
with open(os.path.join(REPO, '.swarm', 'docker-containers'), 'w') as fh:
    fh.write('# containers\n' + '\n'.join(LISTED) + '\n')
DOCKER_WRITERS = [a for a in AGENTS if 'docker exec' in allow_of(a)]
INNER_OK = ['git status', 'ls src', 'cat composer.json', 'php -l src/a.php', 'grep -rn x src']
for _ in range(N // 2 if DOCKER_WRITERS else 0):
    agent, c = R.choice(DOCKER_WRITERS), R.choice(LISTED)
    cwd = R.choice([REPO, os.path.join(REPO, 'sub', 'dir')])
    cwd_cases.append((agent, 'docker exec %s %s' % (c, R.choice(INNER_OK)), cwd, 'allow', 'P9 listed container, read-only inner'))
    cwd_cases.append((agent, 'docker exec %s %s' % ('other' + word(), R.choice(INNER_OK)), cwd, 'deny', 'P9 unlisted container'))
    cwd_cases.append((agent, 'docker exec %s %s' % (c, R.choice(['rm -rf x', 'php x.php', 'git push origin x',
                                                                  'docker exec a ls', 'sh -c ls'])), cwd, 'deny', 'P9 inner must be read-only'))
    cwd_cases.append((agent, 'docker exec %s %s ls' % (R.choice(['--privileged', '-u', '-it', '-e']), c), cwd, 'deny', 'P9 no docker flags'))
    cwd_cases.append((R.choice(READ_ONLY), 'docker exec %s ls' % c, cwd, 'deny', 'P9 read-only roles never docker exec'))
    cwd_cases.append((agent, 'docker exec %s ls' % c, tempfile.gettempdir(), 'deny', 'P9 no containers file above cwd'))

results = parallel(lambda c: guard(c[0], c[1], c[2]), cwd_cases)
for (agent, cmd, cwd, want, why), got in zip(cwd_cases, results):
    S.check(got == want, '%s: %s %r (cwd %s) -> %s, expected %s' % (why, agent, cmd, cwd, got, want))
shutil.rmtree(REPO, ignore_errors=True)

results = parallel(lambda c: guard(c[0], c[1]), cases)
for (agent, cmd, want, why), got in zip(cases, results):
    S.check(got == want, '%s: %s %r -> %s, expected %s' % (why, agent, cmd, got, want))
shutil.rmtree(SR_REPO, ignore_errors=True)

# ---------- P8: no opinion outside swarm Bash calls ----------
noop = [
    json.dumps({'agent_type': 'general-purpose', 'tool_name': 'Bash', 'tool_input': {'command': 'rm -rf /'}}),
    json.dumps({'agent_type': 'swarm:implementer', 'tool_name': 'Write', 'tool_input': {'command': 'rm -rf /'}}),
    json.dumps({'tool_name': 'Bash', 'tool_input': {'command': 'rm -rf /'}}),
    json.dumps({'agent_type': 'swarm:reviewer', 'tool_name': 'Bash', 'tool_input': {'command': '   '}}),
    'not json at all', '', '[]', '{"agent_type": 7}',
]
for payload, (rc, out, err) in zip(noop, parallel(guard_raw, noop)):
    S.check(rc == 0 and not out.strip(), 'P8 no opinion (exit 0, no output) for %r -> rc=%s out=%r' % (payload[:60], rc, out[:80]))

S.done()
