#!/usr/bin/env python3
"""tests/test_mem_paths_fuzz.py — the memory scripts are the boundary for every argument that becomes a path.

bash-guard.py lets `scripts/mem-*.sh` run with any argument, so the scripts validate on their own
(scripts/lib/validate.sh). Seeded random payloads — traversal (`..`, `/`, absolute paths), names outside
`^[a-z0-9][a-z0-9-]{0,63}$`, runs that are neither a uuid nor `adhoc`, sed programs in `--line`, arithmetic
injection in `--days`/`--keep`, embedded newlines — must exit non-zero AND leave every file outside `.swarm/`
untouched (no file created, changed or removed, no sentinel written). A positive control proves the harness
sees writes: valid arguments do write, inside `.swarm/` only. SWARM_SCRIPTS points it at another scripts dir.
"""
import os
import shutil
import string
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swarmtest import ROOT, Suite, rng, sh  # noqa: E402

S = Suite('mem-paths-fuzz')
R = rng('mem-paths')
N = int(os.environ.get('SWARM_FUZZ_N', '60'))
SCRIPTS = os.environ.get('SWARM_SCRIPTS') or os.path.join(ROOT, 'scripts')
BOX = os.path.realpath(tempfile.mkdtemp(prefix='swarm-mem-paths.'))
REPO = os.path.join(BOX, 'repo')
SR = os.path.join(REPO, '.swarm')
os.makedirs(os.path.join(SR, 'findings'))
os.makedirs(os.path.join(REPO, 'src'))
with open(os.path.join(REPO, 'src', 'A.php'), 'w') as fh:
    fh.write('<?php\n' + ''.join('// line %d\n' % n for n in range(2, 40)))
with open(os.path.join(SR, 'findings', 'old.md'), 'w') as fh:  # something for prune/resolve to walk
    fh.write('- [key:old|X|src/A.php:2] [sha:00000000] [status:open] [run:adhoc] X · src/A.php:2 · t → f\n')
ENV = dict(os.environ, SWARM_ROOT=SR)
UUID = 'f3b1c2d4-0a1b-4c2d-8e3f-0123456789ab'
SENTINEL = os.path.join(BOX, 'PWNED')


def word(lo=3, hi=8):
    return ''.join(R.choice(string.ascii_lowercase + string.digits) for _ in range(R.randint(lo, hi)))


def outside():
    """{path: (size, mtime)} of every file under BOX that is not inside .swarm/."""
    snap = {}
    for d, dirs, files in os.walk(BOX):
        dirs[:] = [x for x in dirs if os.path.join(d, x) != SR]
        for f in files + [x for x in dirs]:
            p = os.path.join(d, f)
            st = os.lstat(p)
            snap[p] = (st.st_size, st.st_mtime_ns)
    return snap


def bad_name():
    """A name that must be refused as an agent / recipient / run: traversal, separators, case, length."""
    w = word()
    if R.random() < 0.5:  # half of them climb far enough to leave .swarm/ from findings/, run/<run>/ or mailbox/
        return '../' * R.randint(2, 5) + w
    return R.choice([
        '../' * R.randint(1, 6) + w, '%s/../../%s' % (w, w), '/' + w, os.path.join(BOX, w), BOX + '/' + w,
        '..', '.', './' + w, w + '/' + w, w.upper(), '-' + w, w + ' ' + w, w + '\n' + w, w + '.md', '.' + w,
        'a' * 65, '', w + '/..', '~/' + w, w + '_' + w, '%s\\..\\%s' % (w, w),
    ])


def bad_run():
    if R.random() < 0.4:
        return '../' * R.randint(2, 4) + word()
    return R.choice([bad_name(), 'fuzz', 'r-1', UUID.upper(), UUID + '/..', UUID[:-1], '../' + UUID, 'adhoc/../..',
                     'ADHOC', 'adhoc\n'])


def bad_line():
    return R.choice(['1w %s' % SENTINEL, '1w%s' % SENTINEL, '1,$w %s' % SENTINEL, '1e touch %s' % SENTINEL,
                     '0', '-1', '1p;w ' + SENTINEL, '$', '1 ', 'x', '1\n2', '99999999999', ''])


