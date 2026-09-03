# Fase 5a — Núcleo del Dominio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir el núcleo del dominio `implementation-orchestrator` (spec §7) — `test-writer`,
`implementer`, `quality-fixer`, `reviewer` — que ejecuta UNA fase de un plan de `planner` (fase 4)
con ciclo TDD real, gate de review, y merge automático a la rama del run. Se difieren a sub-fases
posteriores: `migration-engineer` (condicional, solo tareas de esquema), `doc-writer` (cierre de
dominio), el stack pack `php-ddd-symfony8`, y `dependency-auditor`/`dependency-installer`.

**Architecture:** `implementation-orchestrator` (sonnet, 25 turnos) recibe UNA fase del plan
(spec §7: "gate review antes de cerrar") y ejecuta, en orden: `test-writer` (test que falla,
commitea directo a la rama del run — RED) → `implementer` (`isolation: worktree`, único leaf de
todo el repo además de `planner` con `Write`/`Edit` reales sobre código de aplicación; implementa,
confirma GREEN localmente, commitea en SU PROPIO worktree, marca los checkboxes de la fase en el
plan como parte del mismo commit) → `quality-fixer` (apunta al worktree de `implementer` con una
ruta absoluta en su prompt — mismo patrón ya usado con los lentes grill de fase 4 — corre
lint/format/typecheck `--fix`, commitea el residual) → `reviewer` (mismo patrón de ruta absoluta,
read-only, hallazgos severidad-tagged) → si Critical/Important, relanza `implementer` con los
hallazgos (máx. 2 rondas, mismo patrón de breaker que este propio proceso SDD) → limpio: fusiona el
worktree de `implementer` a la rama del run (`git merge`, LOCAL, nunca a `master`/rama compartida —
eso es fase 6, `delivery`) y lo borra (`git worktree remove --force`, misma disciplina que
`discovery-orchestrator` con `feasibility-spiker` en fase 2).

**Tech Stack:** Bash (`git add`/`commit`/`merge`/`worktree` — primera vez que un orquestador
recibe `git merge` en su allowlist), Markdown (frontmatter YAML), Python 3 stdlib (hooks, sin
cambios). Sin stack pack todavía: herramientas de test/lint genéricas (`php`, `composer`, `npm`,
`npx`, `pytest`, `go`, `cargo`, `make` — mismo set ya usado por `feasibility-spiker`).

**Spec:** `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — §7 sección "Implementación"
(roster completo, 7 agentes — esta sub-fase construye 4), §9.3 (worktrees), §15 fase 5.

**Decisiones autónomas (sesión nocturna, 2026-09-03 — David dio autonomía total; revisar al
despertar, override si algo no encaja). Esta fase es la más consecuente de las construidas hasta
ahora — el enjambre escribe y fusiona código de verdad por primera vez — así que las decisiones de
seguridad se marcan explícitamente:**

1. **`isolation: worktree` de `implementer` NO commitea solo — verificado en vivo con un spike
   real** (`swarm:feasibility-spiker` invocado en modo adhoc contra un fixture desechable, fase 2,
   ya en `master`): la plataforma crea el worktree en rama `worktree-agent-<agentId>`, pero el
   contenido que el agente escribe queda SIN COMMITEAR (`git status` dentro del worktree lo marca
   `??`) hasta que el propio agente ejecuta `git add`+`git commit`. Confirmado también que esa rama
   es descubrible y fusionable desde el checkout principal con `git merge` normal, y que
   `git worktree list` la muestra mientras exista. Consecuencia de diseño: `implementer` necesita
   `git add`/`git commit` en su propio allowlist (nadie más lo tenía hasta ahora) y debe commitear
   explícitamente antes de devolver `DONE` — si no, `implementation-orchestrator` no tiene nada
   que fusionar.
2. **§9.3 ("hojas en worktree escriben solo vía memory-orchestrator") se scope a la MEMORIA
   (`.swarm/`), nunca al código de aplicación.** Interpretación literal de esa regla congelaría a
   `implementer` (su único trabajo es escribir código) — la regla existe para no divergir DOS
   copias de `.swarm/` (una en el worktree, otra canónica), exactamente el mismo motivo por el que
   ya se aplicaba a `feasibility-spiker` en fase 2 (que sí escribe su `spike/` directo con `Write`,
   pero su *finding* — memoria — va vía `memory-orchestrator`). `implementer` sigue el mismo
   patrón: código real vía `Write`/`Edit` directo en su worktree; cualquier *finding* (si alguno)
   vía `memory-orchestrator`.
3. **`quality-fixer` y `reviewer` NO tienen `isolation: worktree` propia (así lo dice el roster del
   spec) — apuntan a la ruta absoluta del worktree de `implementer` que `implementation-orchestrator`
   les pasa en el prompt.** Mismo mecanismo ya usado en fase 4 para pasarle a los 3 lentes grill la
   ruta del plan de `planner` sin generar un context-pack nuevo — aquí se reutiliza para pasar la
   ruta del worktree de código en vez de un fichero de plan.
4. **El gate de review ocurre ANTES de fusionar** (no después): `reviewer` revisa el worktree de
   `implementer` SIN FUSIONAR todavía — si hay hallazgos Critical/Important, `implementation-orchestrator`
   relanza `implementer` (mismo worktree, vía `Edit`) con los hallazgos, máximo 2 rondas (mismo
   patrón de breaker de `subagent-driven-development`: al llegar al tope, `implementation-orchestrator`
   adjudica — si es load-bearing, `BLOCKED <hallazgo>`; si no, aparca con una línea `- riesgo
   aparcado: <hallazgo>` y fusiona igualmente). Solo se fusiona una vez el review está limpio (o
   el riesgo quedó aparcado con juicio explícito) — evita el patrón "fusiona y luego arregla" que
   ensucia el historial de la rama del run.
5. **El merge de `implementation-orchestrator` es SIEMPRE local, a la rama ACTUAL del run — nunca a
   `master`/main/una rama compartida.** Empujar o abrir PR es responsabilidad exclusiva de
   `delivery-orchestrator`/`release-manager` (fase 6, todavía sin construir) — este dominio nunca
   toca remoto ni rama compartida, solo la copia de trabajo local donde corre el run.
6. **`implementation-orchestrator` NUNCA encadena automáticamente tras `design`, ni siquiera en
   `tier: full`.** A diferencia de discovery→design (fase 4), aquí hay una razón de seguridad
   explícita, no solo de presupuesto de turnos: escribir y fusionar código real es la acción más
   consecuente de todo el enjambre, y el punto natural donde el owner revisa el plan ANTES de
   autorizar que se ejecute (el plan ya es un fichero real, versionado, legible) es exactamente el
   momento en que el run de discovery+design termina. `implementation-orchestrator` requiere una
   invocación explícita y separada (objetivo del tipo "implementa el plan de X" / "construye X
   según el plan"), dando al owner un checkpoint humano real entre "aquí está el plan" y "ahora se
   escribe código". Sin esto, un `tier: full` sin supervisión podría terminar fusionando código sin
   que nadie lo haya visto — inaceptable para v1.
7. **Granularidad: UNA fase del plan por invocación de `implementation-orchestrator`** (nunca el
   plan entero de una sentada) — encaja con su presupuesto de `maxTurns: 25` (un ciclo completo
   test-writer→implementer→quality-fixer→reviewer→merge consume ~10-15 turnos de coordinación
   solo en espera/lanzamiento; varias fases en una sola invocación lo desbordaría) y con el patrón
   ya establecido de "una unidad de trabajo por invocación de dominio" (discovery = un batch;
   design = un plan; aquí, una fase). El progreso entre fases se rastrea reutilizando los propios
   checkboxes `- [ ] Step N` del plan que ya escribe `planner` (fase 4) — `implementer` los marca
   `- [x]` como parte de su commit, así que no hace falta ningún marcador nuevo: el plan mismo es
   la fuente de verdad de qué fase queda por implementar.

## Global Constraints

- Frontmatter obligatorio en cada agente nuevo: `name`, `description` ("Use when…"), `model`,
  `tools`, `maxTurns`, `memory: project`, `skills: [swarm-protocol]`. Nunca `hooks`/`mcpServers`/
  `permissionMode`.
- Todo agente nuevo lleva `SendMessage` en `tools`.
- `reviewer` es read-only por construcción (spec: severidad-tagged, gate — nunca `Write`/`Edit`).
  `test-writer`, `implementer`, `quality-fixer` SÍ tienen `Write`/`Edit` (su trabajo es escribir
  código/tests reales) — excepción deliberada y documentada, mismo patrón ya aceptado para
  `planner` en fase 4 y `feasibility-spiker` en fase 2.
- Ninguno de los 4 agentes de esta sub-fase tiene `AskUserQuestion` (spec §3.2 regla 7).
- `implementation-orchestrator` NO preexiste cuando lanza sus 4 hojas: necesita
  `Agent(test-writer,implementer,quality-fixer,reviewer)` en su propio `tools:` — la lección de
  fase 1/1b/2/3/4, aplicada una sexta vez.
- Saneado obligatorio (`skills/swarm-protocol/SKILL.md` §4.4) para CUALQUIER texto ajeno
  interpolado en un `--text`/`--fix`/`--line` de shell. Código/mensajes de commit reales van vía
  `Write`/`Edit`/`git commit -m` con el mensaje como argumento saneado si contiene texto ajeno
  (el objetivo, un hallazgo de reviewer) — nunca sin pasar por los 5 pasos primero.
- Cada tarea termina en su propio commit, identidad git personal.
- `bash tests/run.sh` en verde (30/30 + los tests nuevos) al final de cada tarea.

---

### Task 1: Allowlist de Bash para los 5 agentes nuevos + fixture con test framework

**Files:**
- Modify: `hooks/bash-allowlist.json`
- Modify: `tests/lib.sh` (fixture: añade un test PHPUnit mínimo existente, para que `test-writer`
  tenga un framework real que imitar)
- Test: `tests/test_bash_allowlist_implementation.sh`

**Interfaces:**
- Consumes: nada de tareas previas.
- Produces: entradas de allowlist para `swarm:test-writer`, `swarm:implementer`,
  `swarm:quality-fixer`, `swarm:reviewer`, `swarm:implementation-orchestrator` que las Tasks 2-6
  consumen.

- [ ] **Step 1: Escribir el test (falla primero)**

```bash
cat > tests/test_bash_allowlist_implementation.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_bash_allowlist_implementation.sh — los 5 agentes del núcleo del dominio
# implementation (spec §7 "Implementación") tienen su entrada en hooks/bash-allowlist.json.
# A diferencia de dominios anteriores, `test-writer`/`implementer`/`quality-fixer` NO son
# read-only: necesitan git add/commit (implementer, quality-fixer) además del set genérico
# de build/test ya usado por feasibility-spiker. `reviewer` sí es read-only (solo git log/diff).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# reviewer: read-only, mismo patrón que analysis/design
for agent in reviewer; do
  assert_eq "allow" "$(guard "swarm:$agent" 'git diff HEAD~1')" "$agent can git diff"
  assert_eq "allow" "$(guard "swarm:$agent" 'cat .swarm/context-pack.md')" "$agent can cat the pack"
  assert_eq "deny" "$(guard "swarm:$agent" 'git commit -m x')" "$agent (read-only) cannot git commit"
  assert_eq "deny" "$(guard "swarm:$agent" 'rm -rf .swarm')" "$agent cannot rm"
