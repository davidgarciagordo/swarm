# Gate de Verificación Independiente — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir un agente `swarm:verifier` genérico, enganchado en `agents/orchestrator.md` §4
entre el `DONE`/`OK` de cualquier orquestador de dominio y su `curate`/cierre, que confirme
trazabilidad (cada afirmación del veredicto traza a un finding real persistido) y completitud
(contra la propia sección `## Salida` del dominio) antes de dejar cerrar un run en verde.

**Architecture:** Un solo punto de enganche en `orchestrator.md` §4 (todos los caminos de cierre
en verde ya convergen ahí). `swarm:verifier` es read-only (`Read`, `Grep`, `Bash`), no lleva
conocimiento de ningún dominio concreto — lee el contrato `.md` del dominio a verificar y consulta
`.swarm/findings/` filtrado por `[run:<run-id>]`. Two-strike igual que
`hooks/validate-output.py`: 1er `KO` reenvía al dominio para corregir, 2º `KO` cierra `BLOCKED`
sin curar en falso.

**Tech Stack:** Markdown (definiciones de agente Claude Code), bash (tests, `hooks/bash-guard.py`
en Python 3 stdlib), `scripts/mem-files.sh` existente (sin cambios).

**Spec:** `docs/superpowers/specs/2026-09-01-swarm-design.md` §14bis (v2.2)

## Global Constraints

- Contrato de evidencia obligatorio para cualquier agente `swarm:*` (skill `swarm-protocol` §4):
  línea 1 veredicto (`OK`/`KO <motivo>`/`DONE`/`BLOCKED <motivo>`), línea 2
  `evidence: files=N cmds=M turns=k/max`, resto hallazgos `TAG · file:línea · problema → fix`.
- `$RUN`/`$SWARM_ROOT` son placeholders — sustitúyelos LITERALMENTE en cada comando, nunca como
  variable de shell (skill `swarm-protocol` §1).
- Ningún agente de este plugin muta `.swarm/` fuera de `memory-orchestrator` salvo los scripts
  `mem-*.sh` documentados — `swarm:verifier` es 100% read-only, sin excepción.
