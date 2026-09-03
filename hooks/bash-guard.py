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

# Un prefijo allowlist de DOS palabras ("composer update") no puede expresar "y necesita AL
# MENOS una palabra más detrás" — así que también matchea el comando BARE de dos palabras
# (`composer update` a secas, actualización de TODO el árbol), muy por encima de cualquier
# paquete aprobado explícitamente por el owner (dependency-installer, fase 5b, `approved:`).
# Hasta ahora lo único que lo impedía era la prosa de agents/dependency-installer.md — esto es
# el backstop determinista: se deniega si, tras las dos palabras del prefijo, NINGUNA palabra
# restante deja de empezar por "-" — es decir, ni el caso exacto de dos palabras ni ningún
# número de flags (`--no-interaction`, `-n`, `-W`…) sin nombre de paquete real cuelan, porque
# eso sigue siendo "todo el árbol" con el mismo alcance que el bare de dos palabras. En cuanto
# aparece UNA palabra que no empieza por "-" (el paquete), se permite.
BARE_TWO_WORD_DENIED = {
    ('composer', 'update'),
}

# ── Delivery (fase 6): `git push` es la acción más consecuente e IRREVERSIBLE del enjambre ──
# Un merge local se deshace; un push a un remoto compartido, o un PR que otra persona mergea, no
# siempre. La prosa de agents/release-manager.md dice qué forma usar; esto hace imposible el resto,
# para CUALQUIER agent_type (presente o futuro), igual que BARE_TWO_WORD_DENIED con `composer update`.
PUSH_DENIED_FLAGS = (
    '--force', '-f', '--force-with-lease', '--force-if-includes',
    '--delete', '-d', '--mirror', '--all', '--prune', '--tags', '--follow-tags',
)

# Ramas cuyo destino NUNCA se empuja desde el enjambre. Extiende la guarda de 2 nombres que
# implementation-orchestrator aplica en local (backlog de fase 5a: `develop`/`trunk` no cubiertos).
PROTECTED_REFS = ('master', 'main', 'develop', 'trunk')

# C2 (fase 6, review adversarial): `HEAD` y `@` son alias AMBIGUOS del commit actual — no dicen a
# simple vista qué rama del remoto se toca, y con el checkout equivocado apuntan a `master`/`main`
# tan fácilmente como a una feature branch. La única forma permitida es un nombre de rama EXPLÍCITO.
PUSH_AMBIGUOUS_DST = ('HEAD', '@')

# C3/I1 (fase 6, review adversarial): whitelist de FORMA, no blacklist de alias. `heads/<rama>` y
# `refs/heads/<rama>` resuelven al MISMO destino real que `<rama>` a secas vía DWIM de git — una
# blacklist de prefijos conocidos puede no cubrir un alias futuro; una whitelist de forma ("el
# destino es un nombre de rama LISO, sin ningún prefijo `refs/`/`heads/`/`tags/`") no puede fallar
# abierta. Esto también cierra I1 (`refs/tags/v1` / `tags/v1` sin la flag `--tags`).
PUSH_DENIED_DST_PREFIXES = ('refs/', 'heads/', 'tags/')

# Tercera palabra denegada para un prefijo de dos palabras ya permitido. Un prefijo de DOS palabras
# ("gh pr") no puede expresar "todo menos merge" — esto lo expresa. `gh pr merge` es la línea roja
# permanente del diseño (el PR lo mergea una persona); los mutantes DESTRUCTIVOS de `git remote` y
# `gh auth` cambian configuración del owner fuera del alcance de un run.
#
# `add` NO está en la lista de `git remote`: es la única forma que el bootstrap de remoto necesita
# (ruling 3) y es ADITIVA — `git remote add` falla si el nombre ya existe, así que no puede pisar un
# remoto del owner. Su forma exacta la fija `remote_add_segment_denied`. `set-url` SÍ sigue denegado:
# reescribir la URL de un remoto existente es justo lo que el ruling 14 prohíbe hacer en silencio.
SUBCOMMAND_DENIED_ARGS = {
    ('git', 'remote'): ('remove', 'rm', 'set-url', 'rename', 'set-head', 'set-branches', 'prune', 'update'),
    ('gh', 'pr'): ('merge', 'close', 'edit', 'ready', 'review', 'reopen', 'comment', 'lock', 'unlock', 'checkout'),
    ('gh', 'auth'): ('login', 'logout', 'refresh', 'setup-git', 'token'),
}