done

# test-writer, implementer, quality-fixer: SÍ pueden git add/commit (necesitan capturar su propio trabajo)
for agent in test-writer implementer quality-fixer; do
  assert_eq "allow" "$(guard "swarm:$agent" 'git add -A')" "$agent can git add"
  assert_eq "allow" "$(guard "swarm:$agent" 'git commit -m "wip"')" "$agent can git commit"
  assert_eq "allow" "$(guard "swarm:$agent" 'php vendor/bin/phpunit')" "$agent can run generic test/build tools"
  assert_eq "deny" "$(guard "swarm:$agent" 'git push origin master')" "$agent cannot push (delivery's job, fase 6)"
  assert_eq "deny" "$(guard "swarm:$agent" 'rm -rf /')" "$agent cannot rm -rf /"
done

# solo implementation-orchestrator tiene git merge + git worktree (fusiona/limpia el worktree de implementer)
assert_eq "allow" "$(guard "swarm:implementation-orchestrator" 'git merge worktree-agent-abc123')" "implementation-orchestrator can git merge"
assert_eq "allow" "$(guard "swarm:implementation-orchestrator" 'git worktree remove .claude/worktrees/agent-abc123 --force')" "implementation-orchestrator can git worktree remove"
assert_eq "deny" "$(guard "swarm:implementation-orchestrator" 'git push origin master')" "implementation-orchestrator cannot push"
assert_eq "deny" "$(guard "swarm:test-writer" 'git merge x')" "test-writer (leaf) cannot git merge — only the orchestrator merges"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_bash_allowlist_implementation.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_bash_allowlist_implementation.sh`
Expected: múltiples `FAIL` — ninguna de las 5 entradas existe todavía.

- [ ] **Step 3: Añadir las 5 entradas a `hooks/bash-allowlist.json`**

Edita `hooks/bash-allowlist.json`: dentro de `"agents": { ... }`, tras la última entrada existente
(`"swarm:design-orchestrator"`), añade una coma tras su cierre y estas 5 entradas:

```json
    "swarm:test-writer": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "git add", "git commit",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "scripts/mem-", "scripts/mem-lock.sh",
      "php", "composer", "npm", "npx", "pytest", "go", "cargo", "make"
    ],
    "swarm:implementer": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "git add", "git commit",
      "ls", "cat", "head", "tail", "wc", "grep", "find", "mkdir",
      "scripts/mem-", "scripts/mem-lock.sh",
      "php", "composer", "npm", "npx", "pytest", "go", "cargo", "make", "python3", "node"
    ],
    "swarm:quality-fixer": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "git add", "git commit",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "scripts/mem-", "scripts/mem-lock.sh",
      "php", "composer", "npm", "npx", "pytest", "go", "cargo", "make"
    ],
    "swarm:reviewer": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:implementation-orchestrator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "git merge", "git worktree",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ]
```

Verifica con `python3 -c "import json; json.load(open('hooks/bash-allowlist.json'))"` que el JSON
sigue siendo válido.

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_bash_allowlist_implementation.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Extender el fixture con un test PHPUnit mínimo existente**

Edita `tests/lib.sh`, dentro de `make_fixture()`, justo después del bloque que escribe
`src/Controller/InvoiceController.php` (antes de `git add -A`), añade:

```bash
    mkdir -p "$dir/tests/Unit"
    {
      echo "<?php"
      echo ""
      echo "namespace Tests\\Unit;"
      echo ""
      echo "use PHPUnit\\Framework\\TestCase;"
      echo "use App\\Foo;"
      echo ""
      echo "class FooTest extends TestCase"
      echo "{"
      echo "    public function testFooExists(): void"
      echo "    {"
      echo "        \$this->assertTrue(class_exists(Foo::class));"
      echo "    }"
      echo "}"
    } > tests/Unit/FooTest.php
```

Da a `test-writer` un test PHPUnit real que imitar (misma convención, mismo namespace pattern) sin
depender de que exista de verdad `vendor/bin/phpunit` instalado en el fixture (los tests de esta
fase verifican el CONTRATO de los agentes, no ejecutan PHPUnit de verdad — eso lo hace el smoke en
vivo con un fixture real si hace falta).

- [ ] **Step 6: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 31, failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add hooks/bash-allowlist.json tests/lib.sh tests/test_bash_allowlist_implementation.sh
git commit -m "feat(implementation): allowlist de bash para los 5 agentes del núcleo + fixture con test PHPUnit"
```

