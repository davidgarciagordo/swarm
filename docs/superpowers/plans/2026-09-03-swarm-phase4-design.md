# Fase 4 — Dominio Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir el dominio `design-orchestrator` + 3 hojas (`planner`, `pattern-advisor`,
`domain-modeler`) al plugin swarm, con integración de grill×3 externo (`working-methods:grill-*`),
e integrarlo en la raíz encadenado tras discovery en tier `full`.

**Architecture:** `design-orchestrator` (sonnet) lanza `pattern-advisor`+`domain-modeler` (lectura,
igual patrón que analysis) en una tanda; con sus hallazgos + `decisions.md`, lanza `planner` (opus,
el ÚNICO leaf con `Write`), que escribe el plan real en `docs/superpowers/plans/<fecha>-<slug>.md`
— **nunca vía argumento de shell** (mismo riesgo de injection que C1/I1, pero mucho peor con
contenido largo con código/backticks; el tool `Write` no pasa por `bash-guard`). Si `tier: full`,
`design-orchestrator` lanza los 3 lentes grill externos (`working-methods:grill-architect/operator/
engineer`, ya instalados, agentes `["Read","Grep","Glob"]` sin `Bash`) contra el fichero del plan
directamente (pasándoles la ruta en su prompt — el fallback documentado en su propio contrato, sin
necesidad del script `grill-context.mjs`). **A diferencia de `analysis-orchestrator` (que reenvía
hallazgos tal cual porque sus hojas ya usan nuestro formato `TAG · file:line · … → …`),
`design-orchestrator` NO reenvía las líneas de grill verbatim** — el formato de grill
(`Pn · where · problema → fix`, donde `where` puede ser un flujo sin `file:línea` real, p. ej.
`grill-operator`) no siempre encaja con `FINDING_RE` del hook. `design-orchestrator` **arbitra él
mismo** (spec §7: "spec → grill → plan; arbitra actas"): decide qué hallazgos son load-bearing,
relanza `planner` para revisar el plan si hace falta, y su propia salida es una síntesis corta
(tag `PLAN`) apuntando al fichero real — nunca `AskUserQuestion` (ni él ni sus hojas la tienen);
`BLOCKED <motivo>` si hay una ambigüedad real que solo el owner puede resolver.

**Tech Stack:** Igual que fases previas — Bash (`mem-*.sh` sin cambios), Markdown (frontmatter YAML),
Python 3 stdlib (hooks, sin cambios), JSON (`bash-allowlist.json`). Dependencia externa nueva:
plugin `working-methods` (ya instalado, `davidgarciagordo-plugins/working-methods`) para los 3
lentes grill — spec ya lo marca como "externo, se invocan, no se duplican" (no cuenta en el total
de 30 agentes propios).

