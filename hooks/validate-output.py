#!/usr/bin/env python3
"""hooks/validate-output.py — SubagentStop hook: valida el contrato de evidencia swarm (spec §6.1).

Contrato de stdin (JSON, campo real de la plataforma — verificado empíricamente, ver C1):
  {"agent_type": "swarm:<name>", "last_assistant_message": "<texto completo del subagente>"}

Comportamiento:
  - agent_type que no empieza por "swarm:" -> exit 0, sin salida (no es de nuestra incumbencia).
  - línea 1 debe ser un veredicto: OK | KO <motivo> | DONE | BLOCKED <motivo>.
  - línea 2 debe ser `evidence: files=N cmds=M turns=k/max` (tolerante a espacios).
  - OK con files=0 se rechaza (verdicto verde sin evidencia real).
  - narración (prosa larga en vez del formato de hallazgo) se rechaza.
  - si turns >= max: NO es un bloqueo; se emite un systemMessage y se sale con 0.
  - stop_hook_active=true (la plataforma ya está reintentando este mismo Stop) -> exit 0, no
    volvemos a evaluar nada (evita amplificar el propio bloqueo del hook en un bucle).
  - un rechazo se reintenta como máximo una vez (contador en
    run/<run>/retries/<agente>-<hash(motivo)>, es decir por agente + motivo concreto de
    fallo -- dos motivos distintos del mismo agente son cada uno una "primera falta"); al
    SEGUNDO rechazo por el MISMO motivo del mismo agente en el mismo run, se acepta como
    BLOCKED (con systemMessage) en vez de rechazar de nuevo -- nunca bucle infinito.
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

# Formato de batch de discovery-orchestrator (spec §7, agents/discovery-orchestrator.md
# "## Salida"): una pregunta con hasta 4 opciones (≤8 palabras cada una) más recomendación
# supera con normalidad los 120 chars del cap de narración — confirmado en vivo con líneas
# reales de 184-212 chars, que el cap uniforme rechazaba como "narración detectada" (C1 de la
# review final de fase 2, 2026-09-02). Estructuralmente NO es prosa suelta: es un formato fijo
# y parseable (cabecera + pregunta + opciones A-D + rec), así que se exime del cap por FORMA,
# no por venir con un "- " delante — cualquier otra línea "- " sigue sujeta a los 120 (ese era
# el bug real original: narración colándose sin ningún tope).
DISCOVERY_Q_RE = re.compile(r'^- Q\d+ \[[^\]]{1,12}\] .+ · [A-D]\) .+ · rec: [A-D]$')
# DISCOVERY_OTHER_RE también cubre el vocabulario fijo de analysis-orchestrator (spec §7
# "Análisis", agents/analysis-orchestrator.md "## Salida"): `- lentes: <n1>, <n2>, ..., motivo:
# <objetivo casó con "...">` enumera hasta 6 lentes con nombres largos (`vulnerability-scanner`,
# `architecture-auditor`...) y supera con normalidad los 120 chars cuando casan varias — mismo
# bug de fondo que C1, confirmado en vivo con líneas de hasta 174 chars. `- sin hallazgos: <hoja>
# no encontró...` (OK con cero hallazgos) es corta por construcción, pero es el mismo vocabulario
# fijo por FORMA, no por "- " — se incluye aquí por localidad.
DISCOVERY_OTHER_RE = re.compile(r'^- (warn|findings|lentes|sin hallazgos): .+$')
# Las otras dos líneas fijas de analysis-orchestrator llevan un prefijo DINÁMICO (el número de
# hallazgos truncados, el nombre de la hoja) y no caben en el `(a|b|c):` de arriba, así que van en
# regexes aparte, cada una anclada a su forma exacta documentada en "## Espera y fusión" puntos 3
# y 4 de agents/analysis-orchestrator.md — siguen siendo exenciones por FORMA, no por "- ":
# `- N hallazgos adicionales en .swarm/findings/<hoja>.md` (cap de 20 líneas fusionadas) y
# `- <hoja> BLOCKED: <motivo>` (hoja bloqueada, propagada sin descartar).
ANALYSIS_ADDITIONAL_RE = re.compile(r'^- \d+ hallazgos adicionales en \.swarm/findings/\S+\.md$')
ANALYSIS_LEAF_BLOCKED_RE = re.compile(r'^- [a-z][a-z0-9-]* BLOCKED: .+$')


def _repo_root():
    """Raíz real del repo, NO el cwd del hook.

    El hook corre en el cwd de la SESIÓN: si el usuario abrió Claude Code desde un
    subdirectorio (`packages/api` en un monorepo), `os.getcwd()` apunta al sitio equivocado —
    y el `cd "$(git rev-parse --show-toplevel)"` que hace el orquestador dentro de SUS llamadas
    a Bash no cambia el cwd de ESTE proceso. Misma técnica que el orquestador (agents/
    orchestrator.md §2.0). Si no es un repo git, se cae al cwd como antes.
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
    # Un hook NUNCA origina un `.swarm/`: solo `/swarm:init` crea ese árbol. Si la raíz
    # resuelta no existe, el contador de reintentos se pierde (el rechazo se emite igual)
    # antes que sembrar un `.swarm/` fantasma en un directorio equivocado.
    if not os.path.isdir(swarm_root):
        return
    # El contador es best-effort: si el directorio de retries no es escribible (permisos,
    # carrera con otro proceso), el rechazo se emite igual — un fallo aquí no debe tumbar
    # el hook entero (que la plataforma trataría como fail-open, dejando pasar cualquier cosa).
    try:
        os.makedirs(retries_dir, exist_ok=True)
        with open(path, 'w') as f:
            f.write(str(count + 1))
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

    # La plataforma reinvoca este hook cuando SU PROPIO bloqueo anterior ya disparó un
    # reintento (campo estándar de los hooks Stop/SubagentStop) — si no lo respetamos podemos
    # amplificar el propio bloqueo del hook en un bucle, por encima del contador de reintentos
    # que llevamos nosotros mismos más abajo.
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

    if not VERDICT_RE.match(verdict_line):
        reason = 'línea 1 debe ser un veredicto: OK | KO <motivo> | DONE | BLOCKED <motivo>'

    evidence_match = None
    if reason is None:
        evidence_match = EVIDENCE_RE.match(evidence_line)
        if not evidence_match:
            reason = 'línea 2 obligatoria: evidence: files=N cmds=M turns=k/max'

    turns_k = turns_max = None
    if reason is None:
        files_n = int(evidence_match.group(1))
        turns_k = int(evidence_match.group(3))
        turns_max = int(evidence_match.group(4))

        if verdict_line == 'OK' and files_n == 0:
            reason = 'OK con files=0 — verdict verde sin evidencia real'

        if reason is None:
            for line in lines[2:]:
                stripped = line.strip()
                if not stripped:
                    continue
                if FINDING_RE.match(stripped):
                    continue
                # Formato de batch de discovery-orchestrator y de analysis-orchestrator: exentos
                # del cap de longitud por FORMA (regex estructural), nunca solo por empezar con
                # "- " — ver comentarios junto a DISCOVERY_Q_RE / DISCOVERY_OTHER_RE /
                # ANALYSIS_ADDITIONAL_RE / ANALYSIS_LEAF_BLOCKED_RE arriba.
                if (
                    DISCOVERY_Q_RE.match(stripped)
                    or DISCOVERY_OTHER_RE.match(stripped)
                    or ANALYSIS_ADDITIONAL_RE.match(stripped)
                    or ANALYSIS_LEAF_BLOCKED_RE.match(stripped)
                ):
                    continue
                # Cualquier OTRA línea "- " (no reconocida por el formato de batch) sigue
                # sujeta al tope: sin esto, prosa cualquiera se cuela con solo anteponerle
                # "- " (bug real, sin tope alguno, ya arreglado antes — no reabrirlo).
                if stripped.startswith('- ') and len(stripped) <= MAX_FINDING_LINE_LEN:
                    continue
                if len(stripped) > MAX_FINDING_LINE_LEN:
                    reason = 'narración detectada fuera del formato TAG · file:línea · problema → fix'
                    break

    if reason is None:
        if turns_k is not None and turns_max and turns_k >= turns_max:
            _system_message(
                'swarm: %s alcanzó maxTurns → tratar como BLOCKED maxTurns' % agent_type
            )
        sys.exit(0)

    retry_key = _retry_key(agent_type, reason)
    retry_count, retry_path, retries_dir = _retry_count(swarm_root, run_id, retry_key)

    if retry_count >= 1:
        _system_message(
            'swarm: %s falló la validación dos veces (%s) → aceptado como BLOCKED' % (agent_type, reason)
        )

    _bump_retry(swarm_root, retry_path, retries_dir, retry_count)
    _block(reason)


if __name__ == '__main__':
    main()