# C1 (fase 6, review adversarial): flags de `gh` que TOMAN VALOR y pueden aparecer ANTES del
# subcomando real (`gh pr --repo o/r merge 12`, `gh auth -h github.com token`). Sin esto,
# `subcommand_and_rest` confundía el VALOR del flag (`o/r`, `github.com`) con el subcomando, y el
# subcomando real (`merge`, `token`…) se colaba sin comprobar. Su valor se consume/salta antes de
# buscar el subcomando, así el escaneo solo mira palabras con forma de subcomando, nunca valores.
GH_VALUE_TAKING_FLAGS = frozenset({'--repo', '-R', '--hostname', '-h'})

# Inverso de SUBCOMMAND_DENIED_ARGS: para estos prefijos de dos palabras SOLO se permite un conjunto
# CERRADO de terceras palabras, y cualquier otra (incluida la ausencia de tercera palabra) se
# deniega. Denylist y allowlist no son intercambiables: `gh repo` tiene decenas de subcomandos y `gh`
# añade más en cada versión, así que enumerar lo prohibido envejece mal y falla ABIERTO. Aquí sólo
# `create` es alcanzable, y su forma la acota además `gh_repo_create_denied`.
SUBCOMMAND_ALLOWED_ARGS = {
    ('gh', 'repo'): ('create',),
}

# Conjunto CERRADO de flags de `gh repo create`. Lo que se protege aquí es la inyección de flags: el
# nombre del repo y la visibilidad los decide el owner (ruling 2e), pero un `--template`, un
# `--clone` o un `--team` convertirían "crea mi repo vacío" en otra cosa distinta. Lo que no está en
# esta tupla deniega el segmento entero.
GH_REPO_CREATE_ALLOWED_FLAGS = (
    '--public', '--private', '--source', '--remote', '--push', '--description',
)

# De los anteriores, los que llevan valor: hay que consumirlo para no contarlo como el nombre del
# repo cuando vienen en su forma con espacio (`--source .`).
GH_REPO_CREATE_VALUE_FLAGS = ('--source', '--remote', '--description')


def load_allowlist():
    with open(ALLOWLIST_PATH) as f:
        return json.load(f)


def split_segments(command):
    """Divide `command` en &&, ||, ;, |, salto de línea y `&` simple, FUERA de comillas (estado de
    comilla char a char).

    C5 (fase 6, review adversarial): el salto de línea y el `&` simple (operador de fondo, no el
    `&&` de encadenado) faltaban en el conjunto de separadores — un comando benigno en una línea/
    antes del `&` ocultaba uno peligroso en la siguiente/después, porque el string entero se
    analizaba como UN solo segmento y el comando peligroso nunca se comprobaba por su cuenta
    (`git status\ngit push --force origin master`, `git status & git push --force origin master`).
    El chequeo de `&&`/`||` (2 caracteres) va SIEMPRE antes que el de `&` simple, así que un `&&`
    nunca se parte por la mitad.
    """
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
        if ch in (';', '|', '\n', '&'):
            segments.append(''.join(current))
            current = []
            i += 1
            continue
        current.append(ch)
        i += 1
    segments.append(''.join(current))
    return [s.strip() for s in segments if s.strip()]