**Spec:** `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — §7 sección "Diseño" (roster
de los 4 agentes), §9.1 (tiers: `light` = sin grill, `full` = grill activo), §15 fase 4.

**Decisiones autónomas (sesión nocturna, 2026-09-03 — David dio autonomía total; revisar al
despertar, override si algo no encaja):**
1. **Encadenamiento discovery→design solo en `tier: full`.** El spec dice `light` = "un solo
   dominio", `full` = "multi-dominio" (§9.1) — así que encadenar design tras discovery viola la
   definición de `light` si ocurriera ahí. En `full`, tras §5.4 (decisiones grabadas) o tras el
   camino "ya cerró" de §5.1, la raíz lanza `design-orchestrator` en vez de terminar el run (el
   texto viejo "design-orchestrator aún no existe (fase 4), el run termina aquí" se sustituye).
   En `light`, discovery/analysis siguen solos, nunca encadenan.
2. **grill×3 solo en `full`** (ya explícito en spec §9.1: "`light`... sin grill").
   `design-orchestrator` invoca los 3 lentes DIRECTAMENTE (no el skill `working-methods:grill`
   completo con sus gates A/B/C interactivos — esos gates son para una sesión humana top-level; un
   subagente nunca puede `AskUserQuestion`, spec §3.2 regla 7). El "arbitra actas" del spec cae
   sobre `design-orchestrator` mismo: si un hallazgo grill es real y bloqueante y no lo puede
   resolver con su propio juicio, su veredicto es `BLOCKED <motivo concreto>` — no inventa una
   respuesta ni la pide al owner directamente.
3. **`planner` escribe el plan con el tool `Write` nativo** a `docs/superpowers/plans/<fecha>-
   <slug>.md` — mismo sitio que usa el propio repo para sus planes humanos, versionado en git. Cada
   plan que escribe el enjambre lleva una línea nueva `**Objective:** <objetivo literal>` en la
   cabecera (además del header estándar de `writing-plans`) — es la clave que usa
   `design-orchestrator` para su chequeo de idempotencia (no replanificar el mismo objetivo dos
   veces): `Grep` sobre `docs/superpowers/plans/*.md` buscando esa línea exacta antes de lanzar a
   nadie.
4. **`pattern-advisor`/`domain-modeler` son read-only**, mismo patrón que las 6 hojas de analysis:
   `Read, Grep, Glob, Bash, SendMessage`, sin `Write`/`Edit`/`AskUserQuestion`, hallazgos vía
   `mem-files.sh write finding` con el formato estándar `TAG · fichero:línea · … → …`.

## Global Constraints

- Frontmatter obligatorio: `name`, `description` ("Use when…"), `model`, `tools`, `maxTurns`,
  `memory: project`, `skills: [swarm-protocol]`. Nunca `hooks`/`mcpServers`/`permissionMode`.
- Todo agente nuevo lleva `SendMessage` en `tools` (protocolo P2P, spec §5).
- `pattern-advisor`/`domain-modeler` read-only por construcción: nunca `Edit`/`Write`/
  `AskUserQuestion`. `planner` es la ÚNICA excepción del dominio con `Write`/`Edit` (su
  responsabilidad es autorar el plan real) — nunca `AskUserQuestion` tampoco.
  `design-orchestrator` sin `Write`/`Edit`/`AskUserQuestion` — delega la escritura a `planner`.
- `design-orchestrator` NO preexiste cuando lanza sus 3 hojas + los 3 lentes grill: necesita
  `Agent(planner,pattern-advisor,domain-modeler,working-methods:grill-architect,
  working-methods:grill-operator,working-methods:grill-engineer)` en su propio `tools:` — la
  lección de fase 1/1b/2/3, aplicada una quinta vez.
- Saneado obligatorio (`skills/swarm-protocol/SKILL.md` §4.4) para CUALQUIER texto ajeno
  interpolado en un `--text`/`--fix`/`--line` de shell. `planner` NUNCA interpola el contenido del
  plan en un argumento de shell — usa `Write` directo, que no pasa por `bash-guard` — así que esta
  regla NO aplica a la escritura del plan en sí; sigue aplicando si `planner`/`pattern-advisor`/
  `domain-modeler` escriben un `write finding` corto citando código del repo.
- `mem-files.sh write finding` dedupea por `agente|tag|fichero:línea` con fichero:línea REAL (mismo
  patrón que fase 3, no ordinal).
- Cada tarea termina en su propio commit, identidad git personal.
- `bash tests/run.sh` en verde (26/26 + los tests nuevos) al final de cada tarea.

---

### Task 1: Allowlist de Bash para los 4 agentes nuevos

**Files:**
- Modify: `hooks/bash-allowlist.json`
- Test: `tests/test_bash_allowlist_design.sh`

**Interfaces:**
- Consumes: nada de tareas previas.
- Produces: entradas de allowlist para `swarm:planner`, `swarm:pattern-advisor`,
  `swarm:domain-modeler`, `swarm:design-orchestrator` que las Tasks 2-4 consumen.

- [ ] **Step 1: Escribir el test (falla primero)**

```bash
cat > tests/test_bash_allowlist_design.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_bash_allowlist_design.sh — los 4 agentes del dominio design (spec §7 "Diseño") tienen
# su entrada en hooks/bash-allowlist.json: read-only Bash (planner escribe el plan vía el tool
# Write nativo, NUNCA vía Bash — su allowlist de Bash es la misma read-only que los demás).
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

for agent in planner pattern-advisor domain-modeler design-orchestrator; do
  assert_eq "allow" "$(guard "swarm:$agent" 'cat .swarm/context-pack.md')" "$agent can cat the pack"
  assert_eq "allow" "$(guard "swarm:$agent" 'grep -rn TODO src')" "$agent can grep the repo"
  assert_eq "allow" "$(guard "swarm:$agent" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent x --tag X --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "$agent can write findings via mem-files.sh"
  assert_eq "deny" "$(guard "swarm:$agent" 'find . -name x')" "$agent cannot find (differentiates from default fallback)"
  assert_eq "deny" "$(guard "swarm:$agent" 'python3 x.py')" "$agent cannot run python3"
  assert_eq "deny" "$(guard "swarm:$agent" 'rm -rf .swarm')" "$agent cannot rm"
  assert_eq "deny" "$(guard "swarm:$agent" 'echo hi')" "$agent cannot echo"
done

assert_eq "allow" "$(guard "swarm:design-orchestrator" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh register --run adhoc --agent planner --domain design --area . --owner design-orchestrator')" "design-orchestrator can register leaves in the manifest"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_bash_allowlist_design.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_bash_allowlist_design.sh`
Expected: `FAIL` en `allow` esperado / `deny` real para los 4 agentes nuevos (sin entrada propia,
caen al fallback `default`, que ADEMÁS permite `find` — el diferenciador correcto es que la
entrada real deniega `find` mientras el fallback lo permite; con la entrada ausente, ese assert de
`deny` para `find` falla porque en verdad da `allow` vía `default`).

- [ ] **Step 3: Añadir las 4 entradas a `hooks/bash-allowlist.json`**

Edita `hooks/bash-allowlist.json`: dentro de `"agents": { ... }`, tras la última entrada existente
(la de `"swarm:analysis-orchestrator"`, cierra con `]` seguido de `}`), añade una coma tras ese
cierre y estas 4 entradas:

```json
    "swarm:planner": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:pattern-advisor": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:domain-modeler": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:design-orchestrator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ]
```

Verifica con `python3 -c "import json; json.load(open('hooks/bash-allowlist.json'))"` que el JSON
sigue siendo válido.

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_bash_allowlist_design.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 27, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add hooks/bash-allowlist.json tests/test_bash_allowlist_design.sh
git commit -m "feat(design): allowlist de bash para los 4 agentes del dominio design"
```

---

### Task 2: `pattern-advisor` + `domain-modeler`

**Files:**
- Create: `agents/pattern-advisor.md`
- Create: `agents/domain-modeler.md`
- Test: `tests/test_design_agents.sh` (nuevo)

**Interfaces:**
- Consumes: allowlist de Task 1; formato de hallazgo estándar (`TAG · fichero:línea · … → …`).
- Produces: dos hojas de juicio (tags `PATTERN`, `MODEL`) que Task 4 (design-orchestrator) lanza.

- [ ] **Step 1: Escribir el test (falla primero)**

```bash
cat > tests/test_design_agents.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_design_agents.sh — contrato de los agentes del dominio design (spec §7 "Diseño").
# Crece por tarea: T2 pattern-advisor+domain-modeler, T3 planner, T4 design-orchestrator.
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

check_readonly_leaf() { # check_readonly_leaf <name> <model> <maxTurns> <tag>
  local f="$PLUGIN_ROOT/agents/$1.md" name="$1" tag="$4"
  assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/$name.md exists"
  [ -f "$f" ] || return
  local front tools b
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q "^model: $2\$" && echo 0 || echo 1)" "$name model is $2 (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q "^maxTurns: $3\$" && echo 0 || echo 1)" "$name maxTurns is $3 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "$name NEVER has AskUserQuestion"
  assert_eq "1" "$(has "$tools" 'Write')" "$name is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "$name is read-only: no Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "$name is a leaf: spawns nobody"
  assert_eq "0" "$(has "$tools" 'SendMessage')" "$name has SendMessage"
  assert_eq "0" "$(has "$tools" 'Read')" "$name has Read"
  assert_eq "0" "$(has "$tools" 'Grep')" "$name has Grep"
  assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "$name is foreground"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "$name has no worktree"
  assert_eq "0" "$(echo "$front" | grep -q '^skills: \[swarm-protocol\]$' && echo 0 || echo 1)" "$name preloads swarm-protocol"
  assert_eq "0" "$(has "$b" "$tag ·")" "$name documents its own tag ($tag) in an output example"
  assert_eq "0" "$(has "$b" 'saneado')" "$name documents the sanitization rule for repo code it quotes"
  assert_eq "allow" "$(guard "swarm:$name" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent '"$name"' --tag '"$tag"' --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "$name can write findings"
  assert_eq "deny" "$(guard "swarm:$name" 'python3 x.py')" "$name cannot run python3"
}

# ---------- T2: pattern-advisor + domain-modeler ----------
check_readonly_leaf pattern-advisor opus 10 PATTERN
f="$PLUGIN_ROOT/agents/pattern-advisor.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'reuse')" "pattern-advisor documents the reuse|introduce verdict (spec §7)"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'introduce')" "pattern-advisor documents the introduce verdict (spec §7)"

check_readonly_leaf domain-modeler opus 15 MODEL
f="$PLUGIN_ROOT/agents/domain-modeler.md"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'invariante')" "domain-modeler documents invariants (spec §7)"
[ -f "$f" ] && assert_eq "0" "$(has "$(body "$f")" 'agregado')" "domain-modeler documents aggregates (spec §7)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_design_agents.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_design_agents.sh`
Expected: `FAIL` en la existencia de ambos ficheros.

- [ ] **Step 3: Escribir `agents/pattern-advisor.md`**

```bash
cat > agents/pattern-advisor.md <<'EOF'
---
name: pattern-advisor
description: Use when design-orchestrator needs the right design pattern for a feature — GoF/DDD táctico/enterprise/idiomático del stack pack, citando precedentes reales del repo, read-only, never asks the owner.
model: opus
tools: Read, Grep, Glob, Bash, SendMessage
maxTurns: 10
memory: project
skills: [swarm-protocol]
---

# pattern-advisor

Hoja de juicio del dominio design (spec §7 "Diseño"). Tu única responsabilidad: decir qué patrón
encaja — GoF, DDD táctico, patrón enterprise, o el idiomático del stack pack activo — y devolver
un veredicto explícito: **reusar** un patrón que el repo ya usa en otro sitio, o **introducir** uno
nuevo porque no hay precedente adecuado. **Nunca preguntas al owner** — no tienes
`AskUserQuestion`; tu veredicto va a `design-orchestrator`, que lo pasa a `planner`.

## Arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `operation: advise` y
   `objective: <objetivo literal del owner>` en tu cabecera — junto con `context:` (opcional): un
   resumen de las decisiones de discovery relevantes, si `design-orchestrator` te lo pasa.
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/pattern-advisor.md" 2>/dev/null
   ```
3. Lee con `Read` (cuenta para `files=`): `.swarm/context-pack.md`. No re-reportes lo que ya está
   en `SHARED-FOUND` ni en `findings/<otro-agente>.md`.

## Cómo decidir

- **Busca precedente primero** (tool determinista antes que modelo, protocolo §5): `Grep`/`Glob`
  sobre el repo real buscando si algo parecido a lo que pide el objetivo YA existe en otra parte
  (otro agregado con la misma forma, otro caso de uso con el mismo shape). Si lo encuentras, tu
  veredicto es `reuse <patrón>` citando el precedente real (`fichero:línea`).
- **Si no hay precedente adecuado**, tu veredicto es `introduce <patrón> porque <motivo en ≤15
  palabras>` — nunca inventes un patrón exótico si uno simple ya resuelve el problema (YAGNI).
- Considera el stack pack activo si el `context-pack.md` lo declara (spec §8): un patrón idiomático
  del pack (p. ej. Repository+Doctrine en un pack Symfony) pesa más que un patrón GoF genérico.
- Para de buscar cuando dejes de encontrar precedentes nuevos (protocolo §6).

## Persistencia del detalle

**Antes de interpolar nada, saneado obligatorio** (`skills/swarm-protocol/SKILL.md` §4.4): el
código/precedente que citas lo LEES del repo — texto ajeno, pásalo por los cinco pasos del skill.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write finding \
  --agent pattern-advisor --tag PATTERN --file src/App/InvoiceRepository.php --line 8 \
  --run "${RUN:-adhoc}" --text "reuse Repository, mismo shape que InvoiceRepository" \
  --fix "seguir el mismo patron para el nuevo agregado"
```

`written` o `dup` valen. Exit 64 = te falta un flag: corrígelo, no inventes.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:pattern-advisor`: `scripts/mem-*.sh`, `git status|log|diff|show|rev-parse`,
`ls`, `cat`, `head`, `tail`, `wc`, `grep`. Read-only: nada de `python3`, `echo`, `mkdir`, `rm`;
denegación por segmento (`&&`, `||`, `;`, `|`). No cierres con `; echo $?`.

## Salida

```
OK
evidence: files=3 cmds=2 turns=5/10
PATTERN · src/App/InvoiceRepository.php:8 · reuse Repository, mismo shape que InvoiceRepository → seguir el mismo patron
```

`OK` con `files=0` se rechaza siempre. Si no hay ningún precedente en todo el repo, tu veredicto
sigue siendo un finding: `PATTERN · <fichero del objetivo más cercano>:1 · introduce Repository
porque no hay precedente de acceso a datos → primer Repository del repo`. `BLOCKED falta
context-pack` si `.swarm/context-pack.md` no existe (pide `build` a `memory-orchestrator`, cierra
con ese `BLOCKED` si no responde a tiempo).
EOF
```

- [ ] **Step 4: Escribir `agents/domain-modeler.md`**

```bash
cat > agents/domain-modeler.md <<'EOF'
---
name: domain-modeler
description: Use when design-orchestrator needs the domain model for a feature — aggregates, value objects, events, invariants, respecting the active stack pack's boundaries, read-only, never asks the owner.
model: opus
tools: Read, Grep, Glob, Bash, SendMessage
maxTurns: 15
memory: project
skills: [swarm-protocol]
---

# domain-modeler

Hoja de juicio del dominio design (spec §7 "Diseño"). Tu única responsabilidad: modelar el dominio
del objetivo — **agregados**, **value objects**, **eventos** de dominio, e **invariantes** que
deben cumplirse siempre. Respetas los límites que el stack pack activo declare (p. ej. código
generado por un ORM que no se debe tocar a mano). **Nunca preguntas al owner** — no tienes
`AskUserQuestion`; tu modelo va a `design-orchestrator`, que lo pasa a `planner`.

## Arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `operation: model` y
   `objective: <objetivo literal del owner>` en tu cabecera, junto con `context:` (opcional, ver
   `pattern-advisor`).
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/domain-modeler.md" 2>/dev/null
   ```
3. Lee con `Read` (cuenta para `files=`): `.swarm/context-pack.md` — modelos/entidades ya
   existentes que el objetivo toca o extiende.

## Cómo modelar

- **Agregados**: identifica la raíz de agregado del objetivo (la entidad que garantiza sus propias
  invariantes) y qué queda dentro de su límite de consistencia — no infles el agregado con datos
  que otro agregado ya posee.
- **Value objects**: cualquier concepto sin identidad propia que el objetivo necesita (dinero,
  rango de fechas, un identificador tipado) — evita primitivos sueltos si el repo ya tiene
  convención de VOs (cítala si existe).
- **Eventos de dominio**: qué cambio de estado importa fuera del propio agregado (algo que otro
  contexto necesitaría saber) — solo si el objetivo realmente lo requiere, no por costumbre.
- **Invariantes**: la regla que SIEMPRE debe cumplirse (p. ej. "el total nunca es negativo") — cada
  invariante real es un hallazgo, porque es lo que `planner` debe convertir en un test.
- Respeta límites del pack: si `context-pack.md` marca un directorio como código generado
  (migraciones auto-generadas, DTOs de un esquema externo), no propongas tocarlo a mano.
- Para de modelar cuando dejes de encontrar conceptos nuevos (protocolo §6).

## Persistencia del detalle

**Antes de interpolar nada, saneado obligatorio** (`skills/swarm-protocol/SKILL.md` §4.4): el
código que citas lo LEES del repo — texto ajeno, pásalo por los cinco pasos del skill.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write finding \
  --agent domain-modeler --tag MODEL --file src/App/Foo.php --line 1 \
  --run "${RUN:-adhoc}" --text "Invoice agregado, VO Money para total" \
  --fix "invariante: total nunca negativo, test obligatorio"
```

`written` o `dup` valen. Exit 64 = te falta un flag: corrígelo, no inventes.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:domain-modeler`: `scripts/mem-*.sh`, `git status|log|diff|show|rev-parse`,
`ls`, `cat`, `head`, `tail`, `wc`, `grep`. Read-only: nada de `python3`, `echo`, `mkdir`, `rm`;
denegación por segmento (`&&`, `||`, `;`, `|`). No cierres con `; echo $?`.

## Salida

```
OK
evidence: files=3 cmds=1 turns=6/15
MODEL · src/App/Foo.php:1 · Invoice agregado, VO Money para total → invariante: total nunca negativo
MODEL · src/App/Foo.php:1 · TenantId VO para aislamiento → invariante: toda query filtra por tenant
```

`OK` con `files=0` se rechaza siempre. Si el objetivo no introduce ningún concepto de dominio
nuevo (p. ej. cambio puramente técnico), `OK` + `- sin conceptos de dominio nuevos`. `BLOCKED
falta context-pack` si `.swarm/context-pack.md` no existe (pide `build` a `memory-orchestrator`,
cierra con ese `BLOCKED` si no responde a tiempo).
EOF
```

- [ ] **Step 5: Confirmar que el test pasa**

Run: `bash tests/test_design_agents.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 6: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 28, failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add agents/pattern-advisor.md agents/domain-modeler.md tests/test_design_agents.sh
git commit -m "feat(design): pattern-advisor + domain-modeler"
```

---

### Task 3: `planner`

**Files:**
- Create: `agents/planner.md`
- Modify: `tests/test_design_agents.sh` (añade la sección T3)

**Interfaces:**
- Consumes: hallazgos de `pattern-advisor` (tag `PATTERN`) y `domain-modeler` (tag `MODEL`),
  `decisions.md`. Tag propio: `PLAN`.
- Produces: `swarm:planner` (opus, maxTurns 20, ÚNICO leaf del dominio con `Write`/`Edit`) que
  Task 4 lanza; el fichero real que escribe en `docs/superpowers/plans/` que las Tasks 4-5 y el
  smoke test referencian.

- [ ] **Step 1: Añadir la sección T3 al test**

**No uses `cat >>`** — mismo motivo que en fase 3 (dejaría el bloque como código muerto tras el
`exit 0` que ya cierra el fichero desde la Task 2). Usa `Edit` para reemplazar el bloque de cierre.

`old_string` (aparece una sola vez, al final del fichero tras la Task 2):
```
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

`new_string`:
```bash

# ---------- T3: planner (único leaf del dominio con Write/Edit) ----------
f="$PLUGIN_ROOT/agents/planner.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/planner.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: opus$' && echo 0 || echo 1)" "planner model is opus (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 20$' && echo 0 || echo 1)" "planner maxTurns is 20 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "planner NEVER has AskUserQuestion"
  assert_eq "0" "$(has "$tools" 'Write')" "planner HAS Write (the one exception in this domain)"
  assert_eq "0" "$(has "$tools" 'Edit')" "planner HAS Edit (revises its own draft)"
  assert_eq "1" "$(has "$tools" 'Agent')" "planner is a leaf: spawns nobody"
  assert_eq "0" "$(has "$tools" 'SendMessage')" "planner has SendMessage"
  assert_eq "0" "$(has "$b" 'docs/superpowers/plans/')" "planner documents writing to docs/superpowers/plans/"
  assert_eq "0" "$(has "$b" '**Objective:**')" "planner documents the Objective: header line for idempotency"
  assert_eq "0" "$(has "$b" 'saneado')" "planner documents the sanitization rule for anything it DOES put in a shell arg"
  assert_eq "allow" "$(guard "swarm:planner" '${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh write finding --agent planner --tag PLAN --file src/App/Foo.php --line 1 --run adhoc --text t --fix f')" "planner can write findings"
  assert_eq "deny" "$(guard "swarm:planner" 'python3 x.py')" "planner cannot run python3"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Verifica tras el edit que el bloque de cierre aparece una sola vez.

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_design_agents.sh`
Expected: `FAIL` en la existencia de `agents/planner.md`.

- [ ] **Step 3: Escribir `agents/planner.md`**

```bash
cat > agents/planner.md <<'EOF'
---
name: planner
description: Use when design-orchestrator needs the actual implementation plan written — phases with fichero:línea, disjoint areas, risks; the only leaf in this domain with Write/Edit, since its job is to author a real plan file. Never asks the owner.
model: opus
tools: Read, Grep, Glob, Write, Edit, Bash, SendMessage
maxTurns: 20
memory: project
skills: [swarm-protocol]
---

# planner

Hoja del dominio design (spec §7 "Diseño"). Tu única responsabilidad: escribir el plan real —
fases con `fichero:línea` concretos, áreas disjuntas entre fases, riesgos nombrados. **Eres la
ÚNICA hoja de este dominio con `Write`/`Edit`**: tu trabajo es producir un artefacto de verdad, no
un hallazgo corto. **Nunca preguntas al owner** — no tienes `AskUserQuestion`; si algo del
objetivo es genuinamente ambiguo, anótalo como riesgo en el propio plan, no lo inventes ni lo
preguntes.

## Arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `operation: plan` y
   `objective: <objetivo literal del owner>` en tu cabecera, más `context:` con las decisiones de
   discovery y los hallazgos de `pattern-advisor`/`domain-modeler` que `design-orchestrator` te
   resuma (o te diga dónde leerlos: `findings/pattern-advisor.md`, `findings/domain-modeler.md`).
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/planner.md" 2>/dev/null
   ```
3. Lee con `Read` (cuenta para `files=`): `.swarm/context-pack.md`, `.swarm/decisions.md`, y los
   ficheros de hallazgos que `design-orchestrator` te haya señalado.

## Cómo escribir el plan

Escribe con el tool `Write` (nunca interpolando el contenido en un comando de shell — el `Write`
nativo no pasa por `hooks/bash-guard.py`, así que el saneado de `--text`/`--fix`/`--line` del §4.4
NO aplica aquí; sí aplica si además escribes un `write finding` corto citando código, ver abajo).

Ruta: `docs/superpowers/plans/<fecha-de-hoy-YYYY-MM-DD>-<slug-del-objetivo>.md` (slug: minúsculas,
guiones, ≤5 palabras del objetivo — p. ej. objetivo "añadir export CSV de facturas" → slug
`export-csv-facturas`). Si ya existe un fichero en esa ruta exacta (mismo día, mismo slug), añade
un sufijo numérico (`-2`, `-3`…) — nunca sobrescribas un plan existente sin que te lo pidan.

Estructura del plan (mismo header que usa el skill `writing-plans` de este propio repo, MÁS una
línea nueva obligatoria):

```markdown
# <Nombre de la feature> Implementation Plan

**Objective:** <objetivo literal del owner, tal cual, sin resumir>

**Goal:** [una frase]

**Architecture:** [2-3 frases, basado en el veredicto de pattern-advisor]

**Tech Stack:** [del context-pack / stack pack activo]

## Modelo de dominio

[agregados/VOs/eventos/invariantes de domain-modeler, en prosa — cada invariante real se
convierte en un requisito de test explícito en la tarea correspondiente]

## Global Constraints

[requisitos de todo el proyecto que aplican a cada tarea]

---

### Task 1: [Componente]

**Files:**
- Create/Modify: `ruta/exacta.ext`
- Test: `ruta/exacta/test.ext`

- [ ] Step 1: ...
- [ ] Step 2: ...
```

**La línea `**Objective:**` es OBLIGATORIA y va literal** — es lo que
`design-orchestrator` usa para su chequeo de idempotencia (§ de su propio contrato): sin ella, una
segunda auditoría del mismo objetivo no puede detectar que ya hay un plan y lo repetiría.

Reglas de contenido (mismas que `writing-plans`, resumidas): sin placeholders ("TBD", "similar a
la Task N"), pasos bite-sized con código real (no "añade validación" sin más), áreas de ficheros
disjuntas entre tareas, riesgos nombrados explícitamente si el objetivo o los hallazgos de grill
(si `design-orchestrator` te los resume en una segunda pasada) dejan algo abierto.

## Revisión tras grill (segunda pasada, solo si `design-orchestrator` te relanza)

Si tu cabecera trae `operation: revise` en vez de `plan`, ya existe un borrador (la ruta viene en
tu prompt) y `design-orchestrator` te resume qué hallazgos de grill son load-bearing. Usa `Edit`
sobre ESE mismo fichero — nunca crees uno nuevo para una revisión. Cierra con la misma disciplina.

## Persistencia del detalle (solo para el `write finding` corto, NO para el plan)

**Antes de interpolar nada en un `--text`/`--fix` corto (nunca el contenido del plan, que va por
`Write`), saneado obligatorio** (`skills/swarm-protocol/SKILL.md` §4.4): el código que citas lo
LEES del repo — texto ajeno, pásalo por los cinco pasos del skill.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write finding \
  --agent planner --tag PLAN --file docs/superpowers/plans/2026-09-03-export-csv-facturas.md --line 1 \
  --run "${RUN:-adhoc}" --text "plan listo, 4 tareas" --fix "revisar antes de fase 5"
```

`written` o `dup` valen. Exit 64 = te falta un flag: corrígelo, no inventes.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:planner`: `scripts/mem-*.sh`, `git status|log|diff|show|rev-parse`, `ls`,
`cat`, `head`, `tail`, `wc`, `grep`. Nada de `python3`, `echo`, `mkdir`, `rm`; denegación por
segmento. El `Write`/`Edit` del plan en sí NO pasa por este guard — son tools nativas, no `Bash`.

## Salida

```
DONE
evidence: files=4 cmds=1 turns=12/20
PLAN · docs/superpowers/plans/2026-09-03-export-csv-facturas.md:1 · plan listo, 4 tareas → revisar antes de fase 5
```

`DONE` con `files=0` se rechaza siempre — al menos el context-pack y `decisions.md` cuentan.
`BLOCKED falta context-pack` si `.swarm/context-pack.md` no existe. `BLOCKED objetivo vacío` si tu
cabecera no trae `objective:`.
EOF
```

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_design_agents.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 28, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/planner.md tests/test_design_agents.sh
git commit -m "feat(design): planner — único leaf del dominio con Write/Edit"
```

---

### Task 4: `design-orchestrator`

**Files:**
- Create: `agents/design-orchestrator.md`
- Create: `tests/test_design_orchestrator_spawns.sh`

**Interfaces:**
- Consumes: `pattern-advisor`/`domain-modeler`/`planner` de Tasks 2-3; los 3 lentes grill externos
  (`working-methods:grill-architect`, `working-methods:grill-operator`,
  `working-methods:grill-engineer` — ya instalados, formato de salida `OK|KO` + `Pn · where ·
  problema → fix`, SIN `Bash` en sus propios `tools`).
- Produces: `swarm:design-orchestrator` (sonnet, maxTurns 20) que Task 5 lanza desde la raíz; tag
  propio `PLAN` en su salida de síntesis.

- [ ] **Step 1: Escribir el test de spawn (falla primero)**

```bash
cat > tests/test_design_orchestrator_spawns.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_design_orchestrator_spawns.sh — quinta aplicación de la lección de fase 1: un
# orquestador que lanza hojas que NO preexisten necesita Agent(<hojas>) en su frontmatter. Incluye
# los 3 lentes grill EXTERNOS (working-methods:*), que tampoco preexisten cuando design-orchestrator
# arranca.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

F="$PLUGIN_ROOT/agents/design-orchestrator.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/design-orchestrator.md exists"
[ -f "$F" ] || { exit 1; }

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
tools="$(echo "$front" | grep '^tools:')"
agent_clause="$(echo "$tools" | sed -n 's/.*Agent(\([^)]*\)).*/\1/p')"
assert_eq "1" "$([ -z "$agent_clause" ] && echo 0 || echo 1)" "tools: has an Agent(...) clause"
for leaf in planner pattern-advisor domain-modeler; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF "$leaf" && echo 0 || echo 1)" "Agent(...) includes $leaf"
done
for lens in "working-methods:grill-architect" "working-methods:grill-operator" "working-methods:grill-engineer"; do
  assert_eq "0" "$(echo "$agent_clause" | grep -qF "$lens" && echo 0 || echo 1)" "Agent(...) includes external lens $lens"
