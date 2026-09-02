#!/usr/bin/env python3
"""hooks/bash-guard.py — PreToolUse hook: allowlist de Bash por agent_type (spec §3.1).

Contrato de stdin (JSON):
  {"agent_type": "swarm:<name>", "tool_name": "Bash", "tool_input": {"command": "<comando>"}}
"""
import json
import os
import re
import shlex
import sys

ALLOWLIST_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bash-allowlist.json')

# Un ÚNICO prefijo de entorno transparente: `SWARM_ROOT=<valor> <resto>`. Es el mecanismo
# documentado en skills/swarm-protocol/SKILL.md §3 para que un agente en worktree (o con el
# cwd fuera de la raíz) apunte al `.swarm/` canónico. Se recorta ANTES de validar, así que el
# resto del segmento se juzga con las reglas normales: `SWARM_ROOT=/x rm -rf /` sigue denegado.
#
# El valor se restringe a un charset de ruta seguro — NUNCA `\S+` (permitía `$(...)`/`${IFS}`
# sin espacio literal, ejecutando comandos arbitrarios al evaluarse en el shell real; hallazgo
# de la re-review final, corregido antes de merge). Nada de `$`, backticks, `(`, `)`, `{`, `}`,
# `;`, `|`, `&`, `<`, `>`, comillas, `*`, `?`, `~` seguido de nada raro — solo lo que una ruta
# absoluta legítima necesita.
ENV_PREFIX_RE = re.compile(r'^SWARM_ROOT=[A-Za-z0-9_./-]+$')

# `find` sin restricción es un escape hatch (ejecuta/borra arbitrariamente). Solo se permite
# como buscador de solo lectura.
FIND_DENIED_FLAGS = ('-exec', '-execdir', '-ok', '-okdir', '-delete')

# `scripts/mem-*` debe casar solo con los scripts reales del plugin, no con cualquier binario
# cuyo basename empiece por `mem-`.
MEM_SCRIPT_RE = re.compile(r'^mem-[A-Za-z0-9_.-]+\.sh$')

# Intérpretes con evaluación inline: `python3 -c`, `node -e`, `php -r` ejecutan código arbitrario
# sin fichero y convierten un allowlist de "puedes correr tu spike" en "puedes correr cualquier
# cosa". Se deniegan por flag aunque el intérprete esté permitido (feasibility-spiker, fase 2).
INTERP_DENIED_FLAGS = {
    'python3': ('-c',),
    'python': ('-c',),
    'node': ('-e', '--eval', '-p', '--print'),
    'php': ('-r',),
}


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


def _plugin_root_abs():
    # hooks/bash-guard.py vive en <plugin-root>/hooks/ — un nivel arriba.
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def strip_plugin_root(word):
    """Recorta el prefijo de la raíz del plugin, en cualquiera de sus dos formas.

    Un agente puede invocar un script con la variable literal (`${CLAUDE_PLUGIN_ROOT}/...`)
    o con la ruta absoluta ya resuelta (`/abs/path/al/plugin/...`) — ambas deben normalizar
    igual antes de comparar contra el allowlist. Antes de este fix solo se recortaba la forma
    de variable, así que cualquier script nuevo fuera de la familia `mem-*.sh` (que tenía su
    propio fallback especial) quedaba denegado en cuanto se invocaba con ruta absoluta —
    encontrado en vivo con `scripts/req-check.sh` (fase 1b, smoke test).
    """
    var_prefix = '${CLAUDE_PLUGIN_ROOT}/'
    if word.startswith(var_prefix):
        return word[len(var_prefix):]
    abs_prefix = _plugin_root_abs() + '/'
    if word.startswith(abs_prefix):
        return word[len(abs_prefix):]
    return word


def is_mem_script(word):
    """`<algo>/scripts/mem-<nombre>.sh` — el basename por sí solo no basta."""
    head, tail = os.path.split(word)
    return bool(MEM_SCRIPT_RE.match(tail)) and os.path.basename(head) == 'scripts'


def segment_allowed(segment, allowlist):
    words = segment_words(segment)
    if words and ENV_PREFIX_RE.match(words[0]):
        words = words[1:]
    if not words:
        return False
    first_raw = strip_plugin_root(words[0])
    first_two = ' '.join(words[:2])
    command_word = os.path.basename(first_raw)
    if command_word == 'find':
        for word in words[1:]:
            if word in FIND_DENIED_FLAGS:
                return False
    denied_flags = INTERP_DENIED_FLAGS.get(command_word)
    if denied_flags:
        for word in words[1:]:
            # Igualdad exacta no basta: `--eval=CODE`, `-cCODE`/`-rCODE` pegados, y clusters de
            # flags cortos (`-pe`) son sintaxis válida de estos intérpretes y ejecutan código
            # inline igual que la forma con espacio — hallazgo de la review de T4 (fase 2).
            if word in denied_flags:
                return False
            if word.split('=', 1)[0] in denied_flags:  # --eval=CODE
                return False
            for flag in denied_flags:
                if len(flag) == 2 and word.startswith(flag) and word != flag:
                    return False  # -cCODE, -rCODE pegados
            if re.match(r'^-[A-Za-z]+$', word) and not word.startswith('--'):
                if any(len(f) == 2 and f[1] in word[1:] for f in denied_flags):
                    return False  # cluster -pe / -ep
    for prefix in allowlist:
        if ' ' in prefix:
            if first_two == prefix or first_two.startswith(prefix + ' '):
                return True
            continue
        # Coincidencia EXACTA de la primera palabra (no `startswith`): `ls` no casa `lsof`,
        # `cd` no casa `cdrecord`, `cat` no casa `catfoo`.
        if first_raw == prefix:
            return True
        if prefix.startswith('scripts/mem') and is_mem_script(first_raw):
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
