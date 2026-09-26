#!/usr/bin/env python3
"""hooks/bash-guard.py — PreToolUse hook: deny-by-default Bash guard for `swarm:*` agents.
I/O: stdin JSON {agent_type, tool_name, tool_input.command, cwd}; non-swarm agent, non-Bash tool, empty
command or bad JSON -> exit 0 (no opinion); deny -> stdout JSON permissionDecision=deny, exit 0; an internal
error denies (fail closed). The guard never interprets shell syntax, it refuses it:
1. `${CLAUDE_PLUGIN_ROOT}`/`$CLAUDE_PLUGIN_ROOT` becomes this plugin's path (the only expansion kept).
2. Everyone: `$` backtick `\\` `;` `{` `}` `<`, newline and control chars are banned ANYWHERE, quoted or
   not. With no escapes left '...'/"..." are literal spans bash and shlex cannot disagree on (no `$'..'`
   desync). `#`, globs `* ? [ ]` and a word-leading `~` only inside quotes.
3. Read-only roles (not in `file_writers`) also ban `| & > ( )` ANYWHERE: one command, no chaining, no
   redirection, no docker exec. Writers (isolated worktrees) may use them inside quotes; outside, only:
   `&&`/`|` (`cd <wt> && git add -A`, each part checked alone), `2>&1` (`git rev-parse --abbrev-ref HEAD
   2>&1`), `[2]>/dev/null` (`ls -d docs/handoffs 2>/dev/null`), `>`/`>>` to a relative path without `..`
   (`cat a >> .swarm/context-pack.md`) and a word-leading `~/` (`grep Host ~/.ssh/config`).
4. Each part goes through shlex; argv[0] (or argv[0:2]) must EQUAL an allowlist entry, then `shape_ok`.
   Mutations (git push/remote, gh repo/pr) must run alone. A leading `SWARM_ROOT=<dir>` is accepted only when <dir>
   ends in `.swarm`, has no `..`, and (absolute) already exists. Redirects never target `.git/` or `.claude/` (except
   `.claude/agent-memory/`, memory-curator's archive): git hooks/config and agent settings run code later.
5. INTERP_DENY refuses inline/preloaded code so what runs is a file in the diff. It is NOT a sandbox for writers,
   which can write a file and run it; read-only roles get no interpreter at all.
"""
import json, os, re, shlex, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SAFE = r'[A-Za-z0-9._/-]+'
BANNED_ALL = set('$`\\;{}<\x7f') | {chr(c) for c in range(32) if c != 9}
RELPATH = re.compile(r'(?!/)(?!-)(?!(?:.*/)?\.\.(?:/|$))' + SAFE)
REDIRECT = re.compile(r'(>>?)(&?)[ \t]*(' + SAFE + ')')
BRANCH = re.compile(r'[A-Za-z0-9][A-Za-z0-9._/-]*')
REMOTE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*')
OWNER_REPO = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)?')
TEXT = re.compile(r'[^\'"]*')
URL = re.compile(r'(?:https?|ssh|git)://[A-Za-z0-9.@_-]+(?::[0-9]+)?(?:/[A-Za-z0-9._/-]*)?'
                 r'|file:///[A-Za-z0-9._/-]*|[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:[A-Za-z0-9._/-]+|\.{0,2}/[A-Za-z0-9._/-]*')
PROTECTED = {'master', 'main', 'develop', 'dev', 'development', 'trunk', 'stable', 'release', 'production', 'prod', 'head', '@'}
FIND_DENY = {'-exec', '-execdir', '-ok', '-okdir', '-delete', '-fprint', '-fprint0', '-fprintf', '-fls'}
INTERP_DENY = {'python3': ('-c',), 'python': ('-c',),
               'node': ('-e', '--eval', '-p', '--print', '-r', '--require', '--import', '--loader', '--experimental-loader'),
               'php': ('-r', '-B', '-R', '-E')}