def bad_count():
    return R.choice(['now[$(touch %s)]' % SENTINEL, 'keep[$(touch %s)]' % SENTINEL, 'x', '-1', '1e3', '1 + 1', '', '1\n'])


def bad_file():
    return R.choice(['/etc/passwd', '../' * R.randint(1, 5) + 'x', 'src/../../x', '..', os.path.join(BOX, 'x'), 'a\nb'])


MEMF, MANI, CUR = (os.path.join(SCRIPTS, s) for s in ('mem-files.sh', 'mem-manifest.sh', 'mem-curate.sh'))


def finding(agent='arch-a', run='adhoc', line='3', file='src/A.php', text='t'):
    return [MEMF, 'write', 'finding', '--agent', agent, '--tag', 'ARCH', '--file', file, '--line', line,
            '--run', run, '--text', text, '--fix', 'f']


def mailbox(to='options-generator', run='adhoc', text='hi'):
    return [MEMF, 'write', 'mailbox', '--to', to, '--from', 'orchestrator', '--run', run, '--text', text]


def register(run='adhoc', agent='arch-a'):
    return [MANI, 'register', '--run', run, '--agent', agent, '--domain', 'analysis', '--area', '.', '--owner', 'x']


def summary(run='adhoc', line='- ok'):
    return [MANI, 'summary', '--run', run, '--line', line]


# ---------- positive control: valid arguments write, and only inside .swarm/ ----------
before = outside()
for argv in (finding(), finding(run=UUID, agent='verifier-sis'), mailbox(), mailbox(run=UUID), register(), register(run=UUID),
             summary(), summary(run=UUID), [CUR, 'prune', '--days', '30'], [MANI, 'gc', '--keep', '10']):
    rc, out, err = sh(argv, env=ENV, cwd=REPO)
    S.check(rc == 0, 'valid call accepted: %s -> rc=%s %s' % (argv[1:4], rc, err.strip()[:120]))
S.check(os.path.isfile(os.path.join(SR, 'findings', 'arch-a.md')), 'control: the finding landed in .swarm/findings/')
S.check(os.path.isfile(os.path.join(SR, 'run', UUID, 'mailbox', 'options-generator.md')), 'control: mailbox landed under run/<uuid>/')
S.check(outside() == before, 'control: valid calls touch nothing outside .swarm/')

# ---------- hostile arguments: refused, nothing written outside .swarm/ ----------
MAKERS = [
    ('finding --agent', lambda: finding(agent=bad_name())), ('finding --run', lambda: finding(run=bad_run())),
    ('finding --line', lambda: finding(line=bad_line())), ('finding --file', lambda: finding(file=bad_file())),
    ('finding --text', lambda: finding(text='a\n- [key:forged] [status:open]')),
    ('mailbox --to', lambda: mailbox(to=bad_name())), ('mailbox --run', lambda: mailbox(run=bad_run())),
    ('mailbox --text', lambda: mailbox(text='a\nb')),
    ('register --run', lambda: register(run=bad_run())), ('register --agent', lambda: register(agent=bad_name())),
    ('summary --run', lambda: summary(run=bad_run())), ('summary --line', lambda: summary(line='a\nb')),
    ('prune --days', lambda: [CUR, 'prune', '--days', bad_count()]), ('gc --keep', lambda: [MANI, 'gc', '--keep', bad_count()]),
]
for kind, make in MAKERS:
    for _ in range(max(6, N // 3)):
        argv = make()
        if '' in argv[1:] and kind != 'prune --days' and kind != 'gc --keep':
            continue  # an empty required value is the existing "missing arg" path, covered elsewhere
        before = outside()
        rc, out, err = sh(argv, env=ENV, cwd=REPO)
        after = outside()
        S.check(rc != 0, '%s refused: %r -> rc=%s out=%r' % (kind, argv[-1] if kind.endswith(('days', 'keep')) else argv, rc, out.strip()))
        S.check(after == before, '%s wrote outside .swarm/: %r -> %s' % (kind, argv, sorted(set(after) ^ set(before))[:3]))
        S.check(not os.path.exists(SENTINEL), '%s ran injected code: %r' % (kind, argv))

shutil.rmtree(BOX, ignore_errors=True)
S.done()
