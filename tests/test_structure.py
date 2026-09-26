#!/usr/bin/env python3
"""tests/test_structure.py — the plugin's STRUCTURE, never its wording.

Checks: agent frontmatter schema · Agent(...) spawn graph · line budgets per role · no model ids in
agent material · every on-demand path a core file names exists and carries its trigger · no orphan
on-demand file · allowlist <-> agents consistency · commands <-> plugin.json · requirements.json
schema · every documented verdict passes hooks/validate-output.py · every documented ```bash line
and stack-pack command passes hooks/bash-guard.py for the agent that runs it.
Role facts that frontmatter cannot express live in tests/structure.json.
"""
import glob
import json
import os
import re
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swarmtest import (ROOT, Suite, fenced_blocks, guard, load_agents, parallel,  # noqa: E402
                       playbook_files, read, split_frontmatter, validate)

S = Suite('structure')
M = json.load(open(os.path.join(ROOT, 'tests', 'structure.json')))
AGENTS = load_agents()
ROOT_AGENT = M['root']


def rel(path):
    return os.path.relpath(path, ROOT)


def role(name):
    if name == ROOT_AGENT:
        return 'root'
    return 'domain-orchestrator' if AGENTS[name]['children'] else 'leaf'


# ---------- 1. frontmatter schema ----------
allowed_keys = set(M['frontmatter_required']) | set(M['frontmatter_optional'])
for name, a in AGENTS.items():
    f = a['front']
    if not S.check(bool(f), '%s: has a --- frontmatter block' % name):
        continue
    for key in M['frontmatter_required']:
        S.check(bool(f.get(key)), '%s: frontmatter has non-empty %s' % (name, key))
    S.check(set(f) <= allowed_keys, '%s: frontmatter keys outside the schema: %s' % (name, sorted(set(f) - allowed_keys)))
    S.check(f.get('name') == name, '%s: name matches file name (got %r)' % (name, f.get('name')))
    S.check(f.get('model') == 'inherit', '%s: model: inherit (got %r)' % (name, f.get('model')))
    S.check(f.get('tier') in M['tiers'], '%s: tier in %s (got %r)' % (name, M['tiers'], f.get('tier')))
    S.check(f.get('maxTurns', '').isdigit() and int(f['maxTurns']) > 0, '%s: maxTurns is a positive int' % name)
    S.check(f.get('memory') == 'project', '%s: memory: project' % name)
    skills = re.findall(r'[\w:-]+', f.get('skills', ''))
    S.check(all(s in skills for s in M['always_loaded_skills']), '%s: skills preloads %s' % (name, M['always_loaded_skills']))
    S.check(not any(t.startswith('Bash(') for t in a['tools']), '%s: no Bash(...) subcommand syntax in tools' % name)
    S.check(len(a['tools']) == len(set(a['tools'])), '%s: no duplicated tool' % name)
    has_send = 'SendMessage' in a['tools']
    S.check(has_send != (name in M['no_sendmessage']),
            '%s: SendMessage in tools iff not listed in structure.json no_sendmessage' % name)
    S.check(f.get('isolation', 'worktree') == 'worktree', '%s: isolation, when present, is worktree' % name)
    S.check(f.get('background', 'true') == 'true', '%s: background, when present, is true' % name)


# ---------- 2. spawn graph ----------
spawned_by = {n: set() for n in AGENTS}
for name, a in AGENTS.items():
    for child in a['children']:
        if child in M['external_children']:
            continue
        if S.check(child in AGENTS, '%s: spawns %s, which has no agents/%s.md' % (name, child, child)):
            spawned_by[child].add(name)
        S.check(child != ROOT_AGENT, '%s: never spawns the root' % name)

command_spawns = {}
for path in sorted(glob.glob(os.path.join(ROOT, 'commands', '*.md'))):
    for target in re.findall(r'subagent_type:\s*`?swarm:([a-z0-9-]+)', read(path)):
        command_spawns.setdefault(target, []).append(rel(path))
        S.check(target in AGENTS, '%s: launches swarm:%s, which does not exist' % (rel(path), target))
S.check(ROOT_AGENT in command_spawns, 'root agent %s is launched by a command' % ROOT_AGENT)

for name in AGENTS:
    if name == ROOT_AGENT or name in M['unspawned_ok']:
        continue
    S.check(bool(spawned_by[name]) or name in command_spawns, '%s: nobody spawns it (orphan agent)' % name)
for name in M['unspawned_ok']:
    S.check(name in AGENTS and not spawned_by[name], 'structure.json unspawned_ok %s: exists and is really unspawned' % name)

allowed_cycles = {tuple(c) for c in M['allowed_cycles']}