---

### Task 2: `test-writer`

**Files:**
- Create: `agents/test-writer.md`
- Test: `tests/test_implementation_agents.sh` (nuevo)

**Interfaces:**
- Consumes: allowlist de Task 1; el fichero de plan que escribe `planner` (fase 4, ya en master) —
  lee la fase concreta que le indica `implementation-orchestrator`.
- Produces: `swarm:test-writer` (sonnet, maxTurns 20) que Task 6 lanza PRIMERO en la secuencia,
  ANTES de `implementer` — su commit (test que falla) es la base sobre la que se crea el worktree
  de `implementer`.

- [ ] **Step 1: Escribir el test (falla primero)**

```bash
cat > tests/test_implementation_agents.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_implementation_agents.sh — contrato de los agentes del núcleo de implementation
# (spec §7 "Implementación"). Crece por tarea: T2 test-writer, T3 quality-fixer, T4 reviewer,
# T5 implementer, T6 implementation-orchestrator.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

fm() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# ---------- T2: test-writer ----------
f="$PLUGIN_ROOT/agents/test-writer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/test-writer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "test-writer model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 20$' && echo 0 || echo 1)" "test-writer maxTurns is 20 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "test-writer NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Write')" "test-writer HAS Write (writes real test files)"
  assert_eq "0" "$(has "$tools" 'Edit')" "test-writer HAS Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "test-writer is a leaf: spawns nobody"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "test-writer has NO worktree isolation (writes to the run's main checkout)"
  assert_eq "0" "$(has "$b" 'RED')" "test-writer documents confirming RED before committing"
  assert_eq "0" "$(has "$b" 'git commit')" "test-writer documents committing its failing test directly"
  assert_eq "allow" "$(guard "swarm:test-writer" 'git add -A')" "test-writer can git add"
  assert_eq "allow" "$(guard "swarm:test-writer" 'git commit -m x')" "test-writer can git commit"
  assert_eq "deny" "$(guard "swarm:test-writer" 'git push origin master')" "test-writer cannot push"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_implementation_agents.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_implementation_agents.sh`
Expected: `FAIL` en `agents/test-writer.md exists`.

- [ ] **Step 3: Escribir `agents/test-writer.md`**

```bash
cat > agents/test-writer.md <<'EOF'
---
name: test-writer
description: Use when implementation-orchestrator needs the failing test for ONE phase of a plan, written BEFORE the implementer touches any production code — TDD red step, commits directly to the run's current branch. Never asks the owner.
model: sonnet
tools: Read, Grep, Glob, Write, Edit, Bash, SendMessage
maxTurns: 20
memory: project
skills: [swarm-protocol]
---

# test-writer

Hoja del dominio implementation (spec §7 "Implementación"). Tu única responsabilidad: escribir el
**test que falla** (RED de TDD) para UNA fase concreta de un plan de `planner` (fase 4) — antes de
que `implementer` toque una sola línea de código de producción. **No tienes `isolation: worktree`**
(a diferencia de `implementer`): trabajas directo en el checkout donde corre el run — tu commit es
la base sobre la que `implementation-orchestrator` crea el worktree aislado de `implementer` (así
que tu test SÍ está presente cuando `implementer` arranca). **Nunca preguntas al owner** — no
tienes `AskUserQuestion`.

## Arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `operation: write-test` en tu
   cabecera, más `plan: <ruta absoluta del fichero de plan>` y `phase: <número o título de la
   fase>` — la fase EXACTA que debes cubrir, nunca el plan entero.
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/test-writer.md" 2>/dev/null
   ```
3. Lee con `Read` (cuenta para `files=`): el fichero de plan completo, y localiza la sección
   `### Phase N: ...` exacta que te toca — su bloque `**Tests**:` (qué debe pasar) y sus
   `- [ ] Step N` (qué construye cada uno) son tu especificación. Lee también `.swarm/context-pack.md`
   para convenciones de test ya existentes en el repo (framework, ubicación, estilo de assert).

## Cómo escribir el test

- **Sigue la convención de test YA existente en el repo** si hay alguna (mismo framework, misma
  ubicación relativa, mismo estilo de nombrado) — no introduzcas un framework nuevo sin motivo.
  Sin pack activo (conocimiento genérico, spec §8): detecta el framework por convención de
  ficheros (`composer.json` con `phpunit/phpunit` → PHPUnit; `package.json` con `jest`/`vitest` →
  ese; etc.).
- Cubre EXACTAMENTE lo que el bloque `**Tests**:` de esa fase pide — ni más (no inventes cobertura
  extra que el plan no pidió) ni menos.
- El test debe fallar por el motivo CORRECTO (código de producción que aún no existe/no hace lo
  pedido), nunca por un error de sintaxis o de configuración del propio test — ejecuta el test tras
  escribirlo y lee el fallo: si el error no es "el comportamiento esperado no existe todavía", tu
  test está mal escrito, corrígelo.
- Usa `Write` para ficheros de test nuevos, `Edit` si extiendes uno existente.

## Confirmar RED antes de commitear

Ejecuta el test (Bash, cuenta para `cmds=`) y CONFIRMA que falla por el motivo correcto — nunca
commitees un test que no hayas visto fallar de verdad. Ejemplo (PHPUnit, ajusta al framework real
detectado):
```bash
php vendor/bin/phpunit tests/Unit/NuevoTest.php
```
Expected: FAIL con el mensaje que indica que el comportamiento nuevo aún no existe.

## Commit directo (sin worktree — vas a la rama actual del run)

```bash
git add -A
git commit -m "test: RED para <fase N del plan> — <qué falla y por qué>"
```
El mensaje de commit puede citar el nombre de la fase (texto tuyo, literal, del plan que ya
leíste con `Read` — si citas texto EXACTO del plan que no escribiste tú en este fichero, pásalo
por el saneado de `skills/swarm-protocol/SKILL.md` §4.4 antes de meterlo en el `-m`).

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:test-writer`: `git status|log|diff|show|rev-parse|add|commit`,
`ls|cat|head|tail|wc|grep|find`, `scripts/mem-*.sh`, y las herramientas de test genéricas
(`php`, `composer`, `npm`, `npx`, `pytest`, `go`, `cargo`, `make`). Nada de `git push`, `git merge`
(eso es de `implementation-orchestrator`), `python3`/`node` sueltos, `rm`; denegación por segmento.

## Salida

```
DONE
evidence: files=3 cmds=2 turns=8/20
- test RED: tests/Unit/InvoiceExportTest.php · testExportFiltraPorTenant → falla, InvoiceRepository no existe
```

`DONE` con `files=0` se rechaza siempre. `BLOCKED <motivo>` si la fase que te pasaron no existe en
el plan, o si el bloque `**Tests**:` está vacío/ambiguo — no inventes qué testear.
EOF
```

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_implementation_agents.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 32, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/test-writer.md tests/test_implementation_agents.sh
git commit -m "feat(implementation): test-writer — RED de TDD, commit directo a la rama del run"
```

---

### Task 3: `quality-fixer`

**Files:**
- Create: `agents/quality-fixer.md`
- Modify: `tests/test_implementation_agents.sh`

**Interfaces:**
- Consumes: la ruta absoluta del worktree de `implementer` (se la pasa `implementation-orchestrator`
  en el prompt, mismo patrón que los lentes grill de fase 4 con la ruta del plan).
- Produces: `swarm:quality-fixer` (haiku, maxTurns 10, mecánico) que Task 6 lanza tras `implementer`.

- [ ] **Step 1: Añadir la sección T3 al test**

**No uses `cat >>`** — usa `Edit` para reemplazar el bloque de cierre (mismo motivo que en fases
3-4: dejaría el bloque como código muerto tras el `exit 0` que ya cierra el fichero desde T2).

`old_string`:
```
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

