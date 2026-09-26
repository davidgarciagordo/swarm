#!/usr/bin/env python3
"""hooks/bash-guard.py — PreToolUse hook: deny-by-default Bash guard for `swarm:*` agents.
I/O: stdin JSON {agent_type, tool_name, tool_input.command, cwd}; non-swarm agent, non-Bash tool, empty command or
bad JSON -> exit 0 (no opinion); deny -> stdout JSON permissionDecision=deny, exit 0; internal error -> deny.
1. Syntax is refused, never interpreted. `${CLAUDE_PLUGIN_ROOT}` is the only expansion kept. Everyone: `$` backtick
   `\\` `;` `{` `}` `<`, newline, control chars banned ANYWHERE; `#`, globs, word-leading `~` only inside quotes.
2. Read-only roles (not in `file_writers`) also ban `| & > ( )` anywhere. Writers, outside quotes, only: `&&`, `|`
   into a PIPE_OK filter, `2>&1`, `[2]>/dev/null`, `~/`, `>`/`>>` to a relative path without `..` and without a
   PROTECTED_ANY component or `.claude/` (bar agent-memory): git hooks, editor/MCP/direnv config run code later.
3. `cd`: a writer only into a LINKED worktree root; a read-only role only up to the git toplevel holding its cwd.
4. argv[0] (or argv[0:2]) must EQUAL an allowlist entry; then ARG_DENY and the POSITIVE `shapes` table of
   bash-allowlist.json. Mutations run alone; `SWARM_ROOT=<dir>` must name an existing `.swarm` dir.
5. Interpreters need a script file (no inline/preloaded code): NOT a sandbox for writers. Plugin scripts validate
   their own arguments: they, not this guard, are the boundary for what reaches a path.
"""
import json, os, re, shlex, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SAFE = r'[A-Za-z0-9._/-]+'
X = re.compile
BANNED_ALL = set('$`\\;{}<\x7f') | {chr(c) for c in range(32) if c != 9}
RELPATH = X(r'(?!/)(?!-)(?!(?:.*/)?\.\.(?:/|$))' + SAFE)
REDIRECT = X(r'(>>?)(&?)[ \t]*(' + SAFE + ')')
PROTECTED_ANY = {'.git', '.husky', '.githooks', '.vscode', '.mcp.json', '.envrc'}  # any path component
CONTAINER = X(r'[A-Za-z0-9][A-Za-z0-9._-]*')
FIND_DENY = {'-exec', '-execdir', '-ok', '-okdir', '-delete', '-fprint', '-fprint0', '-fprintf', '-fls'}
INTERP_DENY = {'python3': ('-c',), 'python': ('-c',), 'php': ('-r', '-B', '-R', '-E'),
               'node': ('-e', '--eval', '-p', '--print', '-r', '--require', '--import', '--loader', '--experimental-loader')}
INTERP_REPL = {'python3': {'-i'}, 'python': {'-i'}, 'node': {'-i', '--interactive'}, 'php': {'-a', '--interactive'}}
INTERP_VAL = {'python3': {'-W', '-X'}, 'python': {'-W', '-X'}, 'php': {'-d', '-c', '-z'},  # options taking a value
              'node': {'-C', '--conditions', '--input-type', '--title'}}
INTERP_RUN = {'-m', '--test'}  # module / test runner: code comes from files
INFO = {'-v', '-V', '--version', '-h', '--help'}
PHP_INI_DENY = ('auto_prepend_file', 'auto_append_file', 'extension', 'zend_extension')  # `php -d` that loads code
PIPE_OK = {'cat', 'head', 'tail', 'wc', 'grep', 'rg', 'jq', 'sort', 'uniq', 'cut', 'tr', 'cmp', 'diff'}
UNIQ_VAL = ('-f', '-s', '-w', '--skip-fields', '--skip-chars', '--check-chars')
SWARM_ROOT_RE = X(r'SWARM_ROOT=(' + SAFE + ')')
DOCKER_INNER = (PIPE_OK - {'rg'}) | {'ls', 'php -l', 'git status', 'git log', 'git diff', 'git show', 'git rev-parse'}
MUTATIONS = {('git', 'push'), ('git', 'remote'), ('gh', 'repo'), ('gh', 'pr')}


def uniq_bad(a):
    """uniq's 2nd operand is an OUTPUT file; BSD getopt stops at the 1st operand so `uniq a -out` writes `-out`."""
    ops = [k for k, w in enumerate(a) if (not w.startswith('-') or w == '-') and not (k and a[k - 1] in UNIQ_VAL)]
    return '--' in a or (bool(ops) and ops[0] < len(a) - 1)  # nothing may follow the input operand


def npm_exec_bad(cmd, args):
    """`-c`/`--call` (shell string), `-y`/`-p`/`--package` (fetch+run); npx reads flags to its 1st operand."""
    span = args[:args.index('--')] if '--' in args else args
    if cmd == 'npx':
        span = span[:next((k for k, w in enumerate(span) if not w.startswith('-')), len(span))]
    return any((w[2:].split('=')[0] and any(f.startswith(w[2:].split('=')[0]) for f in ('call', 'yes', 'package'))
                if w.startswith('--') else re.fullmatch(r'-[A-Za-z]*[cyp][A-Za-z]*(=.*)?', w)) for w in span)