PHP_INI_DENY = ('auto_prepend_file', 'auto_append_file', 'extension', 'zend_extension')  # `php -d` that loads code
SWARM_ROOT_RE = re.compile(r'SWARM_ROOT=(' + SAFE + ')')
RO_ARG_DENY = {  # read-only roles: package/analysis tools may not switch dir or registry, fix, or write a report
    'npm': lambda a: (a[:1] == ['audit'] and 'fix' in a) or any(w.split('=')[0] in (
        '--registry', '--prefix', '--userconfig', '--globalconfig', '--cache', '--script-shell', '--node-options') for w in a),
    'composer': lambda a: any(w.split('=')[0] == '--working-dir' or w.startswith('-d') for w in a),
    'php': lambda a: a[:1] in (['vendor/bin/phpmd'], ['vendor/bin/deptrac']) and any(
        w.split('=')[0] in ('--report-file', '--output', '-o') or w.startswith('--reportfile') for w in a[1:]),
}
SUB_ALLOWED = {('gh', 'repo'): {'create'}, ('gh', 'pr'): {'create'}, ('gh', 'auth'): {'status'},
               ('claude', 'plugin'): {'list'}, ('git', 'remote'): {None, '-v', 'get-url', 'add'}}
GH_CREATE = {'repo': {'--public': None, '--private': None, '--push': None, '--remote': REMOTE, '--description': TEXT,
                      '--source': re.compile(r'\.')},  # only THIS repo is published
             'pr': {'--draft': None, '--base': BRANCH, '--head': BRANCH, '--repo': OWNER_REPO, '--title': TEXT,
                    '--body-file': RELPATH}}
DOCKER_INNER = {'git status', 'git log', 'git diff', 'git show', 'git rev-parse', 'ls', 'cat', 'head',
                'tail', 'wc', 'grep', 'jq', 'cmp', 'diff', 'sort', 'uniq', 'cut', 'tr', 'php -l'}
MUTATIONS = {('git', 'push'), ('git', 'remote'), ('gh', 'repo'), ('gh', 'pr')}


def split_commands(cmd, writer):
    """(parts without their redirections, redirected?) — or None when the syntax is refused."""
    if BANNED_ALL & set(cmd) or (not writer and set('|&>()') & set(cmd)):
        return None
    parts, cur, quote, i, redirected = [], '', None, 0, False
    while i < len(cmd):
        c = cmd[i]
        if quote or c in '\'"':
            quote = None if c == quote else (quote or c)
            cur, i = cur + c, i + 1
            continue
        word_start = cur == '' or cur[-1] in ' \t'
        if c in '#()*?[]' or (c == '~' and (word_start or cur[-1] in '=:')
                                   and not (writer and word_start and cmd.startswith('~/', i))):
            return None
        if cmd.startswith('&&', i) or (c == '|' and not cmd.startswith(('||', '|&'), i)):
            parts.append(cur)
            cur, i = '', i + (2 if c == '&' else 1)
            continue
        if c in '|&':  # `||`, `|&`, background `&`, `&>`
            return None
        if c == '>':
            cur = cur[:-1] if re.search(r'(^|[ \t])[12]$', cur) else cur  # the fd of `2>` / `1>&2`
            m = REDIRECT.match(cmd, i)
            if not m or (m.group(2) and m.group(3) not in ('1', '2')) or (
                    not m.group(2) and m.group(3) != '/dev/null' and not RELPATH.fullmatch(m.group(3))):
                return None
            parts_of = [p for p in m.group(3).split('/') if p not in ('', '.')]
            if '.git' in parts_of or (parts_of[:1] == ['.claude'] and parts_of[1:2] != ['agent-memory']):
                return None
            redirected, i = True, m.end()
            continue
        cur, i = cur + c, i + 1
    return None if quote else (parts + [cur], redirected)


def allowlisted(argv, allow):
    """argv[0] (or argv[0:2]) equals an entry; plugin scripts only by plugin path (`scripts/mem-` = the family)."""
    rel = argv[0][len(ROOT) + 1:] if argv[0].startswith(ROOT + '/') and '..' not in argv[0].split('/') else ''
    mem = rel.startswith('scripts/mem-') and rel.endswith('.sh') and rel.count('/') == 1 \
        and os.path.isfile(os.path.join(ROOT, rel))
    return any((rel == e or (e == 'scripts/mem-' and mem)) if e.startswith('scripts/')
               else e.split(' ') == argv[:len(e.split(' '))] for e in allow)


