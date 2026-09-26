#!/usr/bin/env python3
"""tests/test_validate_output_fuzz.py — hooks/validate-output.py against generated stops.

Messages come from a seeded grammar that knows, by construction, whether each one honours the
evidence contract (line 1 verdict · line 2 `evidence: files=N cmds=M turns=k/max` · then finding
lines `TAG · file:line · problem → fix`, `- ` lines ≤120 chars, or blanks). Invariants:
  valid (turns<max)           -> accepted silently
  valid with turns>=max        -> accepted with a systemMessage (BLOCKED maxTurns), never blocked
  any single contract breach   -> blocked on the first offence
  same breach twice, same agent, same run -> accepted as BLOCKED (systemMessage), never a loop
  non-swarm agent / stop_hook_active -> no opinion, whatever the text
  WAITING n + `pending:` with exactly n distinct children -> accepted (needs a .swarm/ to count in)
"""
import os
import shutil
import string
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swarmtest import Suite, parallel, rng, validate  # noqa: E402

S = Suite('validate-output-fuzz')
R = rng('validate')
N = int(os.environ.get('SWARM_FUZZ_N', '60'))
TMP = tempfile.mkdtemp(prefix='swarm-vo-fuzz.')
AGENTS = ['swarm:architecture-auditor', 'swarm:planner', 'swarm:implementer', 'swarm:orchestrator', 'swarm:refuter']
TAGS = ['ARCH', 'SEC', 'PERF', 'DEFECT', 'RULES', 'P1-X', 'VULN_2']


def words(lo, hi):
    return ' '.join(''.join(R.choice(string.ascii_lowercase) for _ in range(R.randint(2, 9)))
                    for _ in range(R.randint(lo, hi)))


def verdict():
    return R.choice(['OK', 'DONE', 'KO ' + words(1, 6), 'BLOCKED ' + words(1, 6)])


def evidence(files=None, turns=None, maxt=None):
    maxt = maxt or R.randint(2, 40)
    turns = R.randint(0, maxt - 1) if turns is None else turns
    files = R.randint(1, 30) if files is None else files
    sp = lambda: R.choice(['', ' ', '  '])  # the hook tolerates spaces around = and /
    return 'evidence:%sfiles%s=%s%d cmds=%s%d turns=%d%s/%s%d' % (
        R.choice([' ', '  ']), sp(), sp(), files, sp(), R.randint(0, 50), turns, sp(), sp(), maxt)


def finding():
    return '%s · src/%s.php:%d · %s → %s' % (R.choice(TAGS), words(1, 1), R.randint(1, 999), words(1, 4), words(1, 3))


def body_line():
    return R.choice([finding, lambda: '- ' + words(1, 8)[:110], lambda: ''])()


def valid_message(files=None, turns=None, maxt=None):
    lines = [verdict(), evidence(files, turns, maxt)] + [body_line() for _ in range(R.randint(0, 6))]
    if lines[0] == 'OK' and files == 0:
        lines[0] = 'DONE'
    return '\n'.join(lines)


BREACHES = {
    'verdict lower-case': lambda m: m.replace(m.split('\n')[0], m.split('\n')[0].lower() + ' x', 1),
    'bare KO': lambda m: '\n'.join(['KO'] + m.split('\n')[1:]),
    'bare BLOCKED': lambda m: '\n'.join(['BLOCKED'] + m.split('\n')[1:]),
    'prose before verdict': lambda m: 'Here is my report:\n' + m,
    'no evidence line': lambda m: '\n'.join(m.split('\n')[:1] + m.split('\n')[2:]),
    'malformed evidence': lambda m: '\n'.join(m.split('\n')[:1] + ['evidence: files=%s cmds=1' % R.randint(0, 9)] + m.split('\n')[2:]),
    'narration line': lambda m: m + '\n' + ('I looked at the code and I think that ' + words(30, 40))[:400],
    'long dash narration': lambda m: m + '\n- ' + words(40, 50),
    'OK without files': lambda m: '\n'.join(['OK', evidence(files=0)] + m.split('\n')[2:]),
}