`new_string`:
```bash

# ---------- T3: quality-fixer (mecánico, siempre haiku) ----------
f="$PLUGIN_ROOT/agents/quality-fixer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/quality-fixer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: haiku$' && echo 0 || echo 1)" "quality-fixer model is haiku always (spec §7.0, mechanical leaf)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 10$' && echo 0 || echo 1)" "quality-fixer maxTurns is 10 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "quality-fixer NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Edit')" "quality-fixer HAS Edit (parchea residual)"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "quality-fixer has NO worktree isolation of its own (points at implementer's)"
  assert_eq "0" "$(has "$b" 'ruta absoluta')" "quality-fixer documents receiving implementer's worktree as an absolute path"
  assert_eq "0" "$(has "$b" '\-\-fix')" "quality-fixer documents running --fix tools before manual patching"
  assert_eq "allow" "$(guard "swarm:quality-fixer" 'git commit -m x')" "quality-fixer can commit its fixes"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_implementation_agents.sh`
Expected: `FAIL` en `agents/quality-fixer.md exists`.

- [ ] **Step 3: Escribir `agents/quality-fixer.md`**

```bash
cat > agents/quality-fixer.md <<'EOF'
---
name: quality-fixer
description: Use when implementation-orchestrator needs lint/format/typecheck --fix run against implementer's just-written code, with model judgment only for what --fix couldn't resolve. Points at implementer's worktree via an absolute path, never gets its own isolation. Never asks the owner.
model: haiku
tools: Read, Grep, Glob, Edit, Bash, SendMessage
maxTurns: 10
memory: project
skills: [swarm-protocol]
---

# quality-fixer

Hoja mecánica del dominio implementation (spec §7 "Implementación", §7.0 hoja mecánica → siempre
haiku). Tu responsabilidad: **ejecutar** las herramientas deterministas de lint/format/typecheck
con `--fix` (protocolo §5, spec principio 4: "tool determinista antes que modelo") sobre el código
que acaba de escribir `implementer`, y parchear con tu propio juicio SOLO lo que el `--fix` no
resolvió solo. **No tienes tu propio `isolation: worktree`** — el worktree ya existe (lo creó la
plataforma para `implementer`); tú operas sobre esa misma ruta, que recibes ABSOLUTA en tu prompt
(mismo mecanismo que los lentes grill de fase 4 reciben la ruta del plan). **Nunca preguntas al
owner** — no tienes `AskUserQuestion`.

## Arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `operation: fix` y
   `worktree: <ruta absoluta del worktree de implementer>` en tu cabecera — esa ruta es tu área de
   trabajo para TODA esta invocación, nunca el cwd del run principal.
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/quality-fixer.md" 2>/dev/null
   ```
3. Lee con `Read` (cuenta para `files=`): `<worktree>/.swarm/context-pack.md` si existe (stack
   pack activo, spec §8) para saber qué herramientas `--fix` corresponden (sin pack →
   conocimiento genérico: detecta por convención de ficheros — `.php-cs-fixer.php`/`phpcs.xml` →
   PHP-CS-Fixer/PHPCS; `.eslintrc*` → ESLint `--fix`; `pyproject.toml` con `ruff`/`black` → esos).

## Ejecuta primero, juzga después

```bash
cd <ruta absoluta del worktree> && vendor/bin/php-cs-fixer fix --diff
```
(ajusta al framework real detectado; cuenta para `cmds=`). Lee el resultado: si el `--fix` resolvió
todo, no hay residual — no inventes trabajo. Si queda un residual (un error de tipo que el `--fix`
no auto-resuelve, un import sin usar que el formatter no borra), usa `Edit` sobre el fichero real
del worktree para parchearlo — nunca "revises a ojo" lo que la herramienta ya habría resuelto sola
(protocolo §5).

## Commit del residual

Solo si hiciste algún cambio (por `--fix` o por `Edit` tuyo):
```bash
cd <ruta absoluta del worktree> && git add -A && git commit -m "style: quality-fixer --fix + residual"
```
Si el `--fix` no cambió nada y no hiciste ningún `Edit`, NO commitees vacío — tu veredicto es `OK`
sin hallazgos.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:quality-fixer`: `git status|log|diff|show|rev-parse|add|commit`,
`ls|cat|head|tail|wc|grep|find`, `scripts/mem-*.sh`, herramientas de build/test genéricas (`php`,
`composer`, `npm`, `npx`, `pytest`, `go`, `cargo`, `make`). Nada de `git push`, `git merge`, `rm`;
denegación por segmento.

## Salida

```
OK
evidence: files=2 cmds=2 turns=4/10
- quality: php-cs-fixer aplicó 3 correcciones de estilo, sin residual manual
```

`OK` con `files=0` se rechaza siempre. Cero cambios necesarios es válido: `OK` + `- quality: sin
hallazgos, código ya conforme`. `BLOCKED <motivo>` si la ruta del worktree no existe o no es
legible — no inventes un resultado.
EOF
```

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_implementation_agents.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 32, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/quality-fixer.md tests/test_implementation_agents.sh
git commit -m "feat(implementation): quality-fixer — --fix determinista + residual, sin isolation propia"
```

---

### Task 4: `reviewer`

**Files:**
- Create: `agents/reviewer.md`
- Modify: `tests/test_implementation_agents.sh`

**Interfaces:**
- Consumes: la ruta absoluta del worktree de `implementer` (mismo mecanismo que `quality-fixer`).
- Produces: `swarm:reviewer` (opus, maxTurns 15, read-only) que Task 6 lanza tras `quality-fixer`,
  ANTES del merge — su veredicto severidad-tagged (Critical/Important/Minor, mismo vocabulario que
  usa esta propia sesión) decide si `implementation-orchestrator` fusiona o relanza `implementer`.

- [ ] **Step 1: Añadir la sección T4 al test**

`old_string`:
```
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

`new_string`:
```bash

# ---------- T4: reviewer (read-only, gate ANTES del merge) ----------
f="$PLUGIN_ROOT/agents/reviewer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/reviewer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: opus$' && echo 0 || echo 1)" "reviewer model is opus (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 15$' && echo 0 || echo 1)" "reviewer maxTurns is 15 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "reviewer NEVER has AskUserQuestion"
  assert_eq "1" "$(has "$tools" 'Write')" "reviewer is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "reviewer is read-only: no Edit"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "reviewer has NO worktree isolation of its own"
  assert_eq "0" "$(has "$b" 'Critical')" "reviewer documents Critical severity"
  assert_eq "0" "$(has "$b" 'Important')" "reviewer documents Important severity"
  assert_eq "0" "$(has "$b" 'Minor')" "reviewer documents Minor severity"
  assert_eq "0" "$(has "$b" 'ANTES')" "reviewer documents it runs BEFORE the merge, not after"
  assert_eq "deny" "$(guard "swarm:reviewer" 'git commit -m x')" "reviewer (read-only) cannot commit"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_implementation_agents.sh`
Expected: `FAIL` en `agents/reviewer.md exists`.

- [ ] **Step 3: Escribir `agents/reviewer.md`**