done
assert_eq "0" "$(echo "$tools" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: includes SendMessage"
assert_eq "1" "$(echo "$tools" | grep -qF 'AskUserQuestion' && echo 0 || echo 1)" "tools: NEVER AskUserQuestion (spec §3.2 rule 7)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Write' && echo 0 || echo 1)" "tools: no Write (delegates to planner)"
assert_eq "1" "$(echo "$tools" | grep -qF 'Edit' && echo 0 || echo 1)" "tools: no Edit"
assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "model sonnet (spec §7)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 20$' && echo 0 || echo 1)" "maxTurns 20 (spec §7)"
assert_eq "1" "$(echo "$front" | grep -q '^background:' && echo 0 || echo 1)" "foreground"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
assert_eq "0" "$(echo "$body" | grep -qF 'no preexisten' && echo 0 || echo 1)" "body documents that leaves+lenses do not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'misma tanda' && echo 0 || echo 1)" "body: pattern-advisor+domain-modeler launched in the same message"
assert_eq "0" "$(echo "$body" | grep -qF 'idempotencia' && echo 0 || echo 1)" "body documents the idempotency check against existing plans"
assert_eq "0" "$(echo "$body" | grep -qF 'arbitra' && echo 0 || echo 1)" "body documents it arbitrates grill findings itself (spec: arbitra actas)"
assert_eq "0" "$(echo "$body" | grep -qF 'sin grill' && echo 0 || echo 1)" "body documents grill only runs in tier full"
assert_eq "0" "$(echo "$body" | grep -qF 'no reenv' && echo 0 || echo 1)" "body explicitly says it does NOT forward grill lines verbatim (unlike analysis-orchestrator)"