def _find_command_substitutions(text):
    """Cuerpos de sustitución de comandos ($(...) balanceado en paréntesis, y `...`) que aparecen
    en `text`, en cualquier posición (dentro o fuera de comillas: en bash, `"$(...)"` SÍ se evalúa,
    así que ignorar el estado de comilla aquí solo puede llevar a comprobar un segmento de más —
    dirección segura — nunca a dejar de comprobar uno real).
    """
    bodies = []
    i = 0
    n = len(text)
    while i < n:
        if text[i:i + 2] == '$(':
            depth = 1
            j = i + 2
            while j < n and depth > 0:
                if text[j] == '(':
                    depth += 1
                elif text[j] == ')':
                    depth -= 1
                j += 1
            bodies.append(text[i + 2:j - 1] if depth == 0 else text[i + 2:j])
            i = j
            continue
        if text[i] == '`':
            j = text.find('`', i + 1)
            if j == -1:
                break
            bodies.append(text[i + 1:j])
            i = j + 1
            continue
        i += 1
    return bodies


def all_segments(command, _depth=0):
    """Todos los segmentos a comprobar: los de `split_segments`, más —recursivamente— el CUERPO de
    cualquier sustitución de comando ($(...) / backticks) que aparezca dentro de cada uno (C5).

    El guard no puede evaluar de forma segura qué produce una sustitución en tiempo de ejecución,
    así que trata su cuerpo como un comando más a validar — exactamente igual que si el agente lo
    hubiera escrito suelto. Esto es más preciso que denegar cualquier segmento que contenga
    `$(`/backtick a secas: preserva usos legítimos ya documentados como
    `cd "$(git rev-parse --show-toplevel)"` (agents/orchestrator.md §2.0) — el cuerpo,
    `git rev-parse --show-toplevel`, está en el allowlist — mientras deniega
    `git status $(git push --force origin master)`, cuyo cuerpo SÍ es un push destructivo, aunque
    el comando exterior (`git status`) sea inocuo por sí solo. Tope de profundidad como cinturón de
    seguridad ante una sustitución que se referenciase a sí misma.
    """
    if _depth > 8:
        return
    for segment in split_segments(command):
        yield segment
        for body in _find_command_substitutions(segment):
            if body.strip():
                for inner in all_segments(body, _depth + 1):
                    yield inner


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


def _push_dst(ref):
    """Destino REAL de un refspec de push: el `dst` de `src:dst`, o el propio ref si no hay `:`.

    `master`, `HEAD:master` y `refs/heads/master` son el mismo destino real; comprobar solo la
    palabra literal dejaría pasar las dos últimas formas. Ya no se recorta el prefijo `refs/heads/`
    aquí (C3): en vez de normalizar alias conocidos, `push_segment_denied` aplica una whitelist de
    FORMA — solo un nombre de rama LISO, sin ningún prefijo, es un destino válido — así que
    cualquier forma con prefijo (`refs/heads/…`, `heads/…`, `refs/tags/…`, `tags/…`) se deniega tal
    cual, sin necesidad de enumerar sus alias.
    """
    if ':' in ref:
        return ref.split(':', 1)[1]
    return ref


def _has_unresolvable_substitution(word):
    """C4 (fase 6, review adversarial): `$(...)`, backticks y `${...}` en un argumento posicional
    de push/remoto son sustituciones que el guard no puede resolver de forma estática — el shell
    real las evaluaría en tiempo de ejecución, así que el valor efectivo del destino/URL es
    desconocido en el momento en que este hook decide. El default seguro es denegar (mismo
    principio que el saneado de §5.0 del protocolo para texto ajeno en argumentos de shell: negar/
    denegar, nunca intentar resolver).
    """
    return '$(' in word or '`' in word or '${' in word