def gh_create_ok(kind, args):
    """`gh repo|pr create`: closed flag set with value shapes; repo takes one name, pr needs --base/--head."""
    spec, pos, it = GH_CREATE[kind], [], iter(args)
    for w in it:
        name, eq, val = w.partition('=')
        if not w.startswith('-'):
            pos.append(w)
        elif name not in spec or (spec[name] is None and eq) or (spec[name] is not None and (
                not spec[name].fullmatch(v := val if eq else next(it, '-')) or v.startswith('-'))):
            return False
    if kind == 'repo':
        return len(pos) == 1 and bool(OWNER_REPO.fullmatch(pos[0]))
    return pos == [] and all(sum(w.split('=')[0] == f for w in args) == 1 for f in ('--base', '--head'))


ARG_DENY = {  # options that write a file or run a program although the command itself only reads
    'find': lambda a: FIND_DENY & set(a),  # sort: `-o`/`-T` also inside a cluster, GNU long abbreviations too
    'sort': lambda a: any(re.match(r'-[^-ktS]*[oT]', w) or (w.startswith('--') and len(w) > 2 and any(
        d.startswith(w[2:].split('=')[0]) for d in ('output', 'compress-program', 'temporary-directory')))
        for w in a[:a.index('--') if '--' in a else len(a)]),
    'uniq': lambda a: '--' in a or sum(1 for k, w in enumerate(a) if (not w.startswith('-') or w == '-') and (
        k == 0 or a[k - 1] not in ('-f', '-s', '-w', '--skip-fields', '--skip-chars', '--check-chars'))) > 1,  # OUTPUT
    'jq': lambda a: {'-i', '--in-place'} & set(a),
    'rg': lambda a: any(w.split('=')[0] in ('--pre', '--pre-glob', '--hostname-bin') for w in a),
}


def shape_ok(argv, ro):
    """Per-command rules an exact allowlist prefix cannot express."""
    cmd, args, two, sub = argv[0], argv[1:], tuple(argv[:2]), (argv[2] if len(argv) > 2 else None)
    if (two in SUB_ALLOWED and sub not in SUB_ALLOWED[two]) or (argv[:3] == ['git', 'remote', '-v'] and len(argv) > 3) \
            or (cmd in ARG_DENY and ARG_DENY[cmd](args)) or (ro and cmd in RO_ARG_DENY and RO_ARG_DENY[cmd](args)) \
            or (two == ('php', '-l') and (len(argv) < 3 or any(w.startswith('-') for w in argv[2:]))) \
            or (ro and cmd == 'git' and any(w.split('=')[0] == '--output' for w in args)) \
            or (two == ('gh', 'auth') and {'-t', '--show-token'} & set(args)) \
            or (two == ('composer', 'update') and all(w.startswith('-') for w in argv[2:])):  # whole tree
        return False
    if cmd == 'php' and any(v.split('=')[0].strip() in PHP_INI_DENY for v in
                            [w[2:] for w in args if w.startswith('-d') and w != '-d']
                            + [args[k + 1] for k, w in enumerate(args[:-1]) if w == '-d']):
        return False
    for flag in INTERP_DENY.get(cmd, ()):  # inline code: `-c`, `-cCODE`, `--eval=CODE`, clusters `-pe`
        if any(w.split('=')[0] == flag or (len(flag) == 2 and (w.startswith(flag) or (
                re.fullmatch(r'-[A-Za-z]+', w) and flag[1] in w))) for w in args):
            return False
    if two == ('git', 'branch'):  # only the orphan branch of a platform worktree
        return len(argv) == 4 and argv[2] == '-D' and bool(re.fullmatch(r'worktree-agent-[A-Za-z0-9]+', argv[3]))
    if two == ('git', 'push'):  # `git push [-u|--set-upstream] <remote> <branch>[:<branch>]`
        rest = argv[3:] if sub in ('-u', '--set-upstream') else argv[2:]
        halves = rest[1].split(':') if len(rest) == 2 else []
        dst = halves[-1].lower() if halves else 'head'
        return len(halves) in (1, 2) and bool(REMOTE.fullmatch(rest[0])) and all(BRANCH.fullmatch(h) for h in halves) \
            and dst not in PROTECTED and not dst.startswith(('head~', 'head^', 'refs/', 'heads/', 'tags/'))
    if argv[:3] == ['git', 'remote', 'add']:  # no flags; closed URL schemes (no `ext::` transport)
        return len(argv) == 5 and bool(REMOTE.fullmatch(argv[3]) and URL.fullmatch(argv[4]))
    if cmd == 'gh' and argv[1:2] in (['repo'], ['pr']) and sub == 'create':
        return gh_create_ok(argv[1], argv[3:])
    return True