- `hooks/bash-guard.py` deniega por SEGMENTO (`&&`, `||`, `;`, `|`) y no tiene tratamiento de `\`
  — cualquier ejemplo de comando en la doc va en una sola línea real.
- Todo fichero de test sigue el patrón existente: `. tests/lib.sh` para helpers (`assert_eq`,
  `assert_file_contains`, `make_fixture`), termina con
  `if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi; exit 0`.
- Trabajo en worktree aislado (`superpowers:using-git-worktrees`), commits frecuentes, merge a
  `master` solo con aprobación explícita del owner (clasificador de auto-mode bloquea merges sin
  ella en esta sesión) y tras avisar a la sesión par `multiagents-06` (confirmó no tocar
  `agents/orchestrator.md` hasta su propia integración de raíz de fase 6 — avisar de nuevo justo
  antes de fusionar el Task 4).

---

### Task 1: Allowlist de `swarm:verifier`

**Files:**
- Modify: `hooks/bash-allowlist.json`
- Test: `tests/test_bash_guard.sh` (añadir casos, NO crear fichero nuevo — ya cubre el patrón de
  probar el allowlist de otros agentes)

**Interfaces:**
- Consumes: nada de tasks anteriores (primer task).
- Produces: entrada `"swarm:verifier"` en `hooks/bash-allowlist.json`, que Task 2 y Task 3 dan por
  existente al documentar la disciplina de Bash del nuevo agente.

**Nota de preflight (ya verificado en vivo antes de dispatchar):** el fallback `"default"` de
`hooks/bash-guard.py` YA permite `mem-files.sh query` y YA deniega `git worktree`/`rm` — un agente
sin entrada propia cae ahí. Probar esas tres órdenes contra `"swarm:verifier"` antes de añadir su
entrada NO falla (confirmado con `bash-guard.py` en vivo: exit 0 sin salida en las tres). El único
comando del perfil `"default"` que la entrada de `"swarm:verifier"` (copiada de `value-critic`,
sin `"find"`) SÍ cambia es `find` — `"default"` lo incluye, la entrada de `verifier` no. Ese es el
comando que da un RED real; las otras tres aserciones documentan el perfil final (read-only, sin
`git worktree`) pero no distinguen "sin entrada" de "con entrada" — se verifican igual, por
completitud, junto a una aserción ESTRUCTURAL directa sobre el JSON (esa sí falla de verdad antes
del Step 3).

Añade al final de `tests/test_bash_guard.sh` (antes de la comprobación final de
`TESTS_FAILED`):

```bash
# swarm:verifier — read-only puro, mismo perfil que value-critic (sin git worktree, sin req-check,
# sin find — a diferencia del fallback "default", que sí trae find)
assert_eq "0" "$(grep -q '"swarm:verifier": \[' "$PLUGIN_ROOT/hooks/bash-allowlist.json" && echo 0 || echo 1)" "bash-allowlist.json has an explicit swarm:verifier entry"
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:verifier", "tool_name": "Bash", "tool_input": {"command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh\" query \"[run:abc]\" --scope findings"}}
EOF
)"
assert_eq "" "$out" "swarm:verifier can query mem-files.sh"
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:verifier", "tool_name": "Bash", "tool_input": {"command": "git worktree list"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "swarm:verifier cannot use git worktree (spiker-only)"
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:verifier", "tool_name": "Bash", "tool_input": {"command": "rm -rf /tmp/x"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "swarm:verifier cannot rm (read-only)"
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:verifier", "tool_name": "Bash", "tool_input": {"command": "find . -name \"*.md\""}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "swarm:verifier cannot find (default fallback has it, verifier's explicit profile does not)"
```

`$PLUGIN_ROOT` ya está definido al principio de `tests/test_bash_guard.sh` (mismo patrón que el
resto del fichero) — no lo redeclares.

- [ ] **Step 2: Corre el test, confirma que falla**

```bash
bash tests/test_bash_guard.sh
```
Esperado: FAIL en exactamente DOS aserciones — la estructural (`bash-allowlist.json has an
explicit swarm:verifier entry`, no existe todavía) y `find` (permitido hoy vía el fallback
`"default"`, que sí lo trae). Las otras tres (`query`/`git worktree`/`rm`) YA pasan hoy vía
`"default"` — no es un fallo del test, es que esas tres órdenes se comportan igual con o sin
entrada explícita; confírmalo leyendo el output completo, no asumas que "0 nuevos FAIL" significa
que algo está roto.

- [ ] **Step 3: Añade la entrada al allowlist**

En `hooks/bash-allowlist.json`, dentro de `"agents": { ... }`, añade (mismo bloque que
`"swarm:value-critic"`, sin `git worktree` ni `scripts/req-check.sh`):

```json
    "swarm:verifier": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