def push_segment_denied(words):
    """True si este `git push` cae fuera de la ÚNICA forma permitida.

    Forma permitida: `git push <remote> <rama>` — exactamente dos palabras posicionales tras
    `git push`, sin flag destructivo, sin `+` de force, y con destino que no sea rama protegida.
    """
    for word in words[2:]:
        if word.split('=', 1)[0] in PUSH_DENIED_FLAGS:
            return True
        # cluster de flags cortos: `-fu` lleva `-f` dentro (mismo bug-class que INTERP_DENIED_FLAGS)
        if re.match(r'^-[A-Za-z]+$', word) and not word.startswith('--'):
            if any(len(f) == 2 and f[1] in word[1:] for f in PUSH_DENIED_FLAGS):
                return True
    positional = [w for w in words[2:] if not w.startswith('-')]
    if len(positional) != 2:
        return True
    remote, ref = positional
    # C4: `$(...)`/backtick/`${...}` en el remoto o el refspec — sustitución que el guard no puede
    # resolver estáticamente. Se comprueba ANTES de todo lo demás: el valor real es desconocido.
    if _has_unresolvable_substitution(remote) or _has_unresolvable_substitution(ref):
        return True
    if ref.startswith('+'):
        return True
    # `:rama` — src vacío en un refspec `src:dst` — borra `rama` en el remoto. `_push_dst` por sí
    # sola no lo detecta (solo mira el `dst`), así que se comprueba el `src` aquí explícitamente.
    if ':' in ref and ref.split(':', 1)[0] == '':
        return True
    dst = _push_dst(ref)
    if not dst:
        return True
    if dst in PROTECTED_REFS:
        return True
    # C2: destino ambiguo (`HEAD`, `@`, y sus formas de historial `HEAD~N`/`HEAD^N`/`@{...}`) — no
    # dice a simple vista qué rama del remoto se toca. Solo un nombre de rama EXPLÍCITO vale.
    if dst in PUSH_AMBIGUOUS_DST or dst.startswith('HEAD~') or dst.startswith('HEAD^') or dst.startswith('@{'):
        return True
    # C3/I1: whitelist de forma — cualquier prefijo de ref (`refs/`, `heads/`, `tags/`) deniega,
    # sea o no protegido el nombre que lleve detrás (ver _push_dst).
    if any(dst.startswith(p) for p in PUSH_DENIED_DST_PREFIXES):
        return True
    return False


def subcommand_and_rest(words, value_flags=frozenset()):
    """(subcomando, resto) de un segmento `<cmd> <grupo> …`.

    El subcomando es la PRIMERA palabra con forma de subcomando tras el grupo, no `words[2]` a
    secas: con `words[2]` fijo, `git remote -v set-url origin <url>` colaría por delante de
    SUBCOMMAND_DENIED_ARGS (el tercer palabro sería `-v`) y `git remote -v` legítimo dejaría de
    funcionar si se denegara todo flag.

    `value_flags` (C1, fase 6 review): flags que TOMAN VALOR (`--repo`, `-R`, `--hostname`, `-h`
    de `gh`) — su valor se consume/salta y NUNCA se confunde con el subcomando. Sin esto,
    `gh pr --repo o/r merge 12` resolvía `sub='o/r'` (el valor del flag) y el subcomando real,
    `merge`, se colaba sin comprobar.

    El `resto` lleva TODO lo demás —flags anteriores al subcomando, sus valores, y cualquier
    palabra posterior—, para que los verificadores de forma no puedan saltarse nada por su
    posición.
    """
    sub = None
    rest = []
    skip_next = False
    for word in words[2:]:
        if skip_next:
            rest.append(word)
            skip_next = False
            continue
        bare = word.split('=', 1)[0]
        if bare in value_flags:
            rest.append(word)
            if '=' not in word:
                skip_next = True
            continue
        if sub is None and not word.startswith('-'):
            sub = word
        else:
            rest.append(word)
    return sub, rest


def command_shaped_words(words, value_flags=frozenset()):
    """Palabras de `words` con forma de nombre de subcomando: ni son flags, ni son el VALOR de un
    flag de `value_flags` que toma valor (`--repo o/r` → `o/r` no cuenta, aunque no empiece por
    `-`). Usado por C1 para escanear TODAS las posiciones en busca de un subcomando denegado, no
    solo la resuelta como `sub` — un subcomando denegado no tiene ningún motivo legítimo para
    aparecer en ningún otro sitio de estos segmentos.
    """
    result = []
    skip_next = False
    for word in words:
        if skip_next:
            skip_next = False
            continue
        bare = word.split('=', 1)[0]
        if bare in value_flags:
            if '=' not in word:
                skip_next = True
            continue
        if not word.startswith('-'):
            result.append(word)
    return result