def find_cycles():
    color, stack, found = {}, [], []

    def visit(n):
        color[n] = 1
        stack.append(n)
        for c in AGENTS[n]['children']:
            if c not in AGENTS:
                continue
            if color.get(c) == 1:
                found.append(tuple(stack[stack.index(c):] + [c]))
            elif not color.get(c):
                visit(c)
        stack.pop()
        color[n] = 2
    for n in AGENTS:
        if not color.get(n):
            visit(n)
    return found


for cyc in find_cycles():
    S.check(cyc in allowed_cycles, 'spawn cycle not documented in structure.json: %s' % ' -> '.join(cyc))


# ---------- 3. line budgets ----------
for name in AGENTS:
    budget = M['budgets'][role(name)]
    S.check(AGENTS[name]['lines'] <= budget, '%s (%s): %d lines > budget %d' % (name, role(name), AGENTS[name]['lines'], budget))
for skill in M['always_loaded_skills']:
    path = os.path.join(ROOT, 'skills', skill, 'SKILL.md')
    n = read(path).count('\n')
    S.check(n <= M['budgets']['always-loaded-skill'], '%s: %d lines > budget %d' % (rel(path), n, M['budgets']['always-loaded-skill']))
    b = len(read(path).encode())
    S.check(b <= M['byte_budgets']['always-loaded-skill'], '%s: %d bytes > byte budget %d' % (rel(path), b, M['byte_budgets']['always-loaded-skill']))
for name in AGENTS:
    b = len(read(AGENTS[name]['path']).encode())
    S.check(b <= M['byte_budgets'][role(name)], '%s (%s): %d bytes > byte budget %d' % (name, role(name), b, M['byte_budgets'][role(name)]))


# ---------- 4. no model ids in agent material ----------
model_re = re.compile(r'\b(%s)\b' % '|'.join(M['model_names']), re.I)
material = sorted(glob.glob(os.path.join(ROOT, 'agents', '*.md')) + glob.glob(os.path.join(ROOT, 'skills', '**', '*.md'), recursive=True)
                  + glob.glob(os.path.join(ROOT, 'playbooks', '**', '*.md'), recursive=True))
for path in material:
    hits = [ln.strip()[:80] for ln in read(path).split('\n') if model_re.search(ln)]
    S.check(not hits, '%s names a model id (use a tier; ids live in models.json): %s' % (rel(path), hits[:2]))


# ---------- 5. on-demand material: exists, triggered, not orphaned ----------
CORE = sorted(glob.glob(os.path.join(ROOT, 'agents', '*.md')) + glob.glob(os.path.join(ROOT, 'skills', '*', 'SKILL.md'))
              + glob.glob(os.path.join(ROOT, 'commands', '*.md')))
ON_DEMAND = sorted(set(glob.glob(os.path.join(ROOT, 'playbooks', '**', '*.md'), recursive=True))
                   | {p for p in glob.glob(os.path.join(ROOT, 'skills', '**', '*.md'), recursive=True) if os.path.basename(p) != 'SKILL.md'})
PATH_RE = re.compile(r'(?<![\w./<>-])(?:\$\{CLAUDE_PLUGIN_ROOT\}/|<plugin-root>/)?'
                     r'((?:playbooks|skills|scripts|hooks|agents|commands|references)/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.(?:md|sh|py|json))')
TRIGGER_RE = re.compile(M['on_demand_trigger'])


def resolve(src, ref):
    if ref.startswith('references/'):
        return os.path.normpath(os.path.join(os.path.dirname(src), ref))
    return os.path.normpath(os.path.join(ROOT, ref))


def paragraph(lines, i):
    """The list item / paragraph that contains line i (a pointer's trigger may wrap lines)."""
    item = re.compile(r'^\s*(?:[-*]|\d+\.)\s|^\s*#')
    lo = i
    while lo > 0 and lines[lo - 1].strip() and not item.match(lines[lo]):
        lo -= 1
    hi = i
    while hi + 1 < len(lines) and lines[hi + 1].strip() and not item.match(lines[hi + 1]):
        hi += 1
    return '\n'.join(lines[lo:hi + 1])


referenced = {}
for src in CORE + ON_DEMAND:
    lines = read(src).split('\n')
    for i, line in enumerate(lines):
        for m in PATH_RE.finditer(line):
            target = resolve(src, m.group(1))
            S.check(os.path.exists(target), '%s:%d names %s, which does not exist' % (rel(src), i + 1, m.group(1)))
            if src in CORE and target in ON_DEMAND:
                referenced.setdefault(target, []).append(src)
            if src in CORE and target in ON_DEMAND and '/commands/' not in src:
                S.check(bool(TRIGGER_RE.search(paragraph(lines, i))),
                        '%s:%d points at %s without a trigger (WHEN/BEFORE/AFTER/ONLY/policy:)' % (rel(src), i + 1, m.group(1)))