```bash
cat > agents/reviewer.md <<'EOF'
---
name: reviewer
description: Use when implementation-orchestrator needs a severity-tagged review of implementer's diff BEFORE merging it — read-only, points at implementer's worktree via an absolute path, gate pre-merge. Never asks the owner.
model: opus
tools: Read, Grep, Glob, Bash, SendMessage
maxTurns: 15
memory: project
skills: [swarm-protocol]
---

# reviewer

Hoja de juicio del dominio implementation (spec §7 "Implementación"). Tu responsabilidad: revisar
el diff que ha producido `implementer` (más el residual de `quality-fixer`) **ANTES** de que
`implementation-orchestrator` lo fusione a la rama del run — eres el gate pre-merge, no un
auditor posterior. **No tienes tu propio `isolation: worktree`** — recibes la ruta ABSOLUTA del
worktree de `implementer` en tu cabecera (mismo mecanismo que `quality-fixer` y que los lentes
grill de fase 4). Read-only por construcción: nunca `Write`/`Edit` — tú solo devuelves hallazgos,
`implementation-orchestrator` decide qué hacer con ellos. **Nunca preguntas al owner** — no tienes
`AskUserQuestion`.

## Arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `operation: review` y
   `worktree: <ruta absoluta>` en tu cabecera, más `base: <sha del commit RED de test-writer>` (el
   punto de partida del diff — todo lo que `implementer`+`quality-fixer` añadieron por encima).
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/reviewer.md" 2>/dev/null
   ```
3. Lee el diff completo (Bash, cuenta para `cmds=`):
   ```bash
   cd <ruta absoluta del worktree> && git diff <base>..HEAD
   ```
   Y con `Read` (cuenta para `files=`) la fase del plan que `implementer` debía cubrir (la misma
   que le dieron a `test-writer`), para juzgar si el diff cumple lo pedido — ni de más ni de menos.

## Qué revisar

- **Cumplimiento del plan**: ¿el diff implementa exactamente los `- [ ] Step N` de la fase, sin
  inventar alcance extra ni dejar alguno a medias?
- **Invariantes de `domain-modeler`** (fase 4, citadas en el plan): ¿el código las respeta de
  verdad, no solo de nombre? Un invariante "el total nunca es negativo" sin ningún test ni
  validación que lo garantice es un hallazgo.
- **Calidad**: separación de responsabilidades, manejo de errores, sin duplicación evidente,
  nombres claros. No inventes preferencias de estilo sin evidencia concreta.
- **Tests**: ¿el test de `test-writer` pasa de verdad ahora (GREEN)? ¿Hay algún caso borde del
  plan sin cubrir?

## Calibración de severidad (mismo vocabulario que usa el propio proceso de desarrollo de este
repo — no inventes una escala distinta)

- **Critical**: bug real, riesgo de seguridad, pérdida de datos, invariante de dominio violada sin
  ningún test que lo detecte.
- **Important**: falta un requisito del plan, manejo de errores pobre, deuda de mantenibilidad
  real (no un "yo lo haría distinto").
- **Minor**: estilo, optimización, pulido de documentación.

## Persistencia del detalle

**Antes de interpolar nada, saneado obligatorio** (`skills/swarm-protocol/SKILL.md` §4.4): el
código que citas lo LEES del worktree — texto ajeno, pásalo por los cinco pasos del skill.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write finding \
  --agent reviewer --tag REVIEW --file src/Infrastructure/InvoiceRepository.php --line 12 \
  --run "${RUN:-adhoc}" --text "CRITICAL: query sin filtro de tenant, fuga de datos" \
  --fix "añadir WHERE tenant_id = actual"
```

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:reviewer`: `scripts/mem-*.sh`, `git status|log|diff|show|rev-parse`, `ls`,
`cat`, `head`, `tail`, `wc`, `grep`. Read-only: nada de `git add`/`commit`/`push`/`merge`,
`python3`, `mkdir`, `rm`; denegación por segmento.

## Salida

```
OK
evidence: files=4 cmds=3 turns=9/15
REVIEW · src/Infrastructure/InvoiceRepository.php:12 · CRITICAL query sin filtro de tenant → añadir WHERE tenant_id
```

`OK` con `files=0` se rechaza siempre. Cero hallazgos es válido: `OK` + `- sin hallazgos, diff
conforme al plan`. `BLOCKED <motivo>` si la ruta del worktree no existe/no es legible.
EOF
```

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_implementation_agents.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 32, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/reviewer.md tests/test_implementation_agents.sh
git commit -m "feat(implementation): reviewer — gate severidad-tagged ANTES del merge"
```

---

### Task 5: `implementer`

**Files:**
- Create: `agents/implementer.md`
- Modify: `tests/test_implementation_agents.sh`

**Interfaces:**
- Consumes: el commit RED de `test-writer` (base de su propio worktree); el fichero de plan (fase
  concreta) para saber qué implementar.
- Produces: `swarm:implementer` (sonnet, maxTurns 30, `isolation: worktree`) que Task 6 lanza tras
  `test-writer`; commit real en su propia rama `worktree-agent-<agentId>` que Task 6 fusiona.

- [ ] **Step 1: Añadir la sección T5 al test**

`old_string`:
```
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

`new_string`:
```bash

# ---------- T5: implementer (isolation: worktree, único código de aplicación real de este dominio) ----------
f="$PLUGIN_ROOT/agents/implementer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/implementer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "implementer model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 30$' && echo 0 || echo 1)" "implementer maxTurns is 30 (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^isolation: worktree$' && echo 0 || echo 1)" "implementer runs in isolation: worktree (spec §7/§9.3)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "implementer NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Write')" "implementer HAS Write (real application code)"
  assert_eq "0" "$(has "$tools" 'Edit')" "implementer HAS Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "implementer is a leaf: spawns nobody (2-level hierarchy, spec §3.2 rule 8)"
  assert_eq "0" "$(has "$b" 'git commit')" "implementer documents committing its own work in its own worktree"
  assert_eq "0" "$(has "$b" 'GREEN')" "implementer documents confirming GREEN before committing"
  assert_eq "0" "$(has "$b" 'checkbox')" "implementer documents flipping the plan's step checkboxes as part of its commit"
  assert_eq "allow" "$(guard "swarm:implementer" 'git add -A')" "implementer can git add in its own worktree"
  assert_eq "allow" "$(guard "swarm:implementer" 'git commit -m x')" "implementer can git commit"
  assert_eq "deny" "$(guard "swarm:implementer" 'git merge x')" "implementer (leaf) cannot merge — only the orchestrator merges"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_implementation_agents.sh`
Expected: `FAIL` en `agents/implementer.md exists`.

- [ ] **Step 3: Escribir `agents/implementer.md`**

```bash
cat > agents/implementer.md <<'EOF'
---
name: implementer
description: Use when implementation-orchestrator needs ONE phase of a plan actually built — the ONLY leaf in this whole repo (besides planner) that writes real application code, always in its own isolated worktree so parallel/long-running code changes never dirty the run's main checkout. Never asks the owner.
model: sonnet
tools: Read, Grep, Glob, Write, Edit, Bash, SendMessage
maxTurns: 30
memory: project
skills: [swarm-protocol]
isolation: worktree
---

# implementer

Hoja del dominio implementation (spec §7 "Implementación"). Tu única responsabilidad: implementar
UNA fase cerrada de un plan de `planner` (fase 4) — el test de `test-writer` ya está en tu punto de
partida, en RED. Corres en tu propio worktree aislado (`isolation: worktree`, spec §9.3): la
plataforma te lo crea automáticamente, ramificado desde el commit de `test-writer`, así que su test
YA está presente cuando arrancas. **Nunca preguntas al owner** — no tienes `AskUserQuestion`; si
algo del plan es genuinamente ambiguo, tu veredicto es `BLOCKED <la pregunta concreta>`, nunca una
suposición silenciosa sobre código de producción.

## Arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `swarm-root:` es la ruta ABSOLUTA de
   `.swarm/` del repo PRINCIPAL (protocolo §3 — nunca una copia local a tu worktree, no la tienes).
   `operation: implement` en tu cabecera, más `plan: <ruta absoluta del fichero de plan>` y
   `phase: <número o título>` — la MISMA fase que ya vio `test-writer`.