def containers(cwd):
    """Container names of the nearest `.swarm/docker-containers`, walking up from cwd."""
    d = os.path.abspath(cwd or os.getcwd())
    while not os.path.isfile(os.path.join(d, '.swarm', 'docker-containers')):
        if d == os.path.dirname(d):
            return set()
        d = os.path.dirname(d)
    with open(os.path.join(d, '.swarm', 'docker-containers')) as fh:
        return {l.strip() for l in fh if l.strip() and not l.lstrip().startswith('#')}


def command_ok(argv, allow, ro, cwd):
    if argv[:2] == ['docker', 'exec']:  # writers only; no flags; listed container; read-only inner; no nesting
        inner = [e for e in allow if e in DOCKER_INNER]
        return (not ro and 'docker exec' in allow and len(argv) > 3 and bool(REMOTE.fullmatch(argv[2]))
                and argv[2] in containers(cwd) and command_ok(argv[3:], inner, True, cwd))
    return bool(argv) and allowlisted(argv, allow) and shape_ok(argv, ro)


def swarm_root_ok(word):
    """`SWARM_ROOT=<dir>` prefix: a `.swarm` dir, no `..`; absolute only if it already exists (no writes elsewhere)."""
    m = SWARM_ROOT_RE.fullmatch(word)
    parts = m.group(1).rstrip('/').split('/') if m else []
    return bool(parts) and parts[-1] == '.swarm' and '..' not in parts and (
        not m.group(1).startswith('/') or os.path.isdir(m.group(1)))


def verdict(data):  # None = allow, else the deny reason
    agent, cmd = data['agent_type'], data['tool_input']['command'].strip(' \t')
    if re.fullmatch(SAFE, ROOT):
        cmd = cmd.replace('${CLAUDE_PLUGIN_ROOT}', ROOT).replace('$CLAUDE_PLUGIN_ROOT', ROOT)
    with open(os.path.join(HERE, 'bash-allowlist.json')) as fh:
        cfg = json.load(fh)
    allow, writer = cfg.get('agents', {}).get(agent, cfg['default']), agent in cfg['file_writers']
    split = split_commands(cmd, writer)
    if split is None:
        return 'shell syntax outside the %s policy: %s' % ('writer' if writer else 'read-only', cmd)
    argvs = [a[1:] if a and swarm_root_ok(a[0]) else a for a in map(shlex.split, split[0])]
    if any(tuple(a[:2]) in MUTATIONS for a in argvs) and (len(argvs) > 1 or split[1]):
        return 'a push/remote/gh mutation must run alone (no chaining, no redirection): %s' % cmd
    for argv in argvs:
        if not command_ok(argv, allow, not writer, data.get('cwd') if isinstance(data.get('cwd'), str) else None):
            return '`%s` is not allowed for %s (allowlist or shape rule)' % (shlex.join(argv), agent)
    return None


def main():
    try:
        data = json.loads(sys.stdin.read())
        cmd = data['tool_input']['command'] if data.get('tool_name') == 'Bash' else None
    except (ValueError, TypeError, KeyError, AttributeError):
        sys.exit(0)
    if not (isinstance(cmd, str) and cmd.strip() and str(data.get('agent_type') or '').startswith('swarm:')):
        sys.exit(0)
    try:
        reason = verdict(data)
    except Exception as exc:  # fail closed
        reason = 'bash-guard internal error (%s): denied' % type(exc).__name__
    if reason:
        print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                                  'permissionDecisionReason': reason}}))


if __name__ == '__main__':
    main()