out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:design-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh register --run adhoc --agent planner --domain design --area . --owner design-orchestrator"}}
EOF2
)"
assert_eq "" "$out" "design-orchestrator can register a leaf via mem-manifest.sh"
out="$(python3 "$HOOK" <<'EOF2'
{"agent_type": "swarm:design-orchestrator", "tool_name": "Bash", "tool_input": {"command": "python3 x.py"}}
EOF2
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "design-orchestrator cannot run python3"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_design_orchestrator_spawns.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_design_orchestrator_spawns.sh`
Expected: `FAIL` en `agents/design-orchestrator.md exists`, exit 1.

- [ ] **Step 3: Escribir `agents/design-orchestrator.md`**

```bash
cat > agents/design-orchestrator.md <<'EOF'
---
name: design-orchestrator
description: Use when the root orchestrator needs a real implementation plan for a decided product objective — launches pattern-advisor+domain-modeler, then planner to author the plan file, then (tier full only) grill×3 to adversarially review it, and arbitrates the findings itself. Never asks the owner.
model: sonnet
tools: Read, Grep, Bash, Agent(planner,pattern-advisor,domain-modeler,working-methods:grill-architect,working-methods:grill-operator,working-methods:grill-engineer), SendMessage
maxTurns: 20
memory: project
skills: [swarm-protocol]
---