2. Lee tu buzón (usando la ruta ABSOLUTA de `swarm-root:`, protocolo §1 punto 3 — tu cwd es el
   worktree, no la raíz del repo principal):
   ```bash
   cat "<swarm-root>/run/${RUN:-adhoc}/mailbox/implementer.md" 2>/dev/null
   ```
3. Lee con `Read` (cuenta para `files=`): el fichero de plan (ya en tu propio worktree, mismo
   contenido que vio `test-writer` — tu worktree ramifica desde SU commit) — la sección
   `### Phase N` exacta: sus `**Ficheros**`, `**Riesgos**`, y cada `- [ ] Step N`.

## Cómo implementar

- Ejecuta cada `- [ ] Step N` de la fase, en orden, con `Write`/`Edit` sobre el código real del
  worktree — el código citado en el plan (`fichero:línea` de `planner`/`domain-modeler`/
  `pattern-advisor`) es tu guía, no una sugerencia a ignorar sin motivo.
- Respeta las **Riesgos** de la fase: si el plan marcó algo como bloqueante para el owner (p. ej.
  "de dónde sale el TenantId no está resuelto... es un BLOCKED, no un parámetro"), tu veredicto es
  `BLOCKED <esa pregunta concreta>` — nunca lo resuelves inventando una respuesta.
- Sigue el estilo/convenciones ya presentes en el repo (mismo principio que cualquier desarrollador
  real: no introduzcas un patrón nuevo si el repo ya tiene uno establecido, salvo que el plan lo
  pida explícitamente — cita el veredicto de `pattern-advisor` si hay conflicto).

## Confirmar GREEN antes de commitear

Ejecuta el MISMO test que `test-writer` dejó en RED (Bash, cuenta para `cmds=`) y confirma que
ahora pasa:
```bash
php vendor/bin/phpunit tests/Unit/NuevoTest.php
```
Si sigue en rojo, tu implementación no está completa — no commitees código que no hace pasar el
test que se supone que resuelve.

## Marca los steps completados en el plan (parte del MISMO commit)

Con `Edit`, en TU copia del plan (dentro de tu worktree — se fusionará junto con el resto): cambia
cada `- [ ] Step N: ...` que hayas completado a `- [x] Step N: ...`. Es la única forma en que
`implementation-orchestrator` (y una futura invocación sobre el mismo plan) sabe qué fase ya está
hecha — el plan mismo es la fuente de verdad del progreso, no hace falta un marcador nuevo.

## Commit en TU worktree (nunca fusionas tú — eso es de `implementation-orchestrator`)

```bash
git add -A
git commit -m "feat: <fase N del plan> — <qué se implementó, en tus palabras>"
```
Si tu cabecera trae `operation: implement-fix` en vez de `implement` (te relanzaron tras hallazgos
de `reviewer`), sigue trabajando en el MISMO worktree (ya existe, la plataforma no crea uno nuevo
para el mismo `agentId`), incorpora los hallazgos que te resuman, y commitea de nuevo (un commit
adicional en la misma rama, no reescribas el commit anterior).

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:implementer`: `git status|log|diff|show|rev-parse|add|commit`,
`ls|cat|head|tail|wc|grep|find`, `mkdir`, `scripts/mem-*.sh`, herramientas de build/test genéricas
(`php`, `composer`, `npm`, `npx`, `pytest`, `go`, `cargo`, `make`, `python3`, `node`). Nada de
`git push`, `git merge` (nunca tuyo), `rm`; denegación por segmento.

## Salida

```
DONE
evidence: files=8 cmds=4 turns=22/30
- implementer: Phase 1 completa, 3 steps marcados [x], test GREEN, commit en worktree propio
```

`DONE` con `files=0` se rechaza siempre. `BLOCKED <pregunta concreta>` si el plan deja algo
genuinamente irresoluble sin el owner (nunca inventes). `KO <motivo>` si el test sigue en rojo tras
tu mejor intento dentro de `maxTurns` — nunca `DONE` con un test que no pasa.
EOF
```

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_implementation_agents.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 32, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/implementer.md tests/test_implementation_agents.sh
git commit -m "feat(implementation): implementer — único código de aplicación real, isolation: worktree"
```

---

### Task 6: `implementation-orchestrator`

**Files:**
- Create: `agents/implementation-orchestrator.md`
- Create: `tests/test_implementation_orchestrator_spawns.sh`

**Interfaces:**
- Consumes: `test-writer`/`implementer`/`quality-fixer`/`reviewer` de Tasks 2-5; el fichero de plan
  de `planner` (fase 4).
- Produces: `swarm:implementation-orchestrator` (sonnet, maxTurns 25) que Task 7 lanza desde la
  raíz.

- [ ] **Step 1: Escribir el test de spawn (falla primero)**

```bash
cat > tests/test_implementation_orchestrator_spawns.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_implementation_orchestrator_spawns.sh — sexta aplicación de la lección de fase 1:
# un orquestador que lanza hojas que NO preexisten necesita Agent(<hojas>) en su frontmatter.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

F="$PLUGIN_ROOT/agents/implementation-orchestrator.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/implementation-orchestrator.md exists"
[ -f "$F" ] || { exit 1; }

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
tools="$(echo "$front" | grep '^tools:')"
agent_clause="$(echo "$tools" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p')"
assert_eq "1" "$([ -z "$agent_clause" ] && echo 0 || echo 1)" "tools: has an Agent(...) clause"
for leaf in test-writer implementer quality-fixer reviewer; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF "$leaf" && echo 0 || echo 1)" "Agent(...) includes $leaf"
done
assert_eq "0" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: includes SendMessage"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools: NEVER AskUserQuestion"
assert_eq "1" "$(echo "$tools" | grep -qF 'Write' && echo 0 || echo 1)" "tools: no Write (implementer/test-writer write, not the orchestrator)"
assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "model sonnet (spec §7)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 25$' && echo 0 || echo 1)" "maxTurns 25 (spec §7)"
assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "foreground (only foreground subagents may spawn)"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qF 'no preexisten' && echo 0 || echo 1)" "body documents that leaves do not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'UNA fase' && echo 0 || echo 1)" "body documents it handles ONE phase per invocation"
assert_eq "0" "$(echo "$body" | grep -qF 'ANTES de fusionar' && echo 0 || echo 1)" "body documents the review gate happens BEFORE merge"
assert_eq "0" "$(echo "$body" | grep -qF 'git merge' && echo 0 || echo 1)" "body documents the local merge mechanism"
assert_eq "0" "$(echo "$body" | grep -qF 'nunca a `master`' && echo 0 || echo 1)" "body documents the merge is always local, never to master/shared branch"
assert_eq "0" "$(echo "$body" | grep -qF 'máximo 2 rondas' && echo 0 || echo 1)" "body documents the 2-round fix-loop cap"

out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:implementation-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git merge worktree-agent-abc"}}
EOF2
)"
assert_eq "" "$out" "implementation-orchestrator can git merge"
out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:implementation-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git push origin master"}}
EOF2
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "implementation-orchestrator cannot push"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_implementation_orchestrator_spawns.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_implementation_orchestrator_spawns.sh`
Expected: `FAIL` en `agents/implementation-orchestrator.md exists`, exit 1.

- [ ] **Step 3: Escribir `agents/implementation-orchestrator.md`**

```bash
cat > agents/implementation-orchestrator.md <<'EOF'
---
name: implementation-orchestrator
description: Use when the root orchestrator needs ONE phase of an arbitrado plan actually built — sequences test-writer (RED) → implementer (isolated worktree, GREEN) → quality-fixer → reviewer (gate BEFORE merge) → local merge to the run's branch. Never asks the owner, never touches master or a remote.
model: sonnet
tools: Read, Grep, Bash, Agent(test-writer,implementer,quality-fixer,reviewer), SendMessage
maxTurns: 25
memory: project
skills: [swarm-protocol]
---

