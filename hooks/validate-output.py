#!/usr/bin/env python3
"""hooks/validate-output.py — SubagentStop hook: validates the swarm evidence contract (spec §6.1).

stdin contract (JSON, the platform's real field — verified empirically, see C1):
  {"agent_type": "swarm:<name>", "last_assistant_message": "<the subagent's full text>"}

Behaviour:
  - agent_type not starting with "swarm:" -> exit 0, no output (not our business).
  - line 1 must be a verdict: OK | KO <reason> | DONE | BLOCKED <reason>.
  - line 2 must be `evidence: files=N cmds=M turns=k/max` (whitespace-tolerant).
  - OK with files=0 is rejected (a green verdict with no real evidence).
  - narration (long prose instead of the finding format) is rejected.
  - if turns >= max: NOT a block; a systemMessage is emitted and the hook exits 0.
  - stop_hook_active=true (the platform is already retrying this same Stop) -> exit 0, nothing
    is re-evaluated (avoids amplifying the hook's own block into a loop).
  - a rejection is retried at most once (counter in
    run/<run>/retries/<agent>-<hash(reason)>, i.e. per agent + concrete failure reason
    -- two different reasons from the same agent are each a "first strike"); on the
    SECOND rejection for the SAME reason from the same agent in the same run, it is accepted as
    BLOCKED (with a systemMessage) instead of rejecting again -- never an infinite loop.

WAITING status (live async children -- the hook must NOT force a verdict):
  An agent that launched `background: true` children and ends a turn BEFORE they report is not
  finished: forcing `OK|KO|DONE|BLOCKED` there made it close with a premature verdict while its
  children were still alive. The least-magic reliable signal is an EXPLICIT status the agent
  writes itself -- the hook cannot see the platform's live-children roster:

      WAITING <n>
      pending: <child-1>, <child-2>, ...      (exactly n names, the children still running)

  Rules the hook enforces:
    - n is an integer >= 1 and the `pending:` line names exactly n distinct children; otherwise
      it is rejected like any malformed stop (same one-retry-then-BLOCKED counter).
    - an accepted WAITING is NOT a verdict: exit 0 with no output, and the retry counter is not
      touched. The agent's real verdict comes in a later turn and is validated normally.
    - anti-dodge cap: at most WAITING_CAP accepted WAITINGs per agent INSTANCE per run (counter in
      run/<run>/waiting/<agent>-<agent_id>, or <agent> when the payload has no agent_id), so
      parallel or round-2 instances of the same orchestrator never share one cap. A verdict from
      that instance resets its counter. Past the cap it is rejected: "emit a verdict with what you
      have" -- an agent cannot stall forever by claiming children.
    - WAITING needs a stored counter: if it cannot be written (no `.swarm/`, unwritable dir) the
      WAITING is rejected -- an uncounted WAITING would be an unlimited one.
  Callers (orchestrators) treat a `WAITING <n>` result as "not done yet", never as DONE/OK and
  never as a reason to relaunch the child.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

VERDICT_RE = re.compile(r'^(OK|KO .+|DONE|BLOCKED .+)$')
EVIDENCE_RE = re.compile(
    r'^evidence:\s*files\s*=\s*(\d+)\s+cmds\s*=\s*(\d+)\s+turns\s*=\s*(\d+)\s*/\s*(\d+)\s*$'
)
FINDING_RE = re.compile(r'^[A-Z0-9_-]+\s*·\s*\S+:\d+\s*·\s.+→.+$')
MAX_FINDING_LINE_LEN = 120
WAITING_RE = re.compile(r'^WAITING\s+(\d+)$')
PENDING_RE = re.compile(r'^pending:\s*(.+)$')
CHILD_NAME_RE = re.compile(r'^[a-z][a-z0-9-]*$')
WAITING_CAP = 6

# discovery-orchestrator batch format (spec §7, agents/discovery-orchestrator.md "## Output"):
# a question with up to 4 options (<=8 words each) plus a recommendation routinely exceeds the
# 120-char narration cap — real lines run 184-212 chars. Structurally it is NOT loose prose: it is
# a fixed, parseable format (header + question + options A-D + rec), so it is exempt from the cap
# by SHAPE, never merely for starting with "- " — any other "- " line stays subject to the 120
# (that was the original bug: narration slipping through with no cap at all).
DISCOVERY_Q_RE = re.compile(r'^- Q\d+ \[[^\]]{1,12}\] .+ · [A-D]\) .+ · rec: [A-D]$')
# DISCOVERY_OTHER_RE also covers analysis-orchestrator's fixed vocabulary (spec §7 "Analysis",
# agents/analysis-orchestrator.md "## Output"): `- lenses: <n1>, <n2>, ..., reason: <...>` lists up
# to 6 lenses with long names (`vulnerability-scanner`, `architecture-auditor`...) and routinely
# exceeds 120 chars when several match (real lines up to 174 chars). `- no findings: <leaf> ...`
# (OK with zero findings) is short by construction but is the same fixed vocabulary, exempt by
# SHAPE, not by "- " — included here for locality. `- grill: N P1 incorporated (...), M P2/P3
# noted as risk in the plan` is design-orchestrator's fixed vocabulary (spec §7 "Design",
# agents/design-orchestrator.md "## Output", "Arbitration") — a real arbitration summary line
# (which P1s were incorporated, in parentheses) routinely exceeds 120 chars too.
# The legacy Spanish vocabulary (`lentes`, `sin hallazgos`) is still accepted alongside English:
# `- lenses:`/`- no findings:` were being rejected as narration once longer than 120 chars.
# `- assumed:` (non-interactive runs) and `- review:` (review panel verdict) are root vocabulary.
DISCOVERY_OTHER_RE = re.compile(
    r'^- (warn|findings|lentes|lenses|sin hallazgos|no findings|grill|assumed|review): .+$'
)
# analysis-orchestrator's other two fixed lines carry a DYNAMIC prefix (the number of truncated
# findings, the leaf name) and do not fit the `(a|b|c):` above, so each gets its own regex anchored
# to the exact shape documented in agents/analysis-orchestrator.md — still exemptions by SHAPE,
# not by "- ": `- N additional findings in .swarm/findings/<leaf>.md` (20 merged lines cap) and
# `- <leaf> BLOCKED: <reason>` (a blocked leaf, propagated rather than dropped).
ANALYSIS_ADDITIONAL_RE = re.compile(
    r'^- \d+ (?:hallazgos adicionales en|additional findings in) \.swarm/findings/\S+\.md$'
)
ANALYSIS_LEAF_BLOCKED_RE = re.compile(r'^- [a-z][a-z0-9-]* BLOCKED: .+$')

# Delivery domain fixed vocabulary (spec §7 "Delivery", agents/release-manager.md and
# agents/delivery-orchestrator.md "## Output"): the preview and PR-degradation lines carry a FULL
# COMMAND with resolved values (`gh pr create --base … --body-file /abs/…/release-notes.md`) and
# routinely exceed 120 chars. Exempt by SHAPE (fixed vocabulary prefix + rest), NEVER merely for
# starting with "- ": any other "- " line stays subject to the 120 cap. Legacy Spanish prefixes
# are still accepted.
DELIVERY_LONG_RE = re.compile(
    r'^- (preview push|preview pr|pr|pr manual|pr comando|notas|handoff|pushed|remote'
    r'|remoto propuesto|remoto creado|cuenta gh|hint|siguiente|discrepancia'
    r'|notes|proposed remote|remote created|gh account|next|discrepancy|command'
    r'|push destinations|current branch|candidate aliases): .+$'
)


def _repo_root():
    """The repo's real root, NOT the hook's cwd.

    The hook runs in the SESSION's cwd: if the user opened Claude Code from a subdirectory
    (`packages/api` in a monorepo), `os.getcwd()` points to the wrong place — and the
    `cd "$(git rev-parse --show-toplevel)"` the orchestrator does inside ITS Bash calls does not
    change THIS process's cwd. Same technique as the orchestrator (agents/orchestrator.md §2.0).
    Outside a git repo it falls back to the cwd.
    """
    try:
        out = subprocess.check_output(
            ['git', 'rev-parse', '--show-toplevel'],
            stderr=subprocess.DEVNULL,
        )
    except (OSError, ValueError, subprocess.CalledProcessError):
        return os.getcwd()
    root = out.decode('utf-8', 'replace').strip()
    return root or os.getcwd()


def _swarm_root():
    from_env = os.environ.get('SWARM_ROOT')
    if from_env:
        return from_env
    return os.path.join(_repo_root(), '.swarm')


def _current_run(swarm_root):
    current_file = os.path.join(swarm_root, 'run', 'current')
    try:
        with open(current_file) as f:
            run_id = f.read().strip()
            if run_id:
                return run_id
    except OSError:
        pass
    return 'adhoc'


def _retry_key(agent_type, reason):
    # Keyed by agent + reason (not agent alone): two *different* failure
    # reasons for the same agent in the same run are each a first offense;
    # only a repeat of the SAME failure counts as the second strike.
    agent_basename = agent_type.split(':')[-1]
    reason_hash = hashlib.sha256(reason.encode('utf-8')).hexdigest()[:8]
    return '%s-%s' % (agent_basename, reason_hash)


def _retry_count(swarm_root, run_id, retry_key):
    retries_dir = os.path.join(swarm_root, 'run', run_id, 'retries')
    path = os.path.join(retries_dir, retry_key)
    try:
        with open(path) as f:
            return int(f.read().strip() or '0'), path, retries_dir
    except (OSError, ValueError):
        return 0, path, retries_dir


def _bump_retry(swarm_root, path, retries_dir, count):
    # A hook NEVER creates a `.swarm/`: only `/swarm:init` creates that tree. If the resolved
    # root does not exist, the retry counter is lost (the rejection is still emitted) rather
    # than seeding a phantom `.swarm/` in the wrong directory.
    if not os.path.isdir(swarm_root):
        return
    # The counter is best-effort: if the retries directory is not writable (permissions, a race
    # with another process), the rejection is still emitted — a failure here must not crash the
    # whole hook (the platform would treat that as fail-open and let anything through).
    try:
        os.makedirs(retries_dir, exist_ok=True)
        with open(path, 'w') as f:
            f.write(str(count + 1))
    except OSError:
        pass


def _waiting_reason(lines):
    """None if `lines` is a well-formed WAITING status, else the rejection reason."""
    n = int(WAITING_RE.match(lines[0].strip()).group(1))
    if n < 1:
        return 'WAITING <n> requires n >= 1 (no live children: emit a verdict)'
    pending = PENDING_RE.match(lines[1].strip()) if len(lines) >= 2 else None
    if not pending:
        return 'WAITING <n> requires line 2 `pending: <child>, ...` naming the n live children'
    names = [x.strip() for x in pending.group(1).split(',') if x.strip()]
    if len(set(names)) != n or len(names) != n or not all(CHILD_NAME_RE.match(x) for x in names):
        return 'WAITING %d exige exactamente %d nombres de hijo distintos en `pending:`' % (n, n)
    return None


def _waiting_key(agent_type, agent_id):
    base = agent_type.split(':')[-1]
    safe_id = re.sub(r'[^A-Za-z0-9_.-]', '', agent_id or '')[:64]
    return '%s-%s' % (base, safe_id) if safe_id else base


def _waiting_count(swarm_root, run_id, key):
    path = os.path.join(swarm_root, 'run', run_id, 'waiting', key)
    try:
        with open(path) as f:
            return int(f.read().strip() or '0'), path
    except (OSError, ValueError):
        return 0, path


def _bump_waiting(swarm_root, path, count):
    """True if the counter was stored. Never originates a `.swarm/`, never crashes the hook."""
    if not os.path.isdir(swarm_root):
        return False
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            f.write(str(count + 1))
    except OSError:
        return False
    return True


def _reset_waiting(path):
    try:
        os.remove(path)
    except OSError:
        pass


def _block(reason):
    print(json.dumps({'decision': 'block', 'reason': reason}))
    sys.exit(0)


def _system_message(message):
    print(json.dumps({'systemMessage': message}))
    sys.exit(0)


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    # The platform re-invokes this hook when ITS OWN previous block already triggered a retry
    # (standard field of Stop/SubagentStop hooks) — ignoring it could amplify the hook's own block
    # into a loop, on top of the retry counter kept further down.
    if data.get('stop_hook_active') is True:
        sys.exit(0)

    agent_type = data.get('agent_type', '')
    if not isinstance(agent_type, str) or not agent_type.startswith('swarm:'):
        sys.exit(0)

    # Real SubagentStop payload field is `last_assistant_message`, not `output`
    # (verified against code.claude.com/docs/en/hooks.md and empirically via a
    # live PreToolUse capture confirming the sibling schema matches the docs).
    output = data.get('last_assistant_message', '')
    if not isinstance(output, str):
        sys.exit(0)
    lines = output.split('\n')

    swarm_root = _swarm_root()
    run_id = _current_run(swarm_root)

    verdict_line = lines[0].strip() if len(lines) >= 1 else ''
    evidence_line = lines[1].strip() if len(lines) >= 2 else ''

    reason = None

    agent_id = data.get('agent_id') if isinstance(data.get('agent_id'), str) else ''
    waited, waiting_path = _waiting_count(swarm_root, run_id, _waiting_key(agent_type, agent_id))

    if WAITING_RE.match(verdict_line):
        reason = _waiting_reason(lines)
        if reason is None:
            if waited >= WAITING_CAP:
                reason = ('WAITING repeated %d times: emit a verdict with what you have' % WAITING_CAP)
            elif _bump_waiting(swarm_root, waiting_path, waited):
                sys.exit(0)
            else:
                reason = 'WAITING cannot be counted (no writable .swarm/): emit a verdict'
    elif not VERDICT_RE.match(verdict_line):
        reason = 'line 1 must be a verdict: OK | KO <reason> | DONE | BLOCKED <reason>'

    evidence_match = None
    if reason is None:
        evidence_match = EVIDENCE_RE.match(evidence_line)
        if not evidence_match:
            reason = 'line 2 is required: evidence: files=N cmds=M turns=k/max'

    turns_k = turns_max = None
    if reason is None:
        files_n = int(evidence_match.group(1))
        turns_k = int(evidence_match.group(3))
        turns_max = int(evidence_match.group(4))

        if verdict_line == 'OK' and files_n == 0:
            reason = 'OK with files=0 — a green verdict with no real evidence'

        if reason is None:
            for line in lines[2:]:
                stripped = line.strip()
                if not stripped:
                    continue
                if FINDING_RE.match(stripped):
                    continue
                # discovery/analysis/delivery fixed formats: exempt from the length cap by SHAPE
                # (structural regex), never merely for starting with "- " — see the comments on
                # DISCOVERY_Q_RE / DISCOVERY_OTHER_RE / ANALYSIS_*_RE / DELIVERY_LONG_RE above.
                if (
                    DISCOVERY_Q_RE.match(stripped)
                    or DISCOVERY_OTHER_RE.match(stripped)
                    or ANALYSIS_ADDITIONAL_RE.match(stripped)
                    or ANALYSIS_LEAF_BLOCKED_RE.match(stripped)
                    or DELIVERY_LONG_RE.match(stripped)
                ):
                    continue
                # Any OTHER "- " line (not a recognised fixed format) stays subject to the cap:
                # without this, any prose slips through just by prefixing "- " (a real bug,
                # fixed before — do not reopen it).
                if stripped.startswith('- ') and len(stripped) <= MAX_FINDING_LINE_LEN:
                    continue
                if len(stripped) > MAX_FINDING_LINE_LEN:
                    reason = 'narration detected outside the format TAG · file:line · problem → fix'
                    break

    if reason is None:
        _reset_waiting(waiting_path)
        if turns_k is not None and turns_max and turns_k >= turns_max:
            _system_message(
                'swarm: %s reached maxTurns → treat as BLOCKED maxTurns' % agent_type
            )
        sys.exit(0)

    retry_key = _retry_key(agent_type, reason)
    retry_count, retry_path, retries_dir = _retry_count(swarm_root, run_id, retry_key)

    if retry_count >= 1:
        _system_message(
            'swarm: %s failed validation twice (%s) → accepted as BLOCKED' % (agent_type, reason)
        )

    _bump_retry(swarm_root, retry_path, retries_dir, retry_count)
    _block(reason)


if __name__ == '__main__':
    main()