# design-orchestrator

Dominio design del enjambre (spec §7 "Diseño", §15 fase 4). Corres DESPUÉS de discovery, solo en
`tier: full` (spec §9.1: `light` = un solo dominio, nunca encadena; `full` = multi-dominio — la
raíz te lanza tras cerrar decisiones, nunca en `light`). Tu trabajo: (1) `pattern-advisor` +
`domain-modeler` en una tanda para tener veredicto de patrón + modelo de dominio, (2) `planner`
para escribir el plan real, (3) si `tier: full`, los 3 lentes grill externos contra ese plan, (4)
**arbitras tú mismo** los hallazgos de grill (spec: "spec → grill → plan; arbitra actas") — nunca
`AskUserQuestion`, ni tú ni ninguna de tus hojas la tienen. Nunca ejecutas trabajo de hoja (§3.2
regla 4): no diseñas tú mismo, delegas siempre.

## Contexto de arranque (siempre, antes de lanzar a nadie)

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `swarm-root:` es la ruta absoluta de
   `.swarm/`. `operation:` es `design`. `tier:` (protocolo §2) siempre viene `full` cuando te
   lanzan (la raíz nunca te lanza en `light`). `objective:` es el objetivo literal del owner.
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/design-orchestrator.md" 2>/dev/null
   ```
3. Lee con `Read` (cuenta para `files=`): `.swarm/context-pack.md` y `.swarm/decisions.md` (las
   decisiones de discovery para este objetivo — tu `context:` para las hojas). Si el pack no
   existe: `SendMessage(to: "memory-orchestrator", "build")`, espera, `BLOCKED falta context-pack`
   si no llega.

## Chequeo de idempotencia (ANTES de lanzar a nadie)

Un plan ya escrito para este mismo objetivo no se re-escribe. Sanea el objetivo actual con las
mismas reglas de §4.4 y busca en el repo:
```bash
grep -rF "**Objective:** <objetivo saneado>" docs/superpowers/plans/
```
Si encuentras un match, tu veredicto es `DONE · plan ya existe: <ruta del fichero>` sin lanzar a
nadie — evidencia mínima (el `grep` cuenta para `cmds=`, lee al menos un fichero para `files=`).

## Lanzamiento de pattern-advisor + domain-modeler (UNA sola tanda)

**No preexisten**: los LANZAS con el tool `Agent` — nunca `SendMessage` (la lección de fase 1/1b/
2/3, aplicada una quinta vez; tu frontmatter declara
`Agent(planner,pattern-advisor,domain-modeler,working-methods:grill-architect,
working-methods:grill-operator,working-methods:grill-engineer)` y
`tests/test_design_orchestrator_spawns.sh` lo vigila). Van en la **misma tanda** (foreground
ambas, no hay razón para separarlas — a diferencia de discovery no hablan entre sí en el camino
feliz, pero el roster de hermanos sigue siendo snapshot al arrancar, spec §3.1).

Regístralas antes en el manifest:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register --run "${RUN:-adhoc}" --agent pattern-advisor --domain design --area "." --owner design-orchestrator
```
(y lo mismo para `domain-modeler`).

