#!/usr/bin/env python3
"""tests/test_scripts_fuzz.py — deterministic scripts under seeded random inputs (invariants, not examples).

  model-resolve.sh  random tier configs + unavailable sets (bare / fresh / expired marks):
                    every tier resolves to its FIRST live candidate, else `inherit`; never to a
                    candidate of another tier's list (judgement is never downgraded); --escalate
                    never goes down; --avoid never returns the avoided id (except `inherit`).
  mem-files.sh +    random findings (hostile text included) round-trip: one line per distinct
  swarm-findings.sh key, `dup` on repeats, text verbatim; filters return exactly the matching open
                    findings; any filter outside [A-Za-z0-9_-] exits 64.
  swarm-init.sh     random pre-existing .gitignore: every entry exactly once, user lines kept in
                    order, a second run changes nothing.
  req-check.sh      random requirements: ok/exit/missing_required match the oracle exactly.
"""
import json
import os
import shutil
import string
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swarmtest import ROOT, Suite, parallel, rng, sh  # noqa: E402

S = Suite('scripts-fuzz')
R = rng('scripts')
N = int(os.environ.get('SWARM_FUZZ_N', '60'))
TMP = tempfile.mkdtemp(prefix='swarm-scripts-fuzz.')
SCRIPTS = os.environ.get('SWARM_SCRIPTS') or os.path.join(ROOT, 'scripts')  # override: mutation checks
TIERS = ('judgement', 'standard', 'mechanical')
PLUGIN_MODELS = json.load(open(os.path.join(ROOT, 'models.json')))


def word(lo=3, hi=8):
    return ''.join(R.choice(string.ascii_lowercase) for _ in range(R.randint(lo, hi)))