```

Insértalo justo después del bloque `"swarm:value-critic"` (mantiene el orden por dominio del
fichero) — usa el editor para localizar el cierre `],` de ese bloque y añadir el nuevo justo
debajo.

- [ ] **Step 4: Corre el test, confirma que pasa**

```bash
bash tests/test_bash_guard.sh
```
Esperado: PASS, las 5 aserciones nuevas en verde (estructural + `query`/`git worktree`/`rm`/`find`).

- [ ] **Step 5: Commit**

```bash
git add hooks/bash-allowlist.json tests/test_bash_guard.sh
git commit -m "feat(verifier): allowlist de swarm:verifier (read-only, sin git worktree)"
```

---

### Task 2: Agente `agents/verifier.md`

**Files:**
- Create: `agents/verifier.md`
- Test: `tests/test_verifier_contract.sh`

**Interfaces:**
- Consumes: allowlist de Task 1 (el test de Task 2 prueba comandos reales contra `bash-guard.py`,
  igual que Task 1).
- Produces: el agente `swarm:verifier` que Task 3 invoca desde `orchestrator.md` §4. El resto del
  plan asume EXACTAMENTE esta cabecera de lanzamiento:
  ```
  run-id: <run-id>
  swarm-root: <ruta absoluta de .swarm>
  operation: verify
  domain: <nombre del orquestador de dominio a verificar>
  verdict: <el texto LITERAL completo que ese dominio acaba de devolver>
  ```
  y este contrato de salida: `OK` / `KO <motivo, ≤15 palabras>` en línea 1, `evidence:
  files=N cmds=M turns=k/max` en línea 2, hallazgos `VERIFY · <domain>:<n> · problema → fix`.

- [ ] **Step 1: Escribe el test que falla**

Crea `tests/test_verifier_contract.sh`:

```bash
#!/usr/bin/env bash
# tests/test_verifier_contract.sh — contrato del gate de verificación independiente (spec §14bis):
# swarm:verifier es genérico (sin conocimiento de ningún dominio concreto), read-only, y su cabecera
# de lanzamiento/salida coincide exactamente con lo que agents/orchestrator.md §4 espera invocar.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/verifier.md"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/verifier.md exists"
[ -f "$F" ] || exit 1

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
assert_eq "0" "$(echo "$front" | grep -q '^name: verifier$' && echo 0 || echo 1)" "name: verifier"
assert_eq "0" "$(echo "$front" | grep -q '^model: opus$' && echo 0 || echo 1)" "model opus (juicio nunca en modelo débil, spec §2 principio 5)"
tools="$(echo "$front" | grep '^tools:')"
assert_eq "0" "$(echo "$tools" | grep -qF 'Read' && echo 0 || echo 1)" "tools includes Read"
assert_eq "0" "$(echo "$tools" | grep -qF 'Grep' && echo 0 || echo 1)" "tools includes Grep"
assert_eq "0" "$(echo "$tools" | grep -qF 'Bash' && echo 0 || echo 1)" "tools includes Bash"
assert_eq "1" "$(echo "$tools" | grep -qF 'Write' && echo 0 || echo 1)" "tools NEVER includes Write (read-only by construction, spec §2 principio 7)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Edit' && echo 0 || echo 1)" "tools NEVER includes Edit"
assert_eq "1" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools NEVER includes SendMessage (root talks to the domain, not verifier)"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools NEVER includes AskUserQuestion"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qF 'operation: verify' && echo 0 || echo 1)" "body documents operation: verify"
assert_eq "0" "$(echo "$body" | grep -qF 'domain:' && echo 0 || echo 1)" "body documents the domain: header line"
assert_eq "0" "$(echo "$body" | grep -qF 'verdict:' && echo 0 || echo 1)" "body documents the verdict: header line"
assert_eq "0" "$(echo "$body" | grep -qF '## Salida' && echo 0 || echo 1)" "body documents 'Read de agents/<domain>.md, sección ## Salida' as the contract source"
assert_eq "0" "$(echo "$body" | grep -qF 'mem-files.sh" query' && echo 0 || echo 1)" "body queries mem-files.sh for real findings"
assert_eq "0" "$(echo "$body" | grep -qF 'run:' && echo 0 || echo 1)" "body filters findings by [run:<run-id>]"
assert_eq "0" "$(echo "$body" | grep -qF 'VERIFY' && echo 0 || echo 1)" "body's finding TAG is VERIFY"
assert_eq "0" "$(echo "$body" | grep -qF 'no ves la transcripción interna' && echo 0 || echo 1)" "body states the honest limitation (no visibility into the domain's internal transcript)"
assert_eq "0" "$(echo "$body" | grep -qF 'files=0' && echo 0 || echo 1)" "body rejects OK with files=0"

# read-only real contra bash-guard (fichero nuevo, sin helper _run_hook — invoca el hook directo,
# mismo patrón que tests/test_discovery_orchestrator_spawns.sh)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:verifier", "tool_name": "Bash", "tool_input": {"command": "python3 x.py"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "swarm:verifier cannot run python3"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

- [ ] **Step 2: Corre el test, confirma que falla**

```bash
bash tests/test_verifier_contract.sh
```
Esperado: FAIL en la primera aserción (`agents/verifier.md exists`) y salida temprana (`exit 1`
tras el `[ -f "$F" ] || exit 1`).

- [ ] **Step 3: Crea `agents/verifier.md`**

