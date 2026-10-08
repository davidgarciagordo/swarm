#!/usr/bin/env bash
# scripts/swarm-cost.sh — what a run cost, per agent, read from the session transcripts. Deterministic: no model turn.
#
#   swarm-cost.sh [--session <id>] [--projects <dir>] [--repo <dir>]
#       --projects  transcripts root (default: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects)
#       --repo      repository the session ran in (default: $PWD); selects the project folder
#       --session   session id (default: the most recent session of that repo that spawned subagents)
#
# Prints one line per agent in start order (type, model, turns, tool calls, tokens: input, cache write, cache read,
# output), then the totals. Tokens only: prices change and depend on the account, so no currency is computed.
# Exit: 0 ok · 1 no transcripts found · 64 usage error.
set -u

PROJECTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
REPO="$PWD"
SESSION=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || { echo "swarm-cost.sh: $1 requires a value" >&2; exit 64; }
  case "$1" in
    --projects) PROJECTS="$2" ;;
    --repo) REPO="$2" ;;
    --session) SESSION="$2" ;;
    *) echo "swarm-cost.sh: unknown argument: $1" >&2; exit 64 ;;
  esac
  shift 2
done
case "$SESSION" in *[!A-Za-z0-9-]*) echo "swarm-cost.sh: invalid session id" >&2; exit 64 ;; esac

python3 - "$PROJECTS" "$REPO" "$SESSION" <<'PYEOF'
import glob, json, os, re, sys

projects, repo, session = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3]
folder = os.path.join(projects, re.sub(r'[^A-Za-z0-9]', '-', repo))
if not session:
    dirs = [d for d in glob.glob(os.path.join(folder, '*', 'subagents')) if os.path.isdir(d)]
    if not dirs:
        print('swarm-cost.sh: no session with subagents under %s' % folder, file=sys.stderr)
        sys.exit(1)
    session = os.path.basename(os.path.dirname(max(dirs, key=os.path.getmtime)))
main = os.path.join(folder, session + '.jsonl')
subs = sorted(glob.glob(os.path.join(folder, session, 'subagents', '*.jsonl')))
if not os.path.isfile(main) and not subs:
    print('swarm-cost.sh: no transcripts for session %s under %s' % (session, folder), file=sys.stderr)
    sys.exit(1)

KEYS = (('input_tokens', 'in'), ('cache_creation_input_tokens', 'cwrite'),
        ('cache_read_input_tokens', 'cread'), ('output_tokens', 'out'))


def read(path):
    usage, tools, model, start = {}, 0, '', ''
    try:
        handle = open(path, encoding='utf-8', errors='replace')
    except OSError:
        return None
    with handle:
        for raw in handle:
            try:
                row = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(row, dict):
                continue
            start = start or (row.get('timestamp') or '')
            msg = row.get('message')
            if row.get('type') != 'assistant' or not isinstance(msg, dict) or not isinstance(msg.get('usage'), dict):
                continue
            usage[msg.get('id')] = msg['usage']  # one API response spans several rows: count it once
            model = msg.get('model') or model
            tools += sum(1 for c in (msg.get('content') or []) if isinstance(c, dict) and c.get('type') == 'tool_use')
    tok = {short: sum(int(u.get(key) or 0) for u in usage.values()) for key, short in KEYS}
    return {'start': start, 'turns': len(usage), 'tools': tools, 'model': model, 'tok': tok}


rows = []
if os.path.isfile(main):
    data = read(main)
    if data:
        rows.append(dict(data, agent='(main session)'))
for path in subs:
    data = read(path)
    if not data:
        continue
    agent = '?'
    try:
        agent = json.load(open(path[:-len('.jsonl')] + '.meta.json')).get('agentType') or '?'
    except (OSError, ValueError):
        pass
    rows.append(dict(data, agent=agent))
rows.sort(key=lambda r: r['start'])

print('session: %s' % session)
print('%-34s %-22s %5s %5s %9s %10s %11s %9s' % ('agent', 'model', 'turns', 'tools', 'in', 'cwrite', 'cread', 'out'))
total = dict.fromkeys((s for _, s in KEYS), 0)
for r in rows:
    for k in total:
        total[k] += r['tok'][k]
    print('%-34s %-22s %5d %5d %9d %10d %11d %9d' % (
        r['agent'][:34], r['model'][:22], r['turns'], r['tools'],
        r['tok']['in'], r['tok']['cwrite'], r['tok']['cread'], r['tok']['out']))
print('agents: %d (main session excluded)' % sum(1 for r in rows if r['agent'] != '(main session)'))
print('total: in=%(in)d cwrite=%(cwrite)d cread=%(cread)d out=%(out)d' % total)
PYEOF
