"""tests/swarmtest.py — shared helpers for the python tests (stdlib only, no pip).

Every test file imports this, builds a `Suite`, calls `check(...)` and ends with `suite.done()`
(exit 1 if anything failed). Randomized tests use `rng()` — seeded, so a failure reproduces;
override the seed with SWARM_TEST_SEED to explore further.
"""
import concurrent.futures
import glob
import json
import os
import random
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUARD = os.environ.get('SWARM_GUARD') or os.path.join(ROOT, 'hooks', 'bash-guard.py')  # override: mutation checks
VALIDATOR = os.environ.get('SWARM_VALIDATOR') or os.path.join(ROOT, 'hooks', 'validate-output.py')
WORKERS = int(os.environ.get('SWARM_TEST_WORKERS', '12'))


def rng(salt=''):
    seed = os.environ.get('SWARM_TEST_SEED', '20260926')
    return random.Random('%s:%s' % (seed, salt))


class Suite:
    def __init__(self, name):
        self.name, self.run, self.failed = name, 0, 0

    def check(self, ok, msg):
        self.run += 1
        if not ok:
            self.failed += 1
            sys.stderr.write('FAIL: %s\n' % msg)
        return ok

    def done(self):
        print('%s: %d checks, %d failed' % (self.name, self.run, self.failed))
        sys.exit(1 if self.failed else 0)


# ---------- markdown / frontmatter ----------

def read(path):
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def split_frontmatter(text):
    """(dict of raw frontmatter values, body) — the flat `key: value` YAML subset agents use."""
    if not text.startswith('---\n'):
        return None, text
    end = text.find('\n---\n', 4)
    if end < 0:
        return None, text
    front = {}
    for line in text[4:end].split('\n'):
        m = re.match(r'^([A-Za-z][A-Za-z0-9_-]*):\s?(.*)$', line)
        if m:
            front[m.group(1)] = m.group(2).strip()
    return front, text[end + 5:]


def split_tools(value):
    """Top-level comma split: `Agent(a,b), Read` -> ['Agent(a,b)', 'Read']."""
    out, depth, cur = [], 0, ''
    for c in value:
        depth += (c == '(') - (c == ')')
        if c == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += c
    if cur.strip():
        out.append(cur.strip())
    return out


def agent_children(tools):
    for t in tools:
        m = re.match(r'^Agent\((.*)\)$', t)
        if m:
            return [x.strip() for x in m.group(1).split(',') if x.strip()]
    return []


def load_agents():
    agents = {}
    for path in sorted(glob.glob(os.path.join(ROOT, 'agents', '*.md'))):
        text = read(path)
        front, body = split_frontmatter(text)
        tools = split_tools(front.get('tools', '')) if front else []
        agents[os.path.basename(path)[:-3]] = {
            'path': path, 'text': text, 'front': front or {}, 'body': body,
            'tools': tools, 'children': agent_children(tools), 'lines': text.count('\n'),
        }
    return agents


def playbook_files(agent):
    return sorted(glob.glob(os.path.join(ROOT, 'playbooks', agent, '*.md')))


def fenced_blocks(text):
    """[(lang, body)] for every ``` fenced block, list-item indentation removed."""
    out = []
    for m in re.finditer(r'^([ \t]*)```(\w*)[ \t]*\n(.*?)^[ \t]*```', text, re.S | re.M):
        indent, lang, block = len(m.group(1)), m.group(2), m.group(3)
        lines = [ln[indent:] if ln[:indent].strip() == '' else ln for ln in block.split('\n')]
        out.append((lang, '\n'.join(lines).rstrip('\n')))
    return out


# ---------- hooks as black boxes ----------

def _run(argv, payload, env=None):
    p = subprocess.run(argv, input=payload, capture_output=True, text=True, env=env, timeout=30)
    return p.returncode, p.stdout, p.stderr


def guard(agent_type, command, cwd=None):
    """'allow' | 'deny' from hooks/bash-guard.py for one Bash call."""
    payload = {'agent_type': agent_type, 'tool_name': 'Bash', 'tool_input': {'command': command}}
    if cwd:
        payload['cwd'] = cwd
    rc, out, _ = _run([sys.executable, GUARD], json.dumps(payload))
    return 'deny' if '"deny"' in out else ('allow' if rc == 0 else 'error:%d' % rc)


def guard_raw(payload_text):
    return _run([sys.executable, GUARD], payload_text)


def validate(agent_type, message, swarm_root, extra=None):
    """'accept' | 'block' | 'system' — hooks/validate-output.py on one SubagentStop payload."""
    payload = {'agent_type': agent_type, 'hook_event_name': 'SubagentStop', 'last_assistant_message': message}
    payload.update(extra or {})
    env = dict(os.environ, SWARM_ROOT=swarm_root)
    rc, out, _ = _run([sys.executable, VALIDATOR], json.dumps(payload), env=env)
    if rc != 0:
        return 'error:%d' % rc
    if '"decision": "block"' in out:
        return 'block'
    if 'systemMessage' in out:
        return 'system'
    return 'accept' if not out.strip() else 'unknown:' + out.strip()[:80]


def parallel(fn, items):
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as ex:
        return list(ex.map(fn, items))


def sh(argv, env=None, cwd=None, stdin=None):
    p = subprocess.run(argv, capture_output=True, text=True, env=env, cwd=cwd, input=stdin, timeout=60)
    return p.returncode, p.stdout, p.stderr
