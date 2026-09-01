#!/usr/bin/env python3
"""hooks/bash-guard.py — PreToolUse hook: allowlist de Bash por agent_type (spec §3.1).

Contrato de stdin (JSON):
  {"agent_type": "swarm:<name>", "tool_name": "Bash", "tool_input": {"command": "<comando>"}}
"""
import json
import os
import shlex
import sys

ALLOWLIST_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bash-allowlist.json')


def load_allowlist():
    with open(ALLOWLIST_PATH) as f:
        return json.load(f)


def split_segments(command):
    """Divide `command` en &&, ||, ;, | FUERA de comillas (estado de comilla char a char)."""
    segments = []
    current = []
    i = 0
    n = len(command)
    quote = None
    while i < n:
        ch = command[i]
        if quote:
            current.append(ch)
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ('"', "'"):
            quote = ch
            current.append(ch)
            i += 1
            continue
        if command[i:i + 2] in ('&&', '||'):
            segments.append(''.join(current))
            current = []
            i += 2
            continue
        if ch in (';', '|'):
            segments.append(''.join(current))
            current = []
            i += 1
            continue
        current.append(ch)
        i += 1
    segments.append(''.join(current))
    return [s.strip() for s in segments if s.strip()]


def segment_words(segment):
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def strip_plugin_root(word):
    prefix = '${CLAUDE_PLUGIN_ROOT}/'
    if word.startswith(prefix):
        return word[len(prefix):]
    return word


def segment_allowed(segment, allowlist):
    words = segment_words(segment)
    if not words:
        return False
    first_raw = strip_plugin_root(words[0])
    first_two = ' '.join(words[:2])
    basename = os.path.basename(first_raw)
    for prefix in allowlist:
        if ' ' in prefix:
            if first_two == prefix or first_two.startswith(prefix + ' '):
                return True
            continue
        if first_raw.startswith(prefix):
            return True
        if prefix.startswith('scripts/mem') and basename.startswith('mem-'):
            return True
    return False


def deny(reason):
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': reason,
        }
    }))
    sys.exit(0)


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    agent_type = data.get('agent_type', '') or ''
    if not agent_type.startswith('swarm:'):
        sys.exit(0)

    tool_name = data.get('tool_name', '') or ''
    if tool_name != 'Bash':
        sys.exit(0)

    command = (data.get('tool_input') or {}).get('command', '') or ''
    if not command.strip():
        sys.exit(0)

    allowlists = load_allowlist()
    agent_allowlist = allowlists.get('agents', {}).get(agent_type, allowlists.get('default', []))

    for segment in split_segments(command):
        if not segment_allowed(segment, agent_allowlist):
            deny('%s no está en el allowlist de %s' % (segment, agent_type))
            return

    sys.exit(0)


if __name__ == '__main__':
    main()