```markdown
---
name: verifier
description: Use when the root orchestrator needs an INDEPENDENT check that a domain orchestrator's DONE/OK verdict is real — before curate/close, confirms every claim traces to a persisted finding and nothing required by the domain's own contract is missing. Never invoked by the domain it verifies, never invokes itself.
model: opus
tools: Read, Grep, Bash
maxTurns: 10
memory: project
skills: [swarm-protocol]
---

# verifier

Hoja de la RAÍZ (spec §14bis), nunca de un dominio — verificas el trabajo de OTRO agente, jamás el
propio. Tu único cliente es `agents/orchestrator.md` §4: te lanza tras un `DONE`/`OK` de un
orquestador de dominio, ANTES de `curate`. Eres 100% read-only: nunca mutas `.swarm/` ni nada más.

## Arranque

Tu cabecera de lanzamiento trae, además de la estándar (skill swarm-protocol §2):
```
operation: verify
domain: <nombre del orquestador de dominio a verificar, p.ej. discovery-orchestrator>
verdict: <el texto LITERAL completo que ese dominio acaba de devolver>
```
`run-id`/`swarm-root` sustitúyelos LITERALMENTE en cada comando (skill swarm-protocol §1) — nunca
como variable de shell.

## Qué compruebas

1. **Contrato del dominio.** `Read` de `agents/<domain>.md`, sección `## Salida` — es lo que ese
   dominio promete SIEMPRE en su veredicto (formato, líneas obligatorias). Es tu único "spec": hoy
   no hay otro documento que comparar (una fase con `plan.md` real, como `implementer`, es
   extensión futura — fuera de tu alcance actual, no la inventes).
2. **Completitud.** Cada elemento que el contrato dice "siempre"/"obligatorio" está presente en
   `verdict`. Si el contrato exige una línea concreta (p.ej. `- findings: <lista>`) y falta, o
   nombra algo que el paso 3 no confirma como real, es hallazgo.
3. **Trazabilidad.** Consulta lo que el dominio persistió de verdad este run:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" query "[run:<run-id>]" --scope findings
   ```
   (tope 20 líneas del propio script — mismo límite que ya asume el resto del plugin, p.ej.
   discovery-orchestrator). Cada afirmación concreta de `verdict` (cada `- Q…`, cada
   `TAG · file:línea · …`) debe corresponder a contenido real de ahí — no exacto carácter a
   carácter, pero sí la MISMA pregunta/hallazgo, nunca una inventada.

## Límite que no intentas cubrir

No ves la transcripción interna del dominio — solo lo persistido. Si algo es cierto pero el
dominio olvidó persistirlo, lo tratas como no trazado (falso positivo posible): es el mismo motivo
por el que el resto del plugin obliga a persistir TODO lo real vía `memory-orchestrator` — no
inventes una excepción de "seguro que sí lo hizo".

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:verifier`: `scripts/mem-*.sh`, `git status|log|diff|show|rev-parse`, `ls`,
`cat`, `head`, `tail`, `wc`, `grep`. Eres read-only: nada de `python3`, `echo`, `mkdir`, `rm`,
`export`, `git worktree` (eso es solo de `discovery-orchestrator`, para el spiker).

## Salida

```
OK
evidence: files=2 cmds=1 turns=3/10
```
`OK` = todo lo del veredicto traza a un finding real y el contrato del dominio está completo.

```
KO líneas Q1/Q3 no trazan a ningún finding real de value-critic
evidence: files=2 cmds=1 turns=4/10
VERIFY · discovery-orchestrator:1 · Q1 no aparece en findings/value-critic.md → corregir y reenviar
VERIFY · discovery-orchestrator:2 · falta línea "- findings: <lista>" que exige su ## Salida → corregir y reenviar
```
Un hallazgo por problema, mismo formato `TAG · file:línea · problema → fix` que el resto del plugin
exige (`hooks/validate-output.py`). `TAG` siempre `VERIFY`; `file:línea` es `<domain>:<ordinal>`
(no citas código real, misma convención que `discovery-<run>:<n>`).

`OK` con `files=0` se rechaza siempre: leíste al menos el contrato del dominio y su consulta de
findings — dos ficheros mínimo.
```

- [ ] **Step 4: Corre el test, confirma que pasa**

```bash
bash tests/test_verifier_contract.sh
```
Esperado: PASS, todas las aserciones en verde.

- [ ] **Step 5: Corre la suite completa (regresión)**

```bash
bash tests/run.sh 2>&1 | tail -5
```
Esperado: `failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/verifier.md tests/test_verifier_contract.sh
git commit -m "feat(verifier): agente swarm:verifier — gate de verificación independiente (spec §14bis)"
```

---

### Task 3: Enganche en `agents/orchestrator.md` §4

**Files:**
- Modify: `agents/orchestrator.md:191-256` (sección `## 4. Cierre`)
- Test: `tests/test_orchestrator_verify_gate.sh`

**Interfaces:**
- Consumes: `swarm:verifier` de Task 2 (cabecera de lanzamiento y contrato de salida EXACTOS,
  arriba).