def interp_bad(cmd, args):
    """A script file: no inline code (`-c`, `-cCODE`, `--eval=CODE`, `-pe`), no preload, no REPL, no stdin script."""
    ini = [w[2:] for w in args if w.startswith('-d') and w != '-d'] + [b for a, b in zip(args, args[1:]) if a == '-d']
    inline = [f for f in INTERP_DENY[cmd] for w in args if w.split('=')[0] == f or (len(f) == 2 and (
        w.startswith(f) or (re.fullmatch(r'-[A-Za-z]+', w) and f[1] in w)))]
    if inline or any(w == '-' or '/dev/' in w for w in args) or (
            cmd == 'php' and any(v.split('=')[0].strip() in PHP_INI_DENY for v in ini)):
        return True
    opts, k = [], 0
    while k < len(args) and args[k].startswith('-') and args[k] not in INTERP_RUN:
        opts.append(args[k])
        k += 2 if args[k] in INTERP_VAL[cmd] else 1
    repl = any(w.split('=')[0] in INTERP_REPL[cmd] or (re.fullmatch(r'-[A-Za-z]+', w) and any(
        f[1] in w for f in INTERP_REPL[cmd] if len(f) == 2)) for w in opts)
    return repl or (k >= len(args) and not INFO & set(opts))


ARG_DENY = {  # options that write a file, run a program or leak the environment although the command only reads
    'find': lambda a: FIND_DENY & set(a),  # sort: `-o`/`-T` also inside a cluster, GNU long abbreviations too
    'sort': lambda a: any(re.match(r'-[^-ktS]*[oT]', w) or (w.startswith('--') and len(w) > 2 and any(
        d.startswith(w[2:].split('=')[0]) for d in ('output', 'compress-program', 'temporary-directory')))
        for w in a[:a.index('--') if '--' in a else len(a)]),
    'uniq': uniq_bad,
    'make': lambda a: any(w == '-' or '/dev/' in w or w.endswith('=-') or re.fullmatch(r'-[A-Za-z]*f-', w) for w in a),
    'npx': lambda a: npm_exec_bad('npx', a),
    'npm': lambda a: npm_exec_bad('npm', a),
    'jq': lambda a: any(w in ('-i', '--in-place', '-f', '--from-file') or re.search(r'(?<![\w.$"])env(?![\w"])', w)
                        for w in a),  # `env`/`$ENV` dump the process environment
    'rg': lambda a: any(w.split('=')[0] in ('--pre', '--pre-glob', '--hostname-bin') for w in a),
    'git': lambda a: any(w.split('=')[0] == '--output' for w in a),
}


def split_commands(cmd, writer):
    """(parts without their redirections, redirected?, piped flags) — or None when the syntax is refused."""
    if BANNED_ALL & set(cmd) or (not writer and set('|&>()') & set(cmd)):
        return None
    parts, piped, cur, quote, i, redirected = [], [False], '', None, 0, False
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
            piped.append(c == '|')
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
            comps = [p.lower() for p in m.group(3).split('/') if p not in ('', '.')]  # case-insensitive FS
            if PROTECTED_ANY & set(comps) or (comps[:1] == ['.claude'] and comps[1:2] != ['agent-memory']):
                return None
            redirected, i = True, m.end()
            continue
        cur, i = cur + c, i + 1
    return None if quote else (parts + [cur], redirected, piped)


def allowlisted(argv, allow):
    """argv[0] (or argv[0:2]) equals an entry; plugin scripts only by plugin path (`scripts/mem-` = the family)."""
    rel = argv[0][len(ROOT) + 1:] if argv[0].startswith(ROOT + '/') and '..' not in argv[0].split('/') else ''
    mem = rel.startswith('scripts/mem-') and rel.endswith('.sh') and rel.count('/') == 1 \
        and os.path.isfile(os.path.join(ROOT, rel))
    return any((rel == e or (e == 'scripts/mem-' and mem)) if e.startswith('scripts/')
               else e.split(' ') == argv[:len(e.split(' '))] for e in allow)


def fits(args, sp, sh):
    """`args` match one positive shape (see `shapes._doc` in bash-allowlist.json)."""
    rx = lambda r: re.compile(sh['patterns'][r[1:]] if r.startswith('@') else r)
    flags = sh['flagsets'][sp['flags'][1:]] if str(sp.get('flags')).startswith('@') else sp.get('flags', {})
    pos, seen, it = [], [], iter(args)
    for w in it:
        name, eq, val = w.partition('=')
        if not w.startswith('-'):
            pos.append(w)
        elif flags != '*' and (name not in flags or (flags[name] is None and eq) or (flags[name] is not None and (
                not rx(flags[name]).fullmatch(v := val if eq else next(it, '-')) or v.startswith('-')))):
            return False
        else:
            seen.append(name)
    p, (lo, hi) = sp.get('pos', []), sp.get('n', [0, 0])
    ok = [bool(rx(r).fullmatch(w)) for r, w in zip(p, pos)] + [len(p) == len(pos)] if isinstance(p, list) \
        else [lo <= len(pos) <= hi] + [bool(rx(p).fullmatch(w)) for w in pos]
    return all(ok) and all(seen.count(f) == 1 for f in sp.get('need', []))