Cabecera de cada spawn:
```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: <advise|model>
objective: <objetivo literal del owner>
```

## Lanzamiento de planner (tras tener los hallazgos de las dos hojas)

Registra `planner` en el manifest igual que las otras dos. Su cabecera:
```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: plan
objective: <objetivo literal del owner>
context: pattern-advisor → findings/pattern-advisor.md; domain-modeler → findings/domain-modeler.md
```
Espera su `DONE` con la ruta del plan (línea `PLAN · <ruta>:1 · …`). Si devuelve `BLOCKED`, propaga
su motivo literal — sin plan no hay nada que grillar ni que cerrar con éxito.

## Grill×3 — SOLO en `tier: full` (que es siempre tu caso, la raíz nunca te lanza en `light`)

Lanza los 3 lentes externos EN PARALELO (misma tanda), pasándoles en su propio prompt la ruta del
plan que acaba de escribir `planner` como "el artefacto objetivo" — no generes el context-pack de
`working-methods:grill` (`.forge/grill-context.md`, requiere Node): los 3 lentes documentan
explícitamente que aceptan "la ruta pasada en tu prompt" como fallback sin ese script. Ejemplo de
prompt para cada lente (ajusta el sujeto según el lente):
```
Lee <ruta absoluta del plan que escribió planner> como el artefacto objetivo. Repo: <ruta absoluta
de la raíz del repo, de tu §2.0>. Ataca el plan como tu lente. Devuelve tu salida TERSE habitual
(OK/KO + hallazgos Pn · file:línea · problema → fix).
```
Los 3 lentes son `["Read","Grep","Glob"]`, sin `Bash` — no necesitan (ni tienen) allowlist nuestro.

## Arbitraje (spec: "arbitra actas" — es tu responsabilidad, no la del owner)

**No reenvíes las líneas de grill verbatim** (a diferencia de `analysis-orchestrator`, que sí
reenvía porque sus hojas ya usan nuestro formato `TAG · fichero:línea · … → …`): el formato de
grill es `Pn · where · problema → fix`, y `where` puede ser un flujo sin `fichero:línea` real
(p. ej. `grill-operator` ataca escenarios de uso, no siempre una línea de código) — eso rompería
`FINDING_RE` si lo copias tal cual a tu propia salida, que sí pasa por el hook.

Para cada hallazgo `P1` (bloqueante) de los 3 lentes: decide con tu propio juicio si es real y si
cambia el plan. Si SÍ: relanza `planner` con `operation: revise`, la ruta del plan, y un resumen
de los `P1` a incorporar (tu propio texto, literal tuyo, no necesita saneado). Si el hallazgo es
genuinamente ambiguo y solo el owner puede resolverlo (nunca inventes una respuesta): tu veredicto
final es `BLOCKED <la pregunta concreta, en ≤20 palabras>` — no relances a `planner` con una
suposición.