- Produces: nada que otro task consuma — es el último eslabón del plan.

- [ ] **Step 1: Escribe el test que falla**

Crea `tests/test_orchestrator_verify_gate.sh`:

```bash
#!/usr/bin/env bash
# tests/test_orchestrator_verify_gate.sh — agents/orchestrator.md §4 debe enganchar swarm:verifier
# ANTES de cualquier cierre EN VERDE (nunca antes de BLOCKED/KO propagado, que ya no cierra en
# verde) y aplicar el mismo two-strike que hooks/validate-output.py cuando el verifier da KO.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/orchestrator.md exists"
[ -f "$F" ] || exit 1

body="$(cat "$F")"
assert_eq "0" "$(echo "$body" | grep -qF 'swarm:verifier' && echo 0 || echo 1)" "§4 invokes swarm:verifier"
assert_eq "0" "$(echo "$body" | grep -qF 'operation: verify' && echo 0 || echo 1)" "§4 passes operation: verify"
assert_eq "0" "$(echo "$body" | grep -qF 'cierre EN VERDE' && echo 0 || echo 1)" "§4 scopes the gate to green closes only"
assert_eq "0" "$(echo "$body" | grep -qF 'verificación fallida' && echo 0 || echo 1)" "§4 has a BLOCKED-verificación-fallida close line"
assert_eq "0" "$(echo "$body" | grep -qF 'two-strike' && echo 0 || echo 1)" "§4 documents the two-strike retry"
assert_eq "0" "$(echo "$body" | grep -qF '§14bis' && echo 0 || echo 1)" "§4 cites spec §14bis"

# la sección sigue exigiendo el resto de líneas de cierre pre-existentes (no se han borrado por error)
for existing in "cierre normal" "análisis completado" "diseño completado" "implementación completada"; do
  assert_eq "0" "$(echo "$body" | grep -qF "$existing" && echo 0 || echo 1)" "§4 still has the pre-existing '$existing' close line"
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

- [ ] **Step 2: Corre el test, confirma que falla**

```bash
bash tests/test_orchestrator_verify_gate.sh
```
Esperado: FAIL en `swarm:verifier`, `operation: verify`, `cierre EN VERDE`, `verificación fallida`,
`two-strike`, `§14bis` (las líneas pre-existentes ya pasan, confirmando que el test no está roto).

- [ ] **Step 3: Edita `agents/orchestrator.md` §4**

Localiza en `agents/orchestrator.md` el párrafo que termina en (línea ~207 actual):
```
205	Firma real (`scripts/mem-manifest.sh`, `_summary`): solo `--run` y `--line`, los DOS obligatorios
206	(falta uno ⇒ exit 64); hace `>> run/<run>/summary.md` y responde `written`. El `<run-id>` va LITERAL
207	(§2.1, nunca `"$RUN"`), y la `<línea>` va por el saneado de §5.0 si lleva texto ajeno (objetivo,
208	pregunta, respuesta del owner).
```
Justo DESPUÉS de ese párrafo y ANTES de la línea `Línea por camino terminal (una sola llamada, la
que corresponda):`, inserta:

```markdown
**Antes de cualquier línea de cierre EN VERDE** (cierre normal §5.4, análisis completado §8.4,
diseño completado §9.4, implementación completada §10.4, auditoría/instalación de dependencias
completada §11.4 — NUNCA antes de `BLOCKED`/`KO` propagado ni de una línea "omitido": esos caminos
ya no cierran en verde, no necesitan gate), lanza el gate de verificación independiente
(spec §14bis):

```
Agent(subagent_type: "swarm:verifier", name: "verifier", prompt:
"run-id: <run-id>
swarm-root: <ruta absoluta de .swarm>
operation: verify
domain: <nombre del orquestador de dominio que acaba de cerrar>
verdict: <su veredicto literal completo>")
```

- **`OK`** → sigue con la línea de cierre EN VERDE que corresponda (lista de abajo) y `curate`
  normal, sin cambios.
- **`KO <motivo>`** (1er intento): `SendMessage(to: "<nombre del dominio>", "verify KO: <motivo> —
  corrige y devuelve tu veredicto otra vez")` — el dominio sigue vivo/resumible (§2bis), su
  respuesta te llega como mensaje en un turno posterior, igual que cualquier `SendMessage` a un
  agente ya lanzado. Cuando llegue, relanza `Agent(subagent_type: "swarm:verifier", ...)` una
  SEGUNDA vez con el veredicto corregido — es una instancia nueva bajo el mismo nombre, no hay
  estado que arrastrar entre los dos intentos (el verificador es puro read-only).