def table_ok(argv, table, sh):
    """The LONGEST prefix of argv (3, then 2 words) found in `table` decides; None when no entry applies."""
    for k in (3, 2):
        alts = table.get(' '.join(argv[:k])) if len(argv) >= k else None
        if alts is not None:
            return any(fits(argv[k:], sp, sh) for sp in (alts if isinstance(alts, list) else [alts]))
    return None


def shape_ok(argv, ro, sh):
    """Per-command rules an exact allowlist prefix cannot express."""
    cmd, args, ro_fit = argv[0], argv[1:], table_ok(argv, sh['read_only'], sh) if ro else True
    return not ((cmd in ARG_DENY and ARG_DENY[cmd](args)) or table_ok(argv, sh['every'], sh) is False or ro_fit is False
                or (ro_fit is None and cmd in sh['read_only_strict']) or (cmd in INTERP_REPL and interp_bad(cmd, args)))


def containers(cwd):
    """Container names of the nearest `.swarm/docker-containers`, walking up from cwd."""
    d = os.path.abspath(cwd or os.getcwd())
    while not os.path.isfile(os.path.join(d, '.swarm', 'docker-containers')) and d != os.path.dirname(d):
        d = os.path.dirname(d)
    f = os.path.join(d, '.swarm', 'docker-containers')
    return {l.strip() for l in open(f) if l.strip() and not l.lstrip().startswith('#')} if os.path.isfile(f) else set()


def cd_ok(argv, ro, cwd):
    """Absolute, no `..`: a writer's is a LINKED worktree root; a read-only role's the git toplevel holding its cwd."""
    t = argv[1] if len(argv) == 2 and argv[1].startswith('/') and '..' not in argv[1].split('/') else None
    if t is None or not ro:
        return t is not None and os.path.isfile(os.path.join(t, '.git'))
    here, top = os.path.realpath(cwd or '/nonexistent'), os.path.realpath(t)
    return bool(cwd) and os.path.exists(os.path.join(top, '.git')) and (here + '/').startswith(top.rstrip('/') + '/')


def command_ok(argv, allow, ro, cwd, sh):
    if argv[:1] == ['cd'] and not cd_ok(argv, ro, cwd):
        return False
    if argv[:2] == ['docker', 'exec']:  # writers only; no flags; listed container; read-only inner; no nesting
        inner = [e for e in allow if e in DOCKER_INNER]
        return (not ro and 'docker exec' in allow and len(argv) > 3 and bool(CONTAINER.fullmatch(argv[2]))
                and argv[2] in containers(cwd) and command_ok(argv[3:], inner, True, cwd, sh))
    return bool(argv) and allowlisted(argv, allow) and shape_ok(argv, ro, sh)


def swarm_root_ok(word, cwd):
    """`SWARM_ROOT=<dir>` prefix: a `.swarm` dir, no `..`, that already exists (from cwd if relative)."""
    m = SWARM_ROOT_RE.fullmatch(word)
    parts = m.group(1).rstrip('/').split('/') if m else []
    return bool(parts) and parts[-1] == '.swarm' and '..' not in parts and os.path.isdir(
        os.path.join(os.path.abspath(cwd or os.getcwd()), m.group(1)))


def verdict(data):  # None = allow, else the deny reason
    agent, cmd = data['agent_type'], data['tool_input']['command'].strip(' \t')
    if re.fullmatch(SAFE, ROOT):
        cmd = cmd.replace('${CLAUDE_PLUGIN_ROOT}', ROOT).replace('$CLAUDE_PLUGIN_ROOT', ROOT)
    cfg = json.load(open(os.path.join(HERE, 'bash-allowlist.json')))
    allow, writer = cfg.get('agents', {}).get(agent, cfg['default']), agent in cfg['file_writers']
    split = split_commands(cmd, writer)
    if split is None:
        return 'shell syntax outside the %s policy: %s' % ('writer' if writer else 'read-only', cmd)
    cwd = data.get('cwd') if isinstance(data.get('cwd'), str) else None
    argvs = [a[1:] if a and swarm_root_ok(a[0], cwd) else a for a in map(shlex.split, split[0])]
    if any(tuple(a[:2]) in MUTATIONS for a in argvs) and (len(argvs) > 1 or split[1]):
        return 'a push/remote/gh mutation must run alone (no chaining, no redirection): %s' % cmd
    for argv, fed in zip(argvs, split[2]):
        if fed and argv[:1] and argv[0] not in PIPE_OK:
            return '`%s` may not read a pipe (only text filters do): %s' % (argv[0], cmd)
        if not command_ok(argv, allow, not writer, cwd, cfg['shapes']):
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