# stack packs: siblings are read through the pack's own SKILL.md table (bare file names)
for pack_skill in glob.glob(os.path.join(ROOT, 'skills', 'pack-*', 'SKILL.md')):
    text = read(pack_skill)
    for sib in glob.glob(os.path.join(os.path.dirname(pack_skill), '*')):
        base = os.path.basename(sib)
        if base != 'SKILL.md' and '`%s`' % base in text:
            referenced.setdefault(sib, []).append(pack_skill)
        elif base != 'SKILL.md':
            S.check(False, '%s is not listed in its pack SKILL.md' % rel(sib))

for path in ON_DEMAND:  # Read returns on-demand files RAW: the variable would reach Bash unexpanded (authoring.md)
    hits = [i + 1 for i, ln in enumerate(read(path).split('\n')) if re.search(r'\$\{?CLAUDE_PLUGIN_ROOT\b', ln)]
    S.check(not hits, '%s:%s writes the CLAUDE_PLUGIN_ROOT variable; on-demand files use <plugin-root>' % (rel(path), hits))
for path in ON_DEMAND:
    S.check(path in referenced, 'orphan on-demand file (no core file points at it): %s' % rel(path))
for path in glob.glob(os.path.join(ROOT, 'playbooks', '*', '')):
    owner = os.path.basename(os.path.dirname(path))
    S.check(owner == '_shared' or owner in AGENTS, 'playbooks/%s/ has no agent of that name' % owner)


# ---------- 6. bash allowlist <-> agents ----------
allow = json.load(open(os.path.join(ROOT, 'hooks', 'bash-allowlist.json')))
entries = allow.get('agents', {})
for name, a in AGENTS.items():
    has_bash = 'Bash' in a['tools']
    S.check(('swarm:' + name in entries) == has_bash, '%s: has an allowlist entry iff its tools include Bash' % name)
for key in entries:
    S.check(key.startswith('swarm:') and key[6:] in AGENTS, 'allowlist entry %s names no agent' % key)
writers = sorted('swarm:' + n for n, a in AGENTS.items() if {'Write', 'Edit'} & set(a['tools']))
S.check(sorted(allow.get('file_writers', [])) == writers,
        'file_writers == agents whose tools include Write/Edit (diff: %s)' % sorted(set(writers) ^ set(allow.get('file_writers', []))))


# ---------- 7. commands <-> plugin.json ----------
manifest = json.load(open(os.path.join(ROOT, '.claude-plugin', 'plugin.json')))
declared = {c.lstrip('./') for c in manifest.get('commands', [])}
on_disk = {rel(p) for p in glob.glob(os.path.join(ROOT, 'commands', '*.md'))}
S.check(declared == on_disk, 'plugin.json commands == commands/*.md (diff: %s)' % sorted(declared ^ on_disk))
for path in sorted(on_disk):
    front, _ = split_frontmatter(read(os.path.join(ROOT, path)))
    S.check(bool(front and front.get('description') and front.get('allowed-tools')), '%s: description + allowed-tools' % path)
run_front, run_body = split_frontmatter(read(os.path.join(ROOT, 'commands', 'run.md')))
S.check('$ARGUMENTS' in run_body, 'commands/run.md forwards $ARGUMENTS to the root')


# ---------- 8. requirements.json schema (plugin + packs) ----------
def check_requirements(path, must_have):
    try:
        d = json.load(open(path))
    except (OSError, ValueError) as exc:
        S.check(False, '%s: valid JSON (%s)' % (rel(path), exc))
        return
    S.check(all(isinstance(d.get(k), list) for k in ('os', 'project', 'libs')), '%s: os/project/libs are lists' % rel(path))
    for item in d.get('os', []):
        S.check(isinstance(item.get('required'), bool), '%s: os entry %s declares required: bool' % (rel(path), item.get('tool')))
        S.check(not item.get('required') or bool(item.get('install')) or item.get('tool') in ('git', 'python3', 'uuidgen'),
                '%s: required os entry %s has an install hint' % (rel(path), item.get('tool')))
    tools = {i.get('tool') for i in d.get('os', [])}
    S.check(must_have <= tools, '%s: declares %s' % (rel(path), sorted(must_have - tools)))
    for item in d.get('libs', []):
        S.check(bool(item.get('name') and item.get('manager')), '%s: lib entry needs name + manager' % rel(path))