- **`KO` la segunda vez** (mismo motivo o no): two-strike, igual que
  `hooks/validate-output.py` — NO cures nada: la línea de cierre pasa a ser
  `- run cerrado: BLOCKED verificación fallida de <dominio>: <motivo del verifier>` y sigues con
  `curate` normal (el run se cierra `BLOCKED`, nunca en falso verde).
```

- [ ] **Step 4: Corre el test, confirma que pasa**

```bash
bash tests/test_orchestrator_verify_gate.sh
```
Esperado: PASS, todas las aserciones en verde.

- [ ] **Step 5: Corre la suite completa (regresión)**

```bash
bash tests/run.sh 2>&1 | tail -5
```
Esperado: `failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/orchestrator.md tests/test_orchestrator_verify_gate.sh
git commit -m "feat(orchestrator): engancha swarm:verifier en §4 antes de cualquier cierre en verde"
```

---

### Task 4: Integración final, coordinación y merge

**Files:**
- Ninguno nuevo — verificación cruzada del trabajo de Tasks 1-3.

**Interfaces:**
- Consumes: todo lo de Tasks 1-3.
- Produces: el gate mergeado a `master`.

- [ ] **Step 1: Suite completa desde cero**

```bash
bash tests/run.sh 2>&1 | tail -10
```
Esperado: `failed: 0` en TODOS los ficheros (no solo los 3 nuevos/tocados).

- [ ] **Step 2: Cruce contra spec §14bis**

Lee `docs/superpowers/specs/2026-09-01-swarm-design.md` §14bis y confirma, punto por punto, que
`agents/verifier.md` + el enganche en `agents/orchestrator.md` §4 implementan EXACTAMENTE lo
descrito ahí (agente único genérico, trazabilidad + completitud, two-strike, límite reconocido). Si
algo del spec no tiene tarea que lo cubra, añade el task que falte antes de seguir — no cierres con
un hueco.

Nota honesta: los tests de Tasks 1-3 son ESTRUCTURALES (igual que TODO el resto de este repo — los
agentes son prompts de LLM, no código determinista; no hay forma de "unit-testear" su juicio con
bash). Confirman que el CONTRATO instruye los chequeos correctos, no que el agente los ejecute bien
en vivo. La validación de comportamiento real (¿el verificador de verdad detecta un batch
fabricado?) es un smoke-run manual con `/swarm:run` tras el merge — mismo patrón que cada fase
anterior de este proyecto (ver `docs/superpowers/plans/*-smoke-checklist.md`). No lo saltes: abre
ese checklist como siguiente paso tras el Step 5 de este task, no lo des por hecho solo porque los
tests estructurales están en verde.

- [ ] **Step 3: Avisa a la sesión par antes de fusionar**

`SendMessage(to: "multiagents-06", "Gate de verificación listo para fusionar a master: agents/verifier.md
+ enganche en agents/orchestrator.md §4 (entre <n> líneas insertadas en §4, no toca ninguna otra
sección). Voy a fusionar ahora — avísame si mientras tanto tocaste algo de orchestrator.md.")`
Espera confirmación (o ausencia de objeción en un tiempo razonable) antes del Step 4.

- [ ] **Step 4: Merge a master (con aprobación del owner)**

```bash
git status --short   # confirma limpio
git log --oneline -1 master   # confirma que master no avanzó desde que abriste el worktree
```
Si `master` avanzó, actualiza el worktree (`git rebase master` o `git merge master`) y re-corre la
suite completa antes de fusionar. Pide aprobación explícita al owner (el clasificador de auto-mode
de esta sesión bloquea el merge sin ella) y luego:
```bash
git merge --no-ff <rama-de-este-plan> -m "Merge branch '<rama-de-este-plan>'"
bash tests/run.sh 2>&1 | tail -5
git worktree remove <ruta-del-worktree>
git branch -d <rama-de-este-plan>
```

- [ ] **Step 5: Avisa a la sesión par que ya está fusionado**

`SendMessage(to: "multiagents-06", "Gate de verificación fusionado a master (<sha>). agents/orchestrator.md
libre de nuevo.")`