Hallazgos `P2`/`P3` (significativos/menores): decide tú si merecen una revisión de `planner` o si
quedan anotados como riesgo conocido dentro del propio plan (más barato, igual de honesto) — tu
criterio, documenta la decisión en tu propia salida (`- grill: N P1 incorporados, M P2/P3 anotados
como riesgo`).

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:design-orchestrator`: `scripts/mem-*.sh`, `git status|log|diff|show|
rev-parse`, `ls`, `cat`, `head`, `tail`, `wc`, `grep`. Nada de `python3`, `echo`, `mkdir`, `rm`,
`git worktree` (no lo necesitas — ninguna hoja usa `isolation: worktree`); denegación por segmento.

## Salida

```
DONE
evidence: files=5 cmds=7 turns=15/20
PLAN · docs/superpowers/plans/2026-09-03-export-csv-facturas.md:1 · plan listo, 4 tareas → revisar antes de fase 5
- grill: 1 P1 incorporado (idempotencia del export), 2 P2 anotados como riesgo
```

Idempotencia (plan ya existía):
```
DONE
evidence: files=1 cmds=1 turns=2/20
PLAN · docs/superpowers/plans/2026-09-02-export-csv-facturas.md:1 · plan ya existe → revisar directamente
```

`BLOCKED <pregunta concreta>` si grill levantó una ambigüedad real irresoluble por juicio propio.
`BLOCKED falta context-pack` / `BLOCKED objetivo vacío` en sus casos respectivos. `KO planner
BLOCKED: <motivo>` si `planner` no pudo escribir el plan. `OK`/`DONE` con `files=0` se rechaza
siempre.
EOF
```

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_design_orchestrator_spawns.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 29, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add agents/design-orchestrator.md tests/test_design_orchestrator_spawns.sh
git commit -m "feat(design): design-orchestrator — planner+grill×3, arbitraje propio"
```

---

### Task 5: Integración en la raíz (`agents/orchestrator.md`)

**Files:**
- Modify: `agents/orchestrator.md` (nueva sección `## 9. Diseño`, sustituir el placeholder de
  §5.4 "el run termina aquí", actualizar §1.0/§4)
- Create: `tests/test_orchestrator_design.sh`

**Interfaces:**
- Consumes: `swarm:design-orchestrator` de Task 4.
- Produces: la raíz con 5 dominios disponibles (memory/requirements/discovery/analysis/design).

- [ ] **Step 1: Escribir el test de integración (falla primero)**

```bash
cat > tests/test_orchestrator_design.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_orchestrator_design.sh — la raíz integra el dominio design (spec §15 fase 4): lo
# encadena tras discovery SOLO en tier full (spec §9.1: light = un solo dominio).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" 'subagent_type: "swarm:design-orchestrator"')" "root launches design-orchestrator by type"
assert_eq "0" "$(has "$body" 'name: "design-orchestrator"')" "root names it exactly design-orchestrator"
assert_eq "0" "$(has "$body" 'operation: design')" "root passes operation: design"
assert_eq "0" "$(has "$body" 'solo en `tier: full`')" "root documents design chains ONLY in tier full"
assert_eq "1" "$(has "$body" 'aún no existe (fase 4)')" "root no longer says design-orchestrator is unimplemented"
assert_eq "0" "$(has "$body" '## 9. Diseño')" "root has a dedicated §9 Diseño section"

# §4 cierre: nuevas líneas de camino terminal para design
assert_eq "0" "$(has "$body" 'diseño completado')" "root's close section documents the design terminal path"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_orchestrator_design.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_orchestrator_design.sh`
Expected: varios `FAIL` — nada de esto existe todavía.

- [ ] **Step 3: Actualizar §1.0 "Alcance actual"**

Busca el texto literal `analysis-orchestrator\` (fase 3, §8 de este fichero)` dentro del párrafo de
"Alcance actual" y reemplaza el párrafo completo (desde `**Alcance actual` hasta el punto que
termina en "inventes su veredicto.") por:

```markdown
**Alcance actual (honesto, no aspiracional):** dominios disponibles: `memory-orchestrator` (§4.2,
fase 1), `requirements-orchestrator` (fase 1b — lo invoca `/swarm:doctor`, tú no lo lanzas en un
run), `discovery-orchestrator` (fase 2, §5), `analysis-orchestrator` (fase 3, §8) y
`design-orchestrator` (fase 4, §9 de este fichero — solo en `tier: full`, encadenado tras
discovery). Los dominios `implementation-orchestrator` y `delivery-orchestrator` son fases 5-6
(spec §15) — TODAVÍA NO EXISTEN. Si el objetivo requiere alguno de ellos, responde honestamente
que el enjambre aún no cubre esa fase y ofrece lo que SÍ puedes hacer (memoria + discovery +
analysis + design). No simules haber orquestado un dominio inexistente ni inventes su veredicto.
```

- [ ] **Step 4: Sustituir el placeholder de §5.4 (final del camino normal de discovery)**

Busca el texto literal (o su equivalente actual — léelo primero, puede haber cambiado ligeramente
con los fixes de fase 3): `Después, como design-orchestrator aún no existe (fase 4), el run
termina aquí: cierra con summary+curate (§4) y devuelve DONE con las decisiones como líneas - …
(§7).` y reemplázalo por:

```markdown
Después, si `tier: full`, encadena §9 (design) usando estas decisiones como contexto — NO cierres
el run todavía. Si `tier: light`, el run termina aquí (spec §9.1: `light` = un solo dominio, nunca
encadena): cierra con `summary`+`curate` (§4) y devuelve `DONE` con las decisiones como líneas
`- …` (§7).
```

- [ ] **Step 5: Añadir `## 9. Diseño` al final del fichero**

```bash
cat >> agents/orchestrator.md <<'EOF'

## 9. Diseño (fase 4 — solo `tier: full`, encadenado tras discovery, spec §7 "Diseño")

### 9.1 Cuándo

**Solo `tier: full`** (spec §9.1: `light` = un solo dominio — discovery/analysis corren solos y
el run termina ahí, nunca encadenan a design). En `full`, tras §5.4 (decisiones recién grabadas) o
tras el camino "ya cerró" de §5.1 (decisiones de un run anterior), lanza `design-orchestrator` con
esas decisiones como contexto — nunca en el mismo turno que discovery (discovery tiene que haber
cerrado sus decisiones primero, secuencial, misma razón que discovery→memory-orchestrator en §5.2).
Si discovery se saltó por completo (bugfix/refactor/docs/infra — §5.1), design TAMBIÉN se salta:
no hay decisiones de producto contra las que diseñar. Dilo en una línea `- diseño omitido: <motivo
compartido con discovery>`.

### 9.2 Lanzamiento

```
Agent(subagent_type: "swarm:design-orchestrator", name: "design-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <ruta absoluta de .swarm>
  operation: design
  tier: full
  objective: <objetivo literal del owner, sin el flag --tier>)
```

Regístralo antes en el manifest:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register --run <run-id> --agent design-orchestrator --domain design --area "." --owner orchestrator
```

### 9.3 Reenviar el resultado (sin `AskUserQuestion` — igual que analysis, distinto motivo)

`design-orchestrator` nunca produce un batch de preguntas: produce una síntesis corta (tag `PLAN`)
apuntando al fichero real del plan. Reenvía su línea `PLAN · …` y su línea `- grill: …` (si la
trae) tal cual a tu propia salida (§7) — igual mecanismo que §8.3 para analysis (sin pasarlas por
el saneado de §5.0, porque no construyes ningún `--text`/`--line` nuevo con ellas).

Si `design-orchestrator` devuelve `BLOCKED …`/`KO …`, propaga su veredicto literal — cierra el run
igual que cualquier otro camino terminal (§4).

### 9.4 Cierre — nueva línea de resumen (extiende §4)

- diseño completado (`DONE`): `- run cerrado: DONE · diseño completado, plan en <ruta>`
- `BLOCKED`/`KO` propagado de design: `- run cerrado: <veredicto literal de design-orchestrator>`
- diseño omitido (discovery también se saltó): `- run cerrado: <tu veredicto> · diseño omitido:
  <motivo>`