def remote_add_segment_denied(rest):
    """True si este `git remote add` cae fuera de la ÚNICA forma permitida.

    Forma permitida: `git remote add <nombre> <url>` — exactamente dos palabras posicionales y CERO
    flags. `--mirror=push` convertiría el remoto en uno que BORRA ramas en cada push, y `-f`
    dispararía un fetch que nadie pidió: por eso no se permite ningún flag, no una lista de flags
    malos (fallar cerrado, igual que GH_REPO_CREATE_ALLOWED_FLAGS).
    """
    if any(w.startswith('-') for w in rest):
        return True
    if len(rest) != 2:
        return True
    # C4: `$(...)`/backtick/`${...}` en el nombre o la URL — sustitución no resoluble en estático.
    if any(_has_unresolvable_substitution(w) for w in rest):
        return True
    return False


def gh_repo_create_denied(rest):
    """True si este `gh repo create` cae fuera de la forma permitida.

    Forma permitida: exactamente UN posicional (el nombre `owner/repo` o `repo`) y flags
    únicamente del conjunto cerrado GH_REPO_CREATE_ALLOWED_FLAGS, en su forma `--flag`,
    `--flag=valor` o `--flag valor`. Se cuenta el posicional tras consumir el valor de los flags que
    lo llevan: sin eso, `--source .` metería `.` en la cuenta y la forma legítima se denegaría.
    """
    positional = []
    i = 0
    while i < len(rest):
        word = rest[i]
        if word.startswith('-'):
            name = word.split('=', 1)[0]
            if name not in GH_REPO_CREATE_ALLOWED_FLAGS:
                return True
            if name in GH_REPO_CREATE_VALUE_FLAGS and '=' not in word:
                i += 1  # consume el valor de la forma `--flag valor`
        else:
            positional.append(word)
        i += 1
    return len(positional) != 1


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
    if (
        len(words) >= 2
        and (command_word, words[1]) in BARE_TWO_WORD_DENIED
        and not any(not w.startswith('-') for w in words[2:])
    ):
        return False
    if len(words) >= 2 and (command_word, words[1]) == ('git', 'push'):
        if push_segment_denied(words):
            return False
    if len(words) >= 2:
        group = (command_word, words[1])
        allowed_sub = SUBCOMMAND_ALLOWED_ARGS.get(group)
        denied_sub = SUBCOMMAND_DENIED_ARGS.get(group)
        if allowed_sub is not None or denied_sub is not None:
            # C1: flags de `gh` que toman valor (`--repo o/r`, `-h github.com`…) se consumen antes
            # de resolver el subcomando o escanear en busca de uno denegado — su valor nunca se
            # confunde con un nombre de subcomando.
            value_flags = GH_VALUE_TAKING_FLAGS if command_word == 'gh' else frozenset()
            sub, rest = subcommand_and_rest(words, value_flags)
            if allowed_sub is not None and sub not in allowed_sub:
                return False  # `gh repo` a secas, o con un subcomando que no sea `create`
            if denied_sub is not None:
                # C1: se escanea CUALQUIER posición, no solo la resuelta como `sub` — un flag de
                # valor colocado antes (`gh pr --repo o/r merge 12`) no debe esconder el subcomando
                # real detrás de él.
                shaped = command_shaped_words(words[2:], value_flags)
                if any(w in denied_sub for w in shaped):
                    return False
            if group == ('git', 'remote') and sub == 'add':
                if remote_add_segment_denied(rest):
                    return False
            if group == ('gh', 'repo') and sub == 'create':
                if gh_repo_create_denied(rest):
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

    for segment in all_segments(command):
        if not segment_allowed(segment, agent_allowlist):
            deny('%s no está en el allowlist de %s' % (segment, agent_type))
            return

    sys.exit(0)


if __name__ == '__main__':
    main()