cases = []  # (agent, message, swarm_root, extra, expected, why)
for i in range(N):
    agent = R.choice(AGENTS)
    fresh = os.path.join(TMP, 'none-%d' % i, '.swarm')  # never created: no retry counter survives
    cases.append((agent, valid_message(), fresh, None, 'accept', 'valid stop'))
    maxt = R.randint(2, 30)
    cases.append((agent, valid_message(turns=R.randint(maxt, maxt + 5), maxt=maxt), fresh, None, 'system', 'turns>=max'))
    name, breach = R.choice(sorted(BREACHES.items()))
    cases.append((agent, breach(valid_message()), fresh, None, 'block', 'breach: ' + name))
    junk = R.choice([breach(valid_message()), words(5, 40), ''])
    cases.append(('general-purpose', junk, fresh, None, 'accept', 'non-swarm agent'))
    cases.append((agent, junk, fresh, {'stop_hook_active': True}, 'accept', 'stop_hook_active'))

    # WAITING: counted under a real .swarm/
    root = os.path.join(TMP, 'w-%d' % i, '.swarm')
    os.makedirs(root)
    n = R.randint(1, 4)
    kids = R.sample(['test-writer', 'implementer', 'research-analyst', 'feasibility-spiker', 'doc-writer'], n)
    cases.append((agent, 'WAITING %d\npending: %s' % (n, ', '.join(kids)), root, {'agent_id': 'a%d' % i}, 'accept', 'WAITING n'))
    bad = R.choice(['WAITING %d\npending: %s' % (n + 1, ', '.join(kids)), 'WAITING 0\npending: x',
                    'WAITING %d' % n, 'WAITING %d\npending: %s' % (n, ', '.join([kids[0]] * n) if n > 1 else 'Bad Name')])
    cases.append((agent, bad, root, {'agent_id': 'b%d' % i}, 'block', 'malformed WAITING'))

results = parallel(lambda c: validate(c[0], c[1], c[2], c[3]), cases)
for (agent, msg, _, extra, want, why), got in zip(cases, results):
    S.check(got == want, '%s: %s -> %s, expected %s: %r' % (why, agent, got, want, msg[:160]))

# a repeated breach is converted, never looped: first block, then BLOCKED via systemMessage
for i in range(max(4, N // 10)):
    root = os.path.join(TMP, 'r-%d' % i, '.swarm')
    os.makedirs(root)
    name, breach = R.choice(sorted(BREACHES.items()))
    msg, agent = breach(valid_message()), R.choice(AGENTS)
    first, second = validate(agent, msg, root), validate(agent, msg, root)
    S.check((first, second) == ('block', 'system'), 'repeat of %s: got %s then %s' % (name, first, second))

# WAITING cannot stall forever: past the per-instance cap it is refused; a verdict resets the count
root = os.path.join(TMP, 'cap', '.swarm')
os.makedirs(root)
seq = [validate('swarm:discovery-orchestrator', 'WAITING 1\npending: research-analyst', root, {'agent_id': 'cap1'})
       for _ in range(12)]
cap = seq.index('block') if 'block' in seq else -1
S.check(1 <= cap <= 10 and all(s == 'accept' for s in seq[:cap]), 'WAITING is capped per instance (sequence %s)' % seq)
S.check(validate('swarm:discovery-orchestrator', 'WAITING 1\npending: research-analyst', root, {'agent_id': 'cap2'}) == 'accept',
        'the WAITING cap is per agent instance, not per agent type')
validate('swarm:discovery-orchestrator', valid_message(), root, {'agent_id': 'cap1'})
S.check(validate('swarm:discovery-orchestrator', 'WAITING 1\npending: research-analyst', root, {'agent_id': 'cap1'}) == 'accept',
        'a verdict resets the WAITING cap of that instance')
S.check(validate('swarm:planner', 'WAITING 1\npending: x', os.path.join(TMP, 'absent', '.swarm')) == 'block',
        'WAITING without a writable .swarm/ is refused (an uncounted WAITING would be unlimited)')

shutil.rmtree(TMP, ignore_errors=True)
S.done()