EOF
```

- [ ] **Step 6: Añadir las 3 líneas nuevas a la enumeración de §4 "Cierre"**

Localiza el bloque de §4 "Cierre" que enumera "Línea por camino terminal" (ya extendido en fase 3
con las líneas de análisis) y añade, tras las líneas de analysis, estas 3:

```markdown
- diseño completado (§9.4): `- run cerrado: DONE · diseño completado, plan en <ruta>`
- `BLOCKED`/`KO` propagado de design (§9.3): `- run cerrado: <veredicto literal de
  design-orchestrator>`
- diseño omitido (§9.1): `- run cerrado: <tu veredicto> · diseño omitido: <motivo>`
```

- [ ] **Step 7: Confirmar que el test pasa**

Run: `bash tests/test_orchestrator_design.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 8: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 30, failed: 0`.

- [ ] **Step 9: Commit**

```bash
git add agents/orchestrator.md tests/test_orchestrator_design.sh
git commit -m "feat(design): integra design-orchestrator en la raíz (§9, encadenado tras discovery solo en tier full)"
```

---

### Task 6: Checklist de smoke en vivo + cierre de fase

**Files:**
- Create: `docs/superpowers/plans/2026-09-03-phase4-smoke-checklist.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: evidencia real, gate antes de dar la fase por cerrada.

- [ ] **Step 1: Escribir el checklist (plantilla, se rellena en vivo)**

```bash
cat > docs/superpowers/plans/2026-09-03-phase4-smoke-checklist.md <<'EOF'
# Checklist de smoke — Fase 4 design (`design-orchestrator` + planner/pattern-advisor/domain-modeler + grill×3)

Gate. Fixture: `tests/lib.sh::make_fixture` (ya trae `InvoiceController.php`). Este dominio
**tampoco usa `AskUserQuestion`** (igual que analysis) — headless (`claude -p`) debería completar
la cadena entera. **Riesgo real no verificado hasta este smoke**: si `Agent(working-methods:
grill-architect,...)` funciona de verdad desde el `tools:` de un subagente (nunca se ha probado en
esta sesión) — si falla, es el bug más probable de esta fase, arreglar antes de cerrar.

## 1. Run `full` con objetivo de producto → discovery → decisiones → design encadenado

`/swarm:run "añadir export CSV del listado de facturas" --tier=full` sobre el fixture. Tras
responder el batch de discovery (o si `claude -p` no puede — mismo límite ya documentado en fase
2/3, en ese caso repetir en sesión interactiva o simular con decisions.md ya cerrado de un run
anterior): se espera `design-orchestrator` lanzado NOMBRADO con `tier: full` tras las decisiones →
`pattern-advisor`+`domain-modeler` en una tanda → `planner` escribe un fichero REAL en
`docs/superpowers/plans/` con la línea `**Objective:**` → los 3 lentes grill se lanzan y responden
→ `design-orchestrator` arbitra → salida `DONE` con línea `PLAN · <ruta>:1 · …`.
Evidencia:

## 2. Verificar que `Agent(working-methods:grill-architect,...)` funciona desde un subagente

Confirmar en el transcript del ítem 1 que las 3 llamadas a los lentes grill se lanzaron y
respondieron de verdad (no un `BLOCKED`/error de tool no reconocido). Si falla: es un bug de esta
fase, arreglar el mecanismo de invocación (alternativa: si el grant cruzado no funciona desde
`tools:` de un subagente, puede que la raíz tenga que lanzarlos ella misma y pasar sus hallazgos a
design-orchestrator vía mailbox — documentar y arreglar si se da el caso).
Evidencia:

## 3. Excluyente correctamente con `tier: light`

`/swarm:run "audita la seguridad de InvoiceController" --tier=light` (analysis, no discovery) →
`design-orchestrator` NO aparece (analysis no encadena a design, solo discovery lo hace, y solo en
full). `/swarm:run "añadir otra feature" --tier=light` con discovery aplicable → discovery corre
solo, sin encadenar a design, run termina tras las decisiones.
Evidencia:

## 4. Idempotencia — no re-planificar el mismo objetivo

Repetir el run del ítem 1 sobre el mismo objetivo (con `decisions.md` ya cerrado). Se espera que
`design-orchestrator` detecte el plan ya existente vía el grep de `**Objective:**` y devuelva
`DONE · plan ya existe: <ruta>` sin volver a lanzar a `planner`/`pattern-advisor`/`domain-modeler`.
Evidencia:

## 5. Hook de evidencia en vivo

Ninguna salida de `swarm:*` rechazada como narración por `validate-output.py` en los runs de este
checklist — en particular la línea `PLAN · …` que la raíz reenvía en su propia salida (§9.3).
Evidencia:

## Firma

- [ ] Owner: sesión autónoma nocturna — Fecha: ________________
EOF
```

- [ ] **Step 2: Ejecutar el smoke en vivo**

Igual metodología que fases 2/3: `claude -p --plugin-dir <este worktree> --permission-mode
bypassPermissions`. Si algún bug real aparece (el más probable: el grant cruzado de grill), arreglar
inmediatamente y documentar (regla del owner: "Arregla todos los Bugs que encuentres siempre").

- [ ] **Step 3: Review final de rama (Opus)**

Igual patrón que fases 1/1b/2/3: dispatch sobre TODO el diff de la rama antes de mergear. Cualquier
hallazgo Important/Critical se arregla y se re-verifica con review acotada.

- [ ] **Step 4: Commit del checklist relleno**

```bash
git add docs/superpowers/plans/2026-09-03-phase4-smoke-checklist.md
git commit -m "docs: checklist de smoke fase 4 relleno con evidencia real de ejecución en vivo"
```

- [ ] **Step 5: `finishing-a-development-branch` → merge → handoff**

Mismo patrón: verificar tests, mergear local a master (instrucción del owner: "por ahora siempre
merge de local a máster"), limpiar worktree/rama, reescribir el handoff con el estado final de fase
4 y el siguiente paso (fase 5 — implementación + primer stack pack).

## Self-Review (hecho antes de guardar este plan)

**Cobertura del spec:** §7 "Diseño" (4 agentes) → Tasks 2-4. §9.1 (light sin grill/sin
encadenamiento) → decisión autónoma documentada arriba, verificada por tests en Tasks 4-5. §15 fase
4 → Task 5 (integración) + Task 6 (smoke+cierre).

**Riesgo genuino no resuelto por diseño, solo por verificación en vivo:** el grant cruzado
`Agent(working-methods:grill-architect,...)` desde el `tools:` de un subagente nunca se ha probado
en esta sesión — Task 6 Step 1-2 lo verifica explícitamente y da una ruta de fallback documentada
si falla.

**Placeholders:** ninguno — cada Step trae el contenido completo o el diff exacto a aplicar.

**Consistencia de nombres:** `planner`/`pattern-advisor`/`domain-modeler`/`design-orchestrator` y
sus tags (`PLAN`/`PATTERN`/`MODEL`) idénticos en: `bash-allowlist.json` (Task 1), `Agent(...)` de
Task 4, tabla de lanzamiento, §9 de `agents/orchestrator.md` (Task 5). Verificado por búsqueda
cruzada.