# implementation-orchestrator

Dominio implementation del enjambre (spec §7 "Implementación", §15 fase 5). Ejecutas **UNA fase**
de un plan `arbitrado` de `planner` (fase 4) por invocación — nunca el plan entero de una sentada
(tu `maxTurns: 25` no daría para más de una). **No encadenas automáticamente tras `design`, ni en
`tier: full`** — la raíz te lanza solo con una invocación explícita y separada del owner (decisión
de seguridad de fase 5: escribir/fusionar código real merece un checkpoint humano entre "aquí está
el plan" y "ahora se construye"). Nunca ejecutas trabajo de hoja (§3.2 regla 4): no escribes código
tú mismo, delegas siempre.

## Contexto de arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `swarm-root:` es la ruta absoluta de
   `.swarm/`. `operation:` es `implement-phase`. `plan:` es la ruta absoluta del fichero de plan.
   `phase:` es la fase concreta a implementar (si viene vacía, elige la primera fase del plan con
   algún `- [ ]` Step sin marcar — `Read` el plan y busca el primer `- [ ]` desde el principio).
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/implementation-orchestrator.md" 2>/dev/null
   ```
3. Lee con `Read` (cuenta para `files=`): el fichero de plan completo, confirma que la fase elegida
   existe y tiene al menos un `- [ ]` sin marcar. Si TODA la fase ya está `[x]`, tu veredicto es
   `DONE · fase ya implementada` sin lanzar a nadie.

## Secuencia (en este orden, nunca en paralelo — cada paso depende del anterior)

### 1. `test-writer` (RED, commit directo a la rama actual del run)

```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: write-test
plan: <ruta absoluta del plan>
phase: <la fase elegida>
```
Regístralo en el manifest primero:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register --run "${RUN:-adhoc}" --agent test-writer --domain implementation --area "." --owner implementation-orchestrator
```
Espera su `DONE`. Anota el SHA del commit que acaba de crear (`git log -1 --format=%H`, cuenta
para `cmds=`) — es el `base` que `reviewer` necesitará. Si `BLOCKED`, propaga su motivo, no sigas.

### 2. `implementer` (isolation: worktree, GREEN, commit en su propia rama)

**No preexiste**: lo LANZAS con el tool `Agent` — nunca `SendMessage` (la lección de fase 1/1b/2/
3/4, aplicada una sexta vez; tu frontmatter declara
`Agent(test-writer,implementer,quality-fixer,reviewer)` y
`tests/test_implementation_orchestrator_spawns.sh` lo vigila).
```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: implement
plan: <ruta absoluta del plan>
phase: <la misma fase>
```
Espera su `DONE`. **Anota el `agentId` del spawn** (línea `agentId: <id>` del resultado del
lanzamiento) — necesitas la ruta `.claude/worktrees/agent-<agentId>` para `quality-fixer`,
`reviewer`, el merge final, y la limpieza. Si `BLOCKED`, propaga su motivo — es una pregunta real
para el owner, no relances a nadie más.

### 3. `quality-fixer` (apunta al worktree de `implementer`, sin isolation propia)

```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: fix
worktree: <ruta absoluta, .claude/worktrees/agent-<agentId del paso 2>>
```
Espera su `OK`.

### 4. `reviewer` — gate ANTES de fusionar, nunca después

```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: review
worktree: <la misma ruta absoluta>
base: <el SHA que anotaste en el paso 1>
```
Espera su veredicto. Si trae hallazgos `Critical`/`Important`: relanza `implementer` (MISMO
`agentId`, mismo worktree — cabecera con `operation: implement-fix` y un resumen de los hallazgos
en `context:`) y repite los pasos 3-4. **Máximo 2 rondas de relanzamiento**: si tras la 2ª vuelta
sigue habiendo `Critical`/`Important`, adjudica tú mismo (mismo patrón de breaker que
`subagent-driven-development`): si el hallazgo es genuinamente bloqueante, tu veredicto final es
`BLOCKED <hallazgo concreto>` sin fusionar nada; si no es load-bearing, fusiona igualmente y anota
`- riesgo aparcado: <hallazgo>` en tu salida — nunca fusiones en silencio un hallazgo Critical sin
decidir explícitamente qué hiciste con él. Hallazgos `Minor` nunca bloquean el merge.

## Merge — SIEMPRE local, a la rama ACTUAL del run, NUNCA a `master`/una rama compartida

Solo tras el gate limpio (o aparcado con juicio explícito):
```bash
git merge worktree-agent-<agentId del paso 2>
```
Es una fusión LOCAL a la rama donde corre este run — nunca `git push`, nunca `master` directo,
nunca una rama remota. Empujar o abrir PR es responsabilidad exclusiva de `delivery-orchestrator`/
`release-manager` (fase 6, todavía sin construir); este dominio nunca toca remoto.

Después, limpia el worktree (mismo patrón que `discovery-orchestrator` con `feasibility-spiker` en
fase 2 — fallo blando, nunca cambia tu veredicto):
```bash
git worktree remove .claude/worktrees/agent-<agentId del paso 2> --force
```

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:implementation-orchestrator`: `scripts/mem-*.sh`, `git status|log|diff|show|
rev-parse`, **`git merge`**, **`git worktree`** (los dos únicos aquí, para fusionar y limpiar),
`ls|cat|head|tail|wc|grep`. Nada de `git push`, `python3`, `echo`, `mkdir`, `rm`; denegación por
segmento. El `git merge`/`git worktree remove` van en su PROPIA llamada, nunca encadenados con
`&&` a otro comando.

## Salida

```
DONE
evidence: files=2 cmds=6 turns=18/25
- implementation: Phase 1 fusionada (test-writer+implementer+quality-fixer, reviewer limpio a la 1ª), 3 steps marcados [x]
```

`BLOCKED <hallazgo>` si `reviewer` sigue Critical tras 2 rondas. `KO <hoja> BLOCKED: <motivo>` si
`test-writer`/`implementer` no pudo completar su parte. `DONE · fase ya implementada` si todos los
steps de la fase ya estaban `[x]`, sin lanzar a nadie. `OK`/`DONE` con `files=0` se rechaza siempre.
EOF
```

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_implementation_orchestrator_spawns.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 33, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/implementation-orchestrator.md tests/test_implementation_orchestrator_spawns.sh
git commit -m "feat(implementation): implementation-orchestrator — TDD real, gate antes de fusionar, merge local"
```

---

### Task 7: Integración en la raíz (`agents/orchestrator.md`)

**Files:**
- Modify: `agents/orchestrator.md` (nueva sección `## 10. Implementación`, actualizar §1.0/§4)
- Create: `tests/test_orchestrator_implementation.sh`

**Interfaces:**
- Consumes: `swarm:implementation-orchestrator` de Task 6.
- Produces: la raíz con 6 dominios disponibles.

- [ ] **Step 1: Escribir el test de integración (falla primero)**

```bash
cat > tests/test_orchestrator_implementation.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_orchestrator_implementation.sh — la raíz integra el dominio implementation (spec §15
# fase 5): SOLO por invocación explícita, nunca encadenado tras discovery/design.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" 'subagent_type: "swarm:implementation-orchestrator"')" "root launches implementation-orchestrator by type"
assert_eq "0" "$(has "$body" 'name: "implementation-orchestrator"')" "root names it exactly implementation-orchestrator"
assert_eq "0" "$(has "$body" 'operation: implement-phase')" "root passes operation: implement-phase"
assert_eq "0" "$(has "$body" 'NUNCA encadena')" "root explicitly documents implementation NEVER auto-chains after design"
assert_eq "1" "$(has "$body" 'implementation-orchestrator, fase 5')" "root no longer says implementation-orchestrator is unimplemented"
assert_eq "0" "$(has "$body" '## 10. Implementación')" "root has a dedicated §10 Implementación section"
assert_eq "0" "$(has "$body" 'checkpoint humano')" "root documents the human checkpoint rationale for not auto-chaining"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_orchestrator_implementation.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_orchestrator_implementation.sh`
Expected: varios `FAIL`.

- [ ] **Step 3: Actualizar §1.0 "Alcance actual"**

Localiza el párrafo `**Alcance actual...` y reemplaza el texto entre "dominios disponibles:" y "TODAVÍA NO EXISTEN" para incluir `implementation-orchestrator` (fase 5, §10) entre los construidos,
y dejar solo `delivery-orchestrator` (fase 6) en la lista de no construidos.

- [ ] **Step 4: Añadir `## 10. Implementación` al final del fichero**

```bash
cat >> agents/orchestrator.md <<'EOF'

## 10. Implementación (fase 5 — SOLO por invocación explícita, nunca encadenada, spec §7 "Implementación")

### 10.1 Cuándo

**NUNCA encadenas automáticamente tras discovery/design, ni siquiera en `tier: full`.** A
diferencia de discovery→design (§5.4→§9), aquí hay una razón de seguridad explícita: escribir y
fusionar código real es la acción más consecuente del enjambre, y el cierre de un run de
discovery+design (con el plan ya escrito, legible, en `docs/superpowers/plans/`) es el
**checkpoint humano** natural antes de autorizar que se ejecute. Lanzas `implementation-orchestrator`
solo cuando el objetivo del owner lo pide explícitamente ("implementa el plan de X", "construye X
según el plan ya diseñado") — nunca como continuación automática de otro dominio.

### 10.2 Lanzamiento

```
Agent(subagent_type: "swarm:implementation-orchestrator", name: "implementation-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <ruta absoluta de .swarm>
  operation: implement-phase
  plan: <ruta absoluta del plan a implementar>
  phase: <fase concreta, o vacío para que él elija la primera pendiente>)
```

Regístralo antes en el manifest:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register --run <run-id> --agent implementation-orchestrator --domain implementation --area "." --owner orchestrator
```

### 10.3 Reenviar el resultado

Reenvía su línea `- implementation: …` tal cual a tu propia salida (§7) — sin pasarla por el
saneado de §5.0 (no construyes ningún `--text`/`--line` nuevo con ella). Si devuelve `BLOCKED …`/
`KO …`, propaga su veredicto literal — cierra el run igual que cualquier otro camino terminal (§4).

### 10.4 Cierre

- implementación completada: `- run cerrado: DONE · fase implementada, fusionada localmente`
- `BLOCKED`/`KO` propagado: `- run cerrado: <veredicto literal de implementation-orchestrator>`
EOF
```

- [ ] **Step 5: Confirmar que el test pasa**

Run: `bash tests/test_orchestrator_implementation.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 6: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 34, failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add agents/orchestrator.md tests/test_orchestrator_implementation.sh
git commit -m "feat(implementation): integra implementation-orchestrator en la raíz (§10, solo invocación explícita)"
```

---

### Task 8: Checklist de smoke en vivo + cierre de fase

**Files:**
- Create: `docs/superpowers/plans/2026-09-03-phase5a-smoke-checklist.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: evidencia real, gate antes de dar la fase por cerrada.

- [ ] **Step 1: Escribir el checklist (plantilla, se rellena en vivo)**

```bash
cat > docs/superpowers/plans/2026-09-03-phase5a-smoke-checklist.md <<'EOF'
# Checklist de smoke — Fase 5a implementation (`implementation-orchestrator` + test-writer/implementer/quality-fixer/reviewer)

Gate. Fixture: `tests/lib.sh::make_fixture`. **Riesgo real no verificado hasta este smoke**: la
cadena completa test-writer(RED, commit)→implementer(worktree aislado, GREEN, commit)→
quality-fixer→reviewer(gate)→merge local→limpieza de worktree, nunca ejercitada de punta a punta.
Requiere un plan real ya escrito (fase 4) contra el que implementar — generarlo primero con un run
de design real (mismo mecanismo ya probado en el smoke de fase 4), o escribir uno a mano mínimo
con una sola fase simple si el tiempo/turnos no dan para encadenar discovery+design+implementation
en una sesión.

## 1. Ciclo completo: RED → worktree aislado → GREEN → quality → review limpio → merge → limpieza

Evidencia:

## 2. `implementer` NUNCA modifica el checkout principal — solo su worktree

`git status --porcelain` en el checkout principal, antes y después del run: debe seguir limpio
durante todo el ciclo (todo el trabajo real vive en el worktree aislado hasta el merge explícito).
Evidencia:

## 3. Gate de reviewer bloquea el merge cuando hay Critical

Provocar un hallazgo Critical real (p. ej. un fixture con un bug de aislamiento de tenant
deliberado) y confirmar que `implementation-orchestrator` relanza `implementer` en vez de fusionar
directo.
Evidencia:

## 4. El plan se marca `[x]` correctamente tras el merge

El fichero de plan en el checkout principal, tras el merge, tiene los `- [ ] Step N` de la fase
implementada como `- [x]` — confirma que el mecanismo de progreso (checkboxes del propio plan)
sobrevive el merge intacto.
Evidencia:

## 5. Ningún push, ninguna rama compartida tocada

`git log --all --oneline` tras el run: solo la rama del run tiene commits nuevos; ninguna
operación de red (`git push`) se intentó en ningún momento — confirmado por ausencia total de
`git push` en el allowlist de cualquier agente de este dominio (verificado también por code
review de Task 1/6).
Evidencia:

## Firma

- [ ] Owner: sesión autónoma — Fecha: ________________
EOF
```

- [ ] **Step 2: Ejecutar el smoke en vivo**

Metodología headless (`claude -p --plugin-dir <este worktree> --permission-mode bypassPermissions`)
contra un fixture desechable. Si algún bug real aparece, arreglarlo inmediatamente (regla del
owner: "Arregla todos los Bugs que encuentres siempre").

- [ ] **Step 3: Review final de rama (Opus)**

Igual patrón que fases 1-4: dispatch sobre TODO el diff de la rama antes de mergear. Cualquier
hallazgo Important/Critical se arregla y se re-verifica.

- [ ] **Step 4: Commit del checklist relleno**

```bash
git add docs/superpowers/plans/2026-09-03-phase5a-smoke-checklist.md
git commit -m "docs: checklist de smoke fase 5a relleno con evidencia real de ejecución en vivo"
```

- [ ] **Step 5: `finishing-a-development-branch` → merge → handoff**

Mismo patrón: verificar tests, mergear local a master (instrucción permanente del owner, sin
preguntar), limpiar worktree/rama, reescribir el handoff con el estado final de fase 5a y el
siguiente paso (fase 5b — stack pack `php-ddd-symfony8`; fase 5c — migration-engineer, doc-writer,
dependency-auditor/installer; luego fase 6 — delivery).

## Self-Review

**Cobertura del spec:** §7 "Implementación" (4 de 7 agentes) → Tasks 2-6. §9.3 (worktrees) →
verificado en vivo con el spike previo a este plan (branch `worktree-agent-<agentId>`, contenido
NO auto-commiteado). §15 fase 5 → Tasks 7-8.

**Riesgo genuino no resuelto por diseño, solo por verificación en vivo:** el ciclo completo de 5
agentes encadenados con merge real nunca se ha ejecutado de punta a punta — Task 8 lo verifica
explícitamente.

**Placeholders:** ninguno.

**Consistencia de nombres:** `test-writer`/`implementer`/`quality-fixer`/`reviewer`/
`implementation-orchestrator` y sus tags (`REVIEW`) idénticos en `bash-allowlist.json` (Task 1),
`Agent(...)` de Task 6, tabla de lanzamiento, §10 de `agents/orchestrator.md` (Task 7). Verificado
por búsqueda cruzada.