check_requirements(os.path.join(ROOT, 'requirements.json'), {'git', 'python3', 'uuidgen'})
for pack_req in glob.glob(os.path.join(ROOT, 'skills', 'pack-*', 'requirements.json')):
    check_requirements(pack_req, set())


# ---------- 9. documented verdicts pass the real validator ----------
VERDICT = re.compile(r'^(OK\b|KO\s|DONE\b|BLOCKED\s)')
NEVER = re.compile(r'never|nunca|not\b|wrong', re.I)
NO_ROOT = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'swarm-structure-no-root', '.swarm')
jobs = []
for name, a in AGENTS.items():
    output = re.search(r'^## (?:\d+\.\s*)?Output.*?(?=^## |\Z)', a['body'], re.S | re.M)
    examples = [b for lang, b in fenced_blocks(output.group(0) if output else '') if not lang and VERDICT.match(b)]
    S.check(bool(examples), '%s: its ## Output section carries at least one verdict example' % name)
    for src in [a['path']] + playbook_files(name):
        body = split_frontmatter(read(src))[1]
        for lang, block in fenced_blocks(body):
            if not lang and VERDICT.match(block):
                # a one-line block documents line 1 only; the protocol's evidence line follows it
                jobs.append((name, rel(src), block if '\n' in block else block + '\nevidence: files=1 cmds=1 turns=1/10'))
        for m in re.finditer(r'`([^`\n]+)`', body):
            if VERDICT.match(m.group(1)) and not NEVER.search(body[max(0, m.start() - 25):m.start()]):
                jobs.append((name, rel(src), m.group(1) + '\nevidence: files=1 cmds=1 turns=1/10'))
results = parallel(lambda j: validate('swarm:' + j[0], j[2], NO_ROOT), jobs)
for (name, src, msg), res in zip(jobs, results):
    S.check(res in ('accept', 'system'), '%s: documented verdict rejected by validate-output.py (%s): %r' % (src, res, msg[:140]))


# ---------- 10. documented shell commands pass the real guard ----------
def logical_lines(block):
    out, heredoc = [], None
    for line in block.split('\n'):
        if heredoc:  # a heredoc body belongs to the command that opened it
            out[-1] += '\n' + line
            heredoc = None if line.strip() == heredoc else heredoc
            continue
        out.append(line.rstrip())  # no `\\` joining: the guard bans it, so a continuation must fail here
        m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", out[-1])
        heredoc = m.group(1) if m else None
    return [ln.strip() for ln in out if ln.strip() and not ln.strip().startswith('#')]


SWARM_DIR = tempfile.mkdtemp(prefix='swarm-structure.')
os.makedirs(os.path.join(SWARM_DIR, '.swarm'))


def concrete(cmd):  # <swarm-root> = an existing .swarm, as the header's swarm-root: always is
    cmd = cmd.replace('<plugin-root>', ROOT).replace('<swarm-root>', os.path.join(SWARM_DIR, '.swarm'))
    return re.sub(r'<[A-Za-z][^<>\n]*>', 'PLACEHOLDER', cmd)


cmd_jobs = []
for name, a in AGENTS.items():
    if 'Bash' not in a['tools']:
        continue
    for src in [a['path']] + playbook_files(name):
        for lang, block in fenced_blocks(split_frontmatter(read(src))[1]):
            if lang in ('bash', 'sh'):
                cmd_jobs += [(name, rel(src), concrete(c)) for c in logical_lines(block)]

# stack pack command tables: `| key | condition | `cmd` | executor[+executor] |`
for table in glob.glob(os.path.join(ROOT, 'skills', 'pack-*', 'commands.md')):
    rows = 0
    for line in read(table).split('\n'):
        cells = line.strip().strip('|').split('|')
        if not line.startswith('|') or len(cells) < 4:
            continue
        cmd = '|'.join(cells[2:-1]).strip()
        m = re.match(r'^`(.+)`$', cmd)
        if not m:
            continue
        rows += 1
        for executor in (e.strip() for e in cells[-1].split('+')):
            S.check(executor in AGENTS, '%s: executor %s is an agent' % (rel(table), executor))
            cmd_jobs.append((executor, rel(table), concrete(m.group(1))))
    S.check(rows >= 12, '%s: the command table parses (%d rows)' % (rel(table), rows))

decisions = parallel(lambda j: guard('swarm:' + j[0], j[2]), cmd_jobs)
shutil.rmtree(SWARM_DIR, ignore_errors=True)
for (name, src, cmd), res in zip(cmd_jobs, decisions):
    S.check(res == 'allow', '%s: documented command denied for swarm:%s: %s' % (src, name, cmd[:160]))

S.done()