# ---------- model-resolve.sh ----------
def mr_config(i):
    root = os.path.join(TMP, 'mr%d' % i, '.swarm')
    os.makedirs(root)
    tiers = dict(PLUGIN_MODELS['tiers'])
    override = {}
    for t in TIERS:
        if R.random() < 0.7:
            cands = ['%s-%s' % (t[:3], word(2, 4)) for _ in range(R.randint(1, 4))]
            if R.random() < 0.3:  # share an id with another tier: resolution must still stay in-tier
                cands.insert(R.randint(0, len(cands)), R.choice(sum(tiers.values(), [])))
            if R.random() < 0.5:
                cands.append('inherit')
            override[t] = list(dict.fromkeys(cands))
    tiers.update(override)
    if override or R.random() < 0.5:
        with open(os.path.join(root, 'models.json'), 'w') as fh:
            json.dump({'tiers': override}, fh)
    pool = sorted({c for v in tiers.values() for c in v if c != 'inherit'})
    live, lines, now = set(), [], int(time.time())
    for c in R.sample(pool, R.randint(0, len(pool))):
        kind = R.choice(['bare', 'fresh', 'expired', 'comment'])
        if kind == 'bare':
            lines.append(c)
            live.add(c)
        elif kind == 'fresh':
            lines.append('%s %d run-%s' % (c, now - R.randint(0, 3000), word()))
            live.add(c)
        elif kind == 'expired':
            lines.append('%s %d run-%s' % (c, now - 86400 - R.randint(1, 99999), word()))
        else:
            lines.append('# %s' % c)
    with open(os.path.join(root, 'models.unavailable'), 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
    return root, tiers, live


def expected(tiers, live, t):
    return next((c for c in tiers[t] if c == 'inherit' or c not in live), 'inherit')


def mr(args):
    return sh([os.path.join(SCRIPTS, 'model-resolve.sh')] + args, env=dict(os.environ, SWARM_MODEL_UNAVAILABLE_TTL='86400'))


configs = [mr_config(i) for i in range(N)]
calls, avoids = [], []
for root, tiers, live in configs:
    calls.append(['--show', '--swarm-root', root])
    for t in TIERS:
        calls.append(['--escalate', t, '--swarm-root', root])
    avoid = R.choice(tiers['judgement'])
    avoids.append(avoid)
    calls.append(['judgement', '--avoid', avoid, '--swarm-root', root])
outs = iter(parallel(mr, calls))
for (root, tiers, live), avoid in zip(configs, avoids):
    rc, out, err = next(outs)
    got = {ln.split()[0]: ln.split()[1] for ln in out.strip().split('\n') if ln.strip()}
    for t in TIERS:
        want = expected(tiers, live, t)
        S.check(got.get(t) == want, '%s resolves to %s, expected %s (cands=%s live-unavailable=%s)' % (t, got.get(t), want, tiers[t], sorted(live)))
        S.check(got.get(t) in tiers[t] + ['inherit'], '%s never resolves outside its own list: %s' % (t, got.get(t)))
    for t in TIERS:
        rc, out, err = next(outs)
        up = out.strip()
        S.check(rc == 0 and up in TIERS and TIERS.index(up) <= TIERS.index(t), '--escalate %s -> %r never goes down' % (t, up))
        S.check(t != 'judgement' or up == 'judgement', 'judgement escalates to itself')
    rc, out, err = next(outs)
    pick = out.strip()
    S.check(rc == 0 and pick in tiers['judgement'] + ['inherit'], '--avoid keeps judgement in-tier: %r' % pick)
    S.check(pick != avoid or pick == 'inherit', '--avoid %s never returns the avoided id (got %s)' % (avoid, pick))

# --mark-unavailable then resolve: the marked id is never the answer again
for i in range(N // 3):
    root, tiers, live = configs[i]
    t = R.choice(TIERS)
    first = expected(tiers, live, t)
    if first == 'inherit':
        continue
    rc, out, _ = mr(['--mark-unavailable', first, '--swarm-root', root])
    rc2, out2, _ = mr([t, '--swarm-root', root])
    S.check(rc == 0 and out2.strip() == expected(tiers, live | {first}, t), 'after marking %s, %s -> %s' % (first, t, out2.strip()))

# ---------- mem-files.sh + swarm-findings.sh ----------
repo = os.path.join(TMP, 'repo')
os.makedirs(os.path.join(repo, 'src'))
for f in ('A', 'B', 'C'):
    with open(os.path.join(repo, 'src', f + '.php'), 'w') as fh:
        fh.write('\n'.join('line %d' % n for n in range(1, 40)) + '\n')
SR = os.path.join(repo, '.swarm')
os.makedirs(SR)
ENV = dict(os.environ, SWARM_ROOT=SR)
HOSTILE = ['"q"', "'s'", '$HOME', '$(id)', '`id`', ';', '|', '&&', '→', 'ñ', '\\', '*', '#', '%s', '<x>']
MEMF = os.path.join(SCRIPTS, 'mem-files.sh')
agents_pool, tags_pool = ['arch-a', 'sec-b', 'perf-c'], ['ARCH', 'SEC', 'PERF_2']
records, keys = [], {}
for _ in range(N):
    agent, tag = R.choice(agents_pool), R.choice(tags_pool)
    f, line = 'src/%s.php' % R.choice('ABC'), R.randint(1, 30)
    text = ' '.join(R.choice([word(), R.choice(HOSTILE)]) for _ in range(R.randint(1, 6)))
    records.append((agent, tag, f, line, text))
for agent, tag, f, line, text in records:  # sequential: the dup verdict depends on order
    rc, out, err = sh([MEMF, 'write', 'finding', '--agent', agent, '--tag', tag, '--file', f, '--line', str(line),
                       '--run', 'adhoc', '--text', text, '--fix', 'fix-it'], env=ENV, cwd=repo)
    key = (agent, tag, f, line)
    S.check(rc == 0 and out.strip() == ('dup' if key in keys else 'written'), 'write %s -> rc=%s %r' % (key, rc, out.strip()))
    keys.setdefault(key, text)
for agent in agents_pool:
    path = os.path.join(SR, 'findings', agent + '.md')
    lines = open(path).read().splitlines() if os.path.exists(path) else []
    mine = {k: v for k, v in keys.items() if k[0] == agent}
    S.check(len(lines) == len(mine), '%s: one line per distinct key (%d lines, %d keys)' % (agent, len(lines), len(mine)))
    S.check(all(ln.startswith('- [key:') for ln in lines), '%s: every line carries its metadata header' % agent)
    for (a, tag, f, line), text in mine.items():
        S.check(any(('%s · %s:%d · %s → fix-it' % (tag, f, line, text)) in ln for ln in lines), '%s: text kept verbatim: %r' % (a, text))
FIND = os.path.join(SCRIPTS, 'swarm-findings.sh')
FIND_CAP = 50  # scripts/swarm-findings.sh: CAP = 50 — output is capped even when more findings match
for flt in agents_pool + tags_pool:
    rc, out, _ = sh(['bash', FIND, flt], env=ENV)
    want = [k for k in keys if flt in (k[0], k[1])]
    got = [ln for ln in out.splitlines() if ' · src/' in ln]
    expect_n = min(len(want), FIND_CAP)
    S.check(rc == 0 and len(got) == expect_n, 'swarm-findings %s lists exactly its %d open findings, capped at %d (got %d)'
            % (flt, len(want), FIND_CAP, len(got)))
    if len(want) > FIND_CAP:
        S.check(any('… y %d más' % (len(want) - FIND_CAP) in ln for ln in out.splitlines()),
                'swarm-findings %s: truncation marker names the remaining count' % flt)
for _ in range(N // 3):
    bad = word(1, 3) + R.choice([' ', ';', '$', '`', '|', '/', '.', '*', '(', "'", '"', '\\', '\n', '..']) + word(0, 3)
    rc, out, _ = sh(['bash', FIND, bad], env=ENV)
    S.check(rc == 64, 'swarm-findings rejects filter %r with exit 64 (got %s)' % (bad, rc))

# ---------- swarm-init.sh ----------
ENTRIES = ['.swarm/context-pack.md', '.swarm/index.md', '.swarm/findings/', '.swarm/run/', '.swarm/.lock.d',
           '.swarm/models.unavailable', '.swarm/judgements.jsonl']
for i in range(N // 6):
    d = os.path.join(TMP, 'init%d' % i)
    os.makedirs(d)
    user = [word() + R.choice(['', '/', '.log', '/*.tmp']) for _ in range(R.randint(0, 5))]
    pre = user + R.sample(ENTRIES + ['# swarm'], R.randint(0, 3))
    R.shuffle(pre)
    if pre or R.random() < 0.5:
        with open(os.path.join(d, '.gitignore'), 'w') as fh:
            fh.write(''.join(ln + '\n' for ln in pre))
    env = dict(os.environ, SWARM_ROOT=os.path.join(d, '.swarm'))
    rc1 = sh(['bash', os.path.join(SCRIPTS, 'swarm-init.sh')], env=env, cwd=d)[0]
    after1 = open(os.path.join(d, '.gitignore')).read()
    rc2 = sh(['bash', os.path.join(SCRIPTS, 'swarm-init.sh')], env=env, cwd=d)[0]
    after2 = open(os.path.join(d, '.gitignore')).read()
    lines = after1.splitlines()
    S.check(rc1 == 0 and rc2 == 0, 'swarm-init exits 0 twice')
    S.check(all(lines.count(e) == 1 for e in ENTRIES + ['# swarm']), 'every swarm entry exactly once: %s' % lines)
    S.check([ln for ln in lines if ln in pre and ln not in ENTRIES + ['# swarm']] == [ln for ln in pre if ln not in ENTRIES + ['# swarm']],
            'user .gitignore lines kept, in order')
    S.check(after1 == after2, 'a second swarm-init changes nothing')
    S.check(all(os.path.exists(os.path.join(d, '.swarm', p)) for p in ('findings', 'run', 'memory.json', 'decisions.md')),
            'swarm-init lays out .swarm/')

# ---------- req-check.sh ----------
PRESENT = ['ls', 'sh', 'git', 'python3', 'cat']
req_cases = []
for i in range(N // 2):
    d = os.path.join(TMP, 'req%d' % i)
    os.makedirs(d)
    os_items, project, missing_req = [], [], set()
    for _ in range(R.randint(0, 5)):
        tool = R.choice(PRESENT) if R.random() < 0.5 else 'swarm-fake-' + word()
        required = R.random() < 0.5
        os_items.append({'tool': tool, 'required': required, 'install': {'brew': tool}})
        if required and tool not in PRESENT:
            missing_req.add(tool)
    for _ in range(R.randint(0, 3)):
        name = word() + '.txt'
        if R.random() < 0.5:
            open(os.path.join(d, name), 'w').close()
        required = R.random() < 0.5
        project.append({'file': name, 'required': required})
        if required and not os.path.exists(os.path.join(d, name)):
            missing_req.add(name)
    with open(os.path.join(d, 'req.json'), 'w') as fh:
        json.dump({'os': os_items, 'project': project, 'libs': []}, fh)
    req_cases.append((d, missing_req))
for (d, missing_req), (rc, out, err) in zip(req_cases, parallel(
        lambda c: sh([os.path.join(SCRIPTS, 'req-check.sh'), '--file', os.path.join(c[0], 'req.json'), '--root', c[0]]), req_cases)):
    try:
        rep = json.loads(out)
    except ValueError:
        S.check(False, 'req-check prints one JSON report (got %r)' % out[:120])
        continue
    got = {m.get('tool') for m in rep.get('missing_required', [])}
    S.check(got == missing_req, 'req-check missing_required %s == oracle %s' % (sorted(got), sorted(missing_req)))
    S.check(rep.get('ok') is (not missing_req) and rc == (1 if missing_req else 0), 'req-check ok/exit agree with the oracle (rc=%s)' % rc)

shutil.rmtree(TMP, ignore_errors=True)
S.done()
