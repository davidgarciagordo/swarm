# Plan Fase 1 — Núcleo del plugin `swarm`

Fecha: 2026-09-01 · Estado: aprobado por memoria (obs 53484), reconstruido tras pérdida por cuota · Spec: `docs/superpowers/specs/2026-09-01-swarm-design.md` §15.1

## Alcance (spec §15 fase 1)

`orchestrator`, subsistema memoria (3 agentes + backends files/claude-mem), `swarm-protocol`,
hooks (evidencia + bash-allowlist), `/swarm:init`, smoke tests 1–8.

## Restricciones de implementación (macOS-portables)

1. **Lock atómico `mkdir`, NO `flock`** (ausente en macOS bash 3.2): spin `mkdir "$SWARM_ROOT/.lock.d"` con sleep 50ms y timeout 10s.
2. **Sin `jq`**: todo JSON con `python3` stdlib (json module).
3. **Formato de salida de hooks** (verificado):
   - `SubagentStop` bloquea imprimiendo `{"decision":"block","reason":"<msg>"}` a stdout + **exit 0** (NO exit 2 como se asumía).
   - `PreToolUse` deniega imprimiendo `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<msg>"}}` a stdout + exit 0.
4. Hooks en **Python 3**: `hooks/validate-output.py` (SubagentStop) y `hooks/bash-guard.py` (PreToolUse).
5. **Test framework: bash plano, sin framework.** `tests/lib.sh` aporta `make_fixture`, `assert_eq`, `assert_file_contains`, `assert_exit`.
6. Nombres de agentes planos en `agents/` → registran como `swarm:<nombre>` (§3.1).

## Tasks

Orden TDD: test primero (RED) → implementar (GREEN) → refactor → commit.

### T1 — Scaffold
- Modelo: **haiku**
- Crea estructura: `.claude-plugin/plugin.json` (`name: swarm`, `version: 0.1.0`, `"skills": "./skills/"`, `"commands": ["./commands/init.md","./commands/run.md"]`; `agents/` y `hooks/hooks.json` auto-descubiertos), `agents/`, `commands/`, `skills/`, `scripts/`, `hooks/`, `tests/`.
- Test: existe `plugin.json` con keys correctas.

### T2 — Lock + backend `files` (`scripts/mem-files.sh`)
- Modelo: **sonnet**
- `mem-files.sh`: lock `mkdir .lock.d` spin, queries `files`, write con dedup.
- Test: lock serializa dos escrituras concurrentes; write duplicado → una entrada.

### T3 — Staleness tree-state hash (`scripts/mem-stale.sh`)
- Modelo: **sonnet**
- sha de (`git rev-parse HEAD:` + `git status --porcelain` + mtimes de dirs cubiertos) vs sello en `index.md`.
- Test: cambio sin commitear → hash cambia → stale → reconstruye.

### T4 — Manifest per-agente (`scripts/mem-manifest.sh`)
- Modelo: **sonnet**
- `run/<id>/agents/<nombre>.json`, append-only, nunca global sobrescribible.
- Test: dos escrituras mismos agentes → ambos manifest intactos, sin sobrescritura.

### T5 — Hook evidencia `hooks/validate-output.py` (SubagentStop)
- Modelo: **sonnet**
- Valida línea 2 `evidence: files=N cmds=M turns=k/max`; rechaza `OK` con `files=0`; rechaza narración; `turns==max` → reescribe a `BLOCKED maxTurns`; reintento máx 1 (contador `run/<id>/retries/<agente>`); 2º fallo → acepta como `BLOCKED`.
- Bloqueo por stdout `{"decision":"block",...}` + exit 0.
- Test: sin `evidence:` → block; `OK files=0` → block.

### T6 — Hook `hooks/bash-guard.py` (PreToolUse)
- Modelo: **sonnet**
- Allowlist de prefijos Bash keyed por `agent_type`, en `hooks/bash-allowlist.json`.
- Prefijos por defecto: `git status`, `git log`, `git diff`, `git show`, `git rev-parse`, `ls`, `cat`, `head`, `tail`, `wc`, `grep`, `find`, `uuidgen`, `python3 "${CLAUDE_PLUGIN_ROOT}"`, `scripts/mem-`.
- Denegación por stdout `{"hookSpecificOutput":{...}}` + exit 0.
- Test: prefijo permitido pasa; comando fuera de allowlist → deny.

### T7 — Skill `swarm-protocol` (contrato universal §6)
- Modelo: **opus** (contrato central del plugin)
- Contrato: leer context-pack antes de buscar; no re-reportar findings/SHARED-FOUND; evidencia obligatoria (veredicto + `evidence:` + hallazgos `TAG · file:línea · problema → fix`); tool determinista primero; parar por saturación; frontmatter obligatorio.
- Precargado en todos los agentes.
- Test: fixture hoja produce salida conforme al formato.

### T8 — Comando `/swarm:init`
- Modelo: **sonnet**
- Crea `.swarm/`, `memory.json` por defecto, entradas `.gitignore` (`context-pack.md`, `index.md`, `findings/`, `run/`, `.lock`), esqueleto `decisions.md`.
- Backend `files` health-gated: health falla → init aborta (spec §4.6).
- Test: init crea `.swarm/` + gitignore; backend down → abort.

### T9 — `scripts/mem-scan.sh` / detección stack
- Modelo: **sonnet**
- Detecta stack por tabla precedencia (§8.1): `composer.json` con `symfony/*` → `php-ddd-symfony8`; fallback `generic` + warning. Escribe `stack:` en `context-pack.md`.
- Test: fixture symfony → `php-ddd-symfony8`; sin marcadores → `generic`.

### T10 — Agentes memoria + `scripts/mem-curate.sh`
- Modelo: **opus** (prompts de los 3 agentes) + **sonnet** (mem-curate.sh)
- `memory-orchestrator` (haiku, instancia única por run), `memory-builder` (sonnet), `memory-curator` (haiku).
- `mem-curate.sh`: compacta findings, poda decisions, MEMORY.md ≤25KB, staleness, GC `run/` (10 últimos).
- Test: run → builder crea context-pack; curate compacta y poda.

### T11 — Agente `orchestrator` + comando `/swarm:run`
- Modelo: **opus**
- Raíz: clasifica tier (`direct`/`light`/`full`), exige pack, lanza `memory-orchestrator` NOMBRADO (único por run), presenta discovery con `AskUserQuestion`.
- Pack lazy: nunca antes de clasificar; `direct` nunca construye pack.
- `/swarm:run` invoca orchestrator.
- Test: trivial → `direct` sin lanzar dominios.

### T12 — Smoke checklist (owner gate, no automatizado)
- Modelo: **sesión real del owner**
- Ejecutar manualmente smoke tests 1–8 del spec §14 contra fixture y firmar.

## Confirma / avanza

- Cada task = 1 commit, aprobación del owner entre agentes (norma de David: agente por agente, commit por agente).
- Modelos de ejecución: Fable/Opus solo para diseño y revisión; Sonnet para agentes/scripts; Haiku scaffolding.
