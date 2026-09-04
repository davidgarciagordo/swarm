# Gate de interpretación de objetivo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a conditional pre-classification step to `agents/orchestrator.md` (§1.0bis) that
offers to clarify/optimize an ambiguous `/swarm:run` objective before classifying tier, while
keeping cross-run idempotency ("¿este objetivo ya se cerró?", §5.1) fully deterministic via a
separate `raw:` field.

**Architecture:** No new agent — the root `orchestrator` is the swarm's only holder of a real
`AskUserQuestion`, so the gate lives entirely in its own prompt text as a new sub-section between
§1.0 (guardas de invocación) and §1.1 (tiers). The gate: (a) first checks whether this exact raw
text was already interpreted in a prior run (reuse, no new question); (b) if not, judges its own
confidence in interpreting the objective; (c) on low confidence, asks ONE `AskUserQuestion` (same
one-batch pattern as discovery) offering its interpretation + up to 2 alternatives + free rewrite;
(d) persists the resolution as a `raw:`/`objective:` pair in `.swarm/decisions.md` via
`memory-orchestrator`, BEFORE tier classification runs.

**Tech Stack:** Prompt-text agent files (Markdown, LLM-followed, not executable code — this repo's
"agents" are instructions an LLM reads, not scripts). Bash test suite (`tests/test_*.sh`) that
asserts PROSE PRESENCE in the agent files via `grep`/`has()`, matching every existing test in this
repo for agent `.md` files — there is no runtime simulation of the orchestrator's own LLM judgment,
only assertions that the required instructions, keywords, and structural pieces exist in the file.

**Spec:** `docs/superpowers/specs/2026-09-04-objective-interpretation-gate-design.md`

## Global Constraints

- **Idempotency is sacred (spec, non-negotiable).** The `objective:` field consumed by tier
  classification/discovery/analysis/design/persistence may be the owner-confirmed/optimized text.
  But cross-run "already closed" detection (§5.1's exact match) MUST key off a separate `raw:`
  field — the byte-for-byte sanitized text of `/swarm:run`'s raw argument, written once per run by
  the NEW gate, never by an LLM's non-deterministic interpretation.
- **Happy path stays free.** A clear objective (high confidence) produces ZERO new output lines,
  ZERO new `AskUserQuestion`, and is byte-identical in behavior to before this plan — verified with
  a negative-regression test in Task 1.
- **`tier: direct` is exempt.** The gate never fires for `direct` (that tier never opens a run or
  touches memory — spec, "No objetivos").
- **One batch, never an interrogation.** When the gate fires, it is exactly ONE `AskUserQuestion`
  call — same pattern already established by discovery (§5.3).
- **`agents/orchestrator.md` regression discipline (this session's own established lesson,
  documented 3+ times in this file's history: an enumerated list or cross-reference updated in one
  place and not another).** Every task that edits this file ends with a full-file grep sweep for
  every literal string the task touches (not just the range it edited) before commit.
- **Git identity for every commit:** `git -c user.name="David García Gordo" -c
  user.email="garcia.gordo.david@gmail.com" commit ...` — never touch global git config.
- **Execution pattern for this plan (established today in this same session for the two other
  `agents/orchestrator.md` changes — refactor-routing and push-url= pinning):** TDD (RED against
  the unmodified file, GREEN after the edit) for every task, and after ALL tasks are done, 2-3
  rounds of adversarial Opus review before merge to master — expect at least one review round to
  find something; do not treat "tests pass" as "done."
- **Real mechanism verified against the repo (do not re-derive):** decision lines are written via
  `SendMessage(memory-orchestrator, "write decision --text \"<line-without-date>\"")`, which
  ultimately calls `scripts/mem-files.sh`'s `_write_decision()` (`scripts/mem-files.sh:94-111`) —
  a dumb line-appender that prepends today's UTC date and appends `$text` verbatim to
  `.swarm/decisions.md`. The FIELD NAMES (`raw:`, `objective:`, etc.) are entirely a convention the
  orchestrator's own prose constructs in the `--text` string — `mem-files.sh` has zero awareness of
  field names, so no script changes are needed anywhere in this plan.
- **Real existing pattern verified against the repo (mirror this, don't invent a new shape):**
  `agents/orchestrator.md:625` — the discovery-cancelled decision line is written as:
  ```
  SendMessage(memory-orchestrator, "write decision --text \"objective: <objetivo literal saneado> · discovery <run-id> [pendiente] batch sin responder (owner canceló) · Q1 [<cabecera>] <pregunta saneada> · Q2 [<cabecera>] <pregunta saneada> · …\"")
  ```
  The new gate's write follows the identical `SendMessage(memory-orchestrator, "write decision
  --text \"...\"")` shape, just with a different field set (see Task 2).
- **Real existing idempotency-match prose verified against the repo (Task 3 edits this exact
  passage):** `agents/orchestrator.md:473-486` — today's §5.1 sanitizes THIS run's raw argument
  (§5.0), reads `.swarm/decisions.md` with `Read`, and looks for a decision line whose `objective:`
  field equals it. After this plan, the value fed into that comparison is no longer always the raw
  argument — it is whatever the gate resolved (pass-through raw text on high confidence, or the
  confirmed/alternative/rewritten text on low confidence) — §5.1's OWN matching mechanism is
  unchanged, only the one sentence describing what feeds it needs updating.

---

## File Map

- **Modify:** `agents/orchestrator.md` — new §1.0bis (Tasks 1-2), one-paragraph update to §5.1
  (Task 3), frontmatter `description:` mention if it goes stale (Task 3's regression sweep will
  catch this — do not pre-edit it speculatively).
- **Create:** `tests/test_orchestrator_objective_gate.sh` — mirrors
  `tests/test_orchestrator_design.sh`'s exact conventions (`front`/`body` awk split, `has()`
  helper, `assert_eq`/`lib.sh`).
- **Modify:** `docs/USAGE.md`, `docs/USAGE.es.md` — one new paragraph each under the `/swarm:run`
  section (Task 4).
- **Modify:** `README.md`, `README.es.md` — the existing `/swarm:run` mermaid sequence diagram gets
  one new optional step (Task 4).
- **Modify:** `tests/test_extending_packs_doc.sh` pattern reused as a MODEL, not touched — Task 4
  creates its own small doc-consistency assertions inside Task 4's own test additions to
  `tests/test_orchestrator_objective_gate.sh` (no new test file needed for docs; four assertions
  suffice).

---

## Task 1: §1.0bis skeleton — raw-match reuse + high-confidence pass-through

**Files:**
- Modify: `agents/orchestrator.md` (insert new §1.0bis between the end of §1.0 and the start of
  §1.1 — today's §1.0 ends right before the `### 1.1 Tiers` heading; find that heading with `Grep`
  first, since exact line numbers shift as the file is edited by concurrent work)
- Test: `tests/test_orchestrator_objective_gate.sh` (new file)

**Interfaces:**
- Consumes: nothing from earlier tasks (this is the first task).
- Produces: the §1.0bis heading and its two sub-paths (raw-match reuse, high-confidence
  pass-through) that Task 2 appends its low-confidence branch to, in the SAME section. Produces the
  `raw:`/`objective:` field-naming convention that Task 2 and Task 3 both reference verbatim —
  `raw:` is always the sanitized literal argument of `/swarm:run` (minus `--tier=`), `objective:`
  is always the text that flows into tier classification/discovery/persistence from here on.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_orchestrator_objective_gate.sh`:

```bash
#!/usr/bin/env bash
# tests/test_orchestrator_objective_gate.sh — §1.0bis: gate condicional de interpretación de
# objetivo (docs/superpowers/specs/2026-09-04-objective-interpretation-gate-design.md). Corre
# ANTES de clasificar tier (§1.1) porque una interpretación mejor también mejora esa clasificación.
# Idempotencia (spec, restricción dura): el match de "ya cerró" en §5.1 sigue siendo determinista
# porque compara SIEMPRE contra el campo raw:, nunca contra objective: (que puede variar entre
# interpretaciones no deterministas del mismo texto crudo).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# --- §1.0bis exists, runs before §1.1 ---
assert_eq "0" "$(has "$body" '### 1.0bis')" "root has a §1.0bis section"
bis_pos="$(echo "$body" | grep -n '### 1.0bis' | head -1 | cut -d: -f1)"
tiers_pos="$(echo "$body" | grep -n '### 1.1 Tiers' | head -1 | cut -d: -f1)"
assert_eq "0" "$([ -n "$bis_pos" ] && [ -n "$tiers_pos" ] && [ "$bis_pos" -lt "$tiers_pos" ] && echo 0 || echo 1)" "§1.0bis appears BEFORE §1.1 Tiers in the file"

# --- direct tier is exempt ---
assert_eq "0" "$(has "$body" 'tier: direct')" "§1.0bis or its surrounding prose documents the direct-tier exemption"

# --- raw: / objective: field convention is documented ---
assert_eq "0" "$(has "$body" 'raw:')" "root documents the raw: field"
assert_eq "0" "$(has "$body" 'raw:.*objective:')" "root documents raw: appearing before objective: in a decision line (same order as the spec's example)"

# --- raw-match reuse path (skip re-interpretation for a raw text already resolved before) ---
assert_eq "0" "$(has "$body" 'raw:.*es igual')" "§1.0bis describes matching a NEW run's sanitized raw argument against a stored raw: field"
assert_eq "0" "$(has "$body" '\[pendiente\]')" "the raw-match reuse path explicitly treats a [pendiente] prior line as NOT resolved (mirrors §5.1's existing pendiente handling)"

# --- high-confidence pass-through: zero new output, zero new AskUserQuestion ---
assert_eq "0" "$(has "$body" 'confianza alta')" "§1.0bis documents the high-confidence pass-through path"
assert_eq "0" "$(has "$body" 'sin línea de output nueva')" "§1.0bis explicitly states the high-confidence path emits no new output line (happy path stays free)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/davidgarciagordo/projects/multiagents
bash tests/test_orchestrator_objective_gate.sh
```

Expected: multiple `FAIL:` lines (none of the assertions match anything yet — `§1.0bis` doesn't
exist in the file).

- [ ] **Step 3: Locate the exact insertion point**

```bash
grep -n '^### 1.1 Tiers' agents/orchestrator.md
```

Note the line number. §1.0bis is inserted immediately before that heading (i.e., right after §1.0's
last paragraph ends).

- [ ] **Step 4: Insert §1.0bis (raw-match reuse + high-confidence pass-through only — Task 2 adds
  the low-confidence branch in the SAME section, right after this)**

Insert this text immediately before `### 1.1 Tiers`:

```markdown
### 1.0bis Interpretación del objetivo (spec: docs/superpowers/specs/2026-09-04-objective-interpretation-gate-design.md)

Corre DESPUÉS de §1.0 (objetivo no vacío, `--tier=` válido) y ANTES de §1.1 (clasificación de
tier) — una interpretación mejor también mejora esa clasificación. **Se salta por completo si
`--tier=direct` viene explícito en la invocación**: ese tier nunca abre run ni toca memoria, y el
objetivo es trivial por definición del propio tier — no tiene sentido interponer nada aquí.

**Paso 1 — ¿esta interpretación ya se hizo antes?** Toma el argumento crudo de `/swarm:run` (sin el
flag `--tier=`) y pásalo por el **saneado de §5.0** (el mismo saneado que aplica todo el resto del
fichero antes de comparar o interpolar texto ajeno). Lee `.swarm/decisions.md` con `Read` y busca
una línea de decisión cuyo campo `raw:` sea igual al argumento ya saneado. Si la encuentras Y no
está marcada `[pendiente]`: el objetivo de este run es directamente el `objective:` de esa misma
línea — sáltate los pasos 2 y 3 de abajo, no preguntes nada, sigue a §1.1 con ese texto. Si la
encuentras pero SÍ está `[pendiente]` (el owner canceló esa interpretación en un run anterior — ver
Paso 3 abajo): trátalo como si no la hubieras encontrado, sigue al Paso 2. Si no encuentras ninguna
línea con ese `raw:`: sigue al Paso 2.

**Paso 2 — juzga tu propia confianza.** Con el objetivo saneado (y sin match previo), forma tu
propia interpretación de qué pide el owner y tu nivel de confianza en que esa interpretación es
correcta y suficientemente clara para clasificar tier sin ambigüedad — juicio tuyo como LLM, el
mismo tipo de juicio que ya aplicas en las tablas de keywords "ilustrativas, no exhaustivas" de
§5.1/§8.1/§9.1 más abajo en este fichero, no una métrica calculada.

- **Si tu confianza es alta:** el objetivo de este run es el argumento crudo ya saneado, tal cual —
  sigue a §1.1 sin línea de output nueva, sin `AskUserQuestion`, sin ningún cambio de comportamiento
  respecto a antes de este gate. Este es el caso feliz y debe seguir siendo la mayoría de los runs.
- **Si tu confianza es baja o el objetivo es ambiguo:** sigue al Paso 3 (§1.0bis continúa abajo).
```

- [ ] **Step 5: Run tests, verify the ones about §1.0bis pass**

```bash
bash tests/test_orchestrator_objective_gate.sh
```

Expected: the assertions for "§1.0bis exists", "before §1.1", "direct tier exemption", "raw:
field", "raw-match reuse", "[pendiente] handling", "confianza alta", "sin línea de output nueva"
now PASS. The `raw:.*objective:` assertion (ordering in a decision line) may still FAIL — that's
Task 2's job, don't force it here.

- [ ] **Step 6: Full-file regression sweep (this file's own established discipline)**

```bash
grep -n 'raw:\|objective:\|1\.0bis' agents/orchestrator.md
```

Read every hit. Confirm nothing you just wrote contradicts existing prose elsewhere in the file
(there should be no OTHER mention of `1.0bis` yet, and no stale reference anywhere claiming the
objective always equals the raw argument).

- [ ] **Step 7: Run the FULL test suite**

```bash
for f in tests/test_*.sh; do bash "$f" || echo "FAIL: $f"; done
```

Expected: no new `FAIL:` lines beyond the two `raw:.*objective:` / low-confidence-path assertions
that Task 2 resolves (everything else in the suite, ~56 files, must stay green — this task only
ADDS a section, it does not remove or restructure anything existing).

- [ ] **Step 8: Commit**

```bash
git add agents/orchestrator.md tests/test_orchestrator_objective_gate.sh
git -c user.name="David García Gordo" -c user.email="garcia.gordo.david@gmail.com" commit -m "feat(orchestrator): §1.0bis skeleton — raw-match reuse + high-confidence pass-through

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: §1.0bis low-confidence branch — AskUserQuestion, write decision, BLOCKED-on-cancel

**Files:**
- Modify: `agents/orchestrator.md` (append to the END of §1.0bis, right after Task 1's "Si tu
  confianza es baja... sigue al Paso 3" line)
- Modify: `tests/test_orchestrator_objective_gate.sh` (add assertions)

**Interfaces:**
- Consumes: the `raw:`/`objective:` field convention and the §1.0bis section Task 1 created —
  this task's new prose is Paso 3, appended directly after Task 1's Paso 2.
- Produces: the exact `SendMessage(memory-orchestrator, "write decision --text \"...\"")` call
  shape for the gate's own decision line — Task 3 references this shape when updating §5.1 (it
  does NOT need to repeat the shape, just note that §5.1's match now runs against whatever this
  task wrote).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_orchestrator_objective_gate.sh` (before the final `if [ "$TESTS_FAILED"...`
block):

```bash
# --- low-confidence branch: ONE AskUserQuestion, same one-batch pattern as discovery ---
assert_eq "0" "$(has "$body" 'AskUserQuestion')" "§1.0bis low-confidence path uses a real AskUserQuestion"
assert_eq "0" "$(has "$front" 'AskUserQuestion')" "root's own tools: frontmatter already includes AskUserQuestion (pre-existing, verify not accidentally removed)"
assert_eq "0" "$(has "$body" 'hasta 2 alternativas')" "the question offers up to 2 alternatives, matching the spec"
assert_eq "0" "$(has "$body" 'quiero re-escribirlo yo')" "the question offers a free-rewrite option via Other"

# --- outcomes: confirm / alternative / rewrite all become objective: ---
assert_eq "0" "$(has "$body" 'ESE texto final es el')" "whichever outcome the owner picks becomes the objective: used from here on"

# --- decision line written BEFORE tier classification, with raw: + objective: fields ---
assert_eq "0" "$(has "$body" 'write decision --text')" "§1.0bis writes a decision line via the same write decision --text mechanism as discovery"
assert_eq "0" "$(has "$body" '\\\"raw: ')" "the write decision call's --text starts with raw: (mirrors discovery's objective:-first convention, adapted for this gate)"

# --- owner cancels: BLOCKED, [pendiente], mirrors discovery §5.3's cancel handling exactly ---
assert_eq "0" "$(has "$body" 'BLOCKED interpretación de objetivo sin confirmar')" "cancelling the gate's question produces this exact BLOCKED verdict"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash tests/test_orchestrator_objective_gate.sh
```

Expected: all the new assertions above FAIL (Paso 3 doesn't exist in the file yet), plus the
`raw:.*objective:` assertion from Task 1 still fails.

- [ ] **Step 3: Append Paso 3 to §1.0bis**

Immediately after Task 1's last line (`- **Si tu confianza es baja o el objetivo es ambiguo:**
sigue al Paso 3 (§1.0bis continúa abajo).`), append:

```markdown
**Paso 3 — pregunta, UNA sola tanda (mismo patrón que discovery, §5.3).** Construye una
`AskUserQuestion` con:

- tu interpretación optimizada del objetivo, como la opción recomendada
- hasta 2 alternativas si genuinamente las hay (nunca inventes alternativas artificiales solo para
  rellenar — si solo ves una lectura razonable, una sola opción más el rewrite libre basta)
- la opción "Other" de `AskUserQuestion` sirve como "quiero re-escribirlo yo" — texto libre del
  owner, sin ninguna sugerencia tuya de por medio

```
AskUserQuestion(questions: [{
  question: "Tu objetivo: '<argumento crudo del owner>'. Lo interpreto como: '<tu interpretación>'. ¿Confirmas o prefieres otra?",
  header: "Objetivo",
  multiSelect: false,
  options: [
    { label: "<tu interpretación> (recomendada)", description: "<en qué te basas>" },
    { label: "<alternativa 1, si la hay>", description: "<en qué te basas>" }
  ]
}])
```

**Resuelve el resultado:**

- El owner confirma tu interpretación, o elige una alternativa, o escribe la suya en "Other": ESE
  texto final es el `objective:` que usa el resto de este run — clasificación de tier (§1.1),
  discovery, analysis, design, y lo que se persiste en `.swarm/decisions.md` de aquí en adelante.
  Antes de seguir a §1.1, persiste la resolución (pasa AMBOS textos por el saneado de §5.0 antes de
  interpolarlos):
  ```
  SendMessage(memory-orchestrator, "write decision --text \"raw: <argumento crudo saneado> · objective: <texto final saneado> · interpretación resuelta\"")
  ```
  Espera su `OK`/`written` antes de continuar a §1.1.

- El owner cancela el diálogo (lo cierra sin elegir — mismo comportamiento normal que discovery
  §5.3, no un error): registra la interpretación como PENDIENTE (una sola escritura, mismo saneado
  de §5.0):
  ```
  SendMessage(memory-orchestrator, "write decision --text \"raw: <argumento crudo saneado> · objective: <tu interpretación saneada> [pendiente] interpretación sin confirmar\"")
  ```
  Espera su `OK`/`written`, cierra el run igual que cualquier otro camino terminal (§4: `summary`
  con esta línea, `SendMessage(memory-orchestrator, "curate")`, espera su `DONE`) y tu veredicto es:
  ```
  BLOCKED interpretación de objetivo sin confirmar
  ```
```

- [ ] **Step 4: Run tests, verify they pass**

```bash
bash tests/test_orchestrator_objective_gate.sh
```

Expected: every assertion in the file now passes, including the `raw:.*objective:` ordering
assertion from Task 1 (both the confirm-path and pendiente-path `--text` strings start with `raw:`
then `objective:`).

- [ ] **Step 5: Full-file regression sweep**

```bash
grep -n 'BLOCKED interpretación\|write decision --text\|Paso 3\|AskUserQuestion' agents/orchestrator.md
```

Read every hit. Confirm the new `BLOCKED interpretación de objetivo sin confirmar` string appears
EXACTLY where Task 2 wrote it and nowhere else contradicts it (no other §4 close-path table missing
this new terminal state — check §4's list of close-path lines and add this one if that section
enumerates terminal verdicts explicitly; if §4 is generic prose that doesn't enumerate every
possible `BLOCKED <motivo>` literally, no edit is needed there — verify which is true by reading §4
before deciding).

- [ ] **Step 6: Run the FULL test suite**

```bash
for f in tests/test_*.sh; do bash "$f" || echo "FAIL: $f"; done
```

Expected: 100% green, no new failures anywhere in the suite.

- [ ] **Step 7: Commit**

```bash
git add agents/orchestrator.md tests/test_orchestrator_objective_gate.sh
git -c user.name="David García Gordo" -c user.email="garcia.gordo.david@gmail.com" commit -m "feat(orchestrator): §1.0bis low-confidence branch — AskUserQuestion, decision write, BLOCKED-on-cancel

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: Update §5.1's idempotency-match prose to reflect the post-gate objective

**Files:**
- Modify: `agents/orchestrator.md:473-486` (exact passage identified and quoted in Global
  Constraints above — re-locate with `Grep` first, since Tasks 1-2 shifted line numbers)
- Modify: `tests/test_orchestrator_objective_gate.sh` (add assertions)

**Interfaces:**
- Consumes: nothing new — this task only clarifies existing prose to be consistent with Tasks 1-2's
  new gate, it does not change §5.1's actual matching MECHANISM (still an exact `Read` + compare
  against a stored field).
- Produces: nothing new for later tasks — this is the last `agents/orchestrator.md` content task
  before Task 4's doc updates.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_orchestrator_objective_gate.sh` (before the final `if` block):

```bash
# --- §5.1's own idempotency-match prose now clarifies it runs on the POST-GATE objective ---
assert_eq "0" "$(has "$body" 'ya resuelto por')" "§5.1 clarifies the objective it matches may already be resolved by §1.0bis, not always the raw argument"

# --- full-file regression: no stale claim anywhere that objective always equals the raw /swarm:run argument ---
stale="$(echo "$body" | grep -n 'argumento crudo de.*swarm:run.*objetivo\|objetivo.*siempre.*argumento crudo' || true)"
assert_eq "0" "$([ -z "$stale" ] && echo 0 || echo 1)" "no stale claim anywhere states the objective always equals the raw /swarm:run argument (§1.0bis can now change it)"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash tests/test_orchestrator_objective_gate.sh
```

Expected: the `ya resuelto por` assertion FAILS (§5.1 hasn't been touched yet). The stale-claim
assertion should already PASS (nothing in the current file makes that literal claim) — if it
unexpectedly fails, read what it matched before proceeding; it means Task 1/2's own new prose
accidentally introduced a stale-sounding claim that needs rewording, fix that first.

- [ ] **Step 3: Locate and update §5.1**

```bash
grep -n 'Cómo compruebas ese "ya cerró"' agents/orchestrator.md
```

Find the paragraph starting `**Cómo compruebas ese "ya cerró"** (importa el CÓMO): primero pasa el
objetivo de ESTE run...`. Insert ONE new sentence at the START of that paragraph, before "primero
pasa el objetivo de ESTE run":

```markdown
**Cómo compruebas ese "ya cerró" (importa el CÓMO):** el "objetivo de este run" de aquí en adelante
puede venir ya resuelto por §1.0bis (interpretado y confirmado por el owner, o adoptado por un match
de `raw:` con un run anterior) en vez de ser siempre el argumento crudo de `/swarm:run` — el
mecanismo de comparación que sigue no cambia, solo su fuente. primero pasa el objetivo de ESTE run
—ya resuelto por §1.0bis, o el argumento de `/swarm:run` sin el flag `--tier` si §1.0bis no se
disparó— por el **saneado de §5.0**, el mismo que aplicó §5.4 al guardarlo. [...]
```

(Keep the rest of the existing paragraph UNCHANGED — this step only prepends the clarifying
sentence and adjusts the immediately-following clause to say "ya resuelto por §1.0bis, o el
argumento... si §1.0bis no se disparó" instead of unconditionally "el argumento de `/swarm:run`".)

- [ ] **Step 4: Run tests, verify they pass**

```bash
bash tests/test_orchestrator_objective_gate.sh
```

- [ ] **Step 5: Full-file regression sweep (mandatory — this is exactly the file/pattern that has
  regressed 3+ times this project)**

```bash
grep -n 'objetivo de ESTE run\|objetivo de este run\|argumento crudo' agents/orchestrator.md
```

Read every hit across the WHOLE file (§5.1, §8.1, §9.1, and any other section that references "el
objetivo de este run"). If §8.1 or §9.1 also independently claim the objective is always the raw
`/swarm:run` argument (rather than deferring to §1.0bis/§5.1's already-clarified language), add the
same one-sentence clarification there too — do not leave a second site stale. If they already just
say "el objetivo" without asserting where it comes from, no edit needed there.

- [ ] **Step 6: Run the FULL test suite**

```bash
for f in tests/test_*.sh; do bash "$f" || echo "FAIL: $f"; done
```

Expected: 100% green.

- [ ] **Step 7: Commit**

```bash
git add agents/orchestrator.md tests/test_orchestrator_objective_gate.sh
git -c user.name="David García Gordo" -c user.email="garcia.gordo.david@gmail.com" commit -m "fix(orchestrator): §5.1 idempotency match now documents it runs on the post-gate objective

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4: Bilingual docs — USAGE.md/.es.md paragraph, README mermaid diagram step

**Files:**
- Modify: `docs/USAGE.md`, `docs/USAGE.es.md`
- Modify: `README.md`, `README.es.md`
- Modify: `tests/test_orchestrator_objective_gate.sh` (add doc-consistency assertions, mirroring
  `tests/test_extending_packs_doc.sh`'s pattern of checking both language files for the same
  concrete claims)

**Interfaces:**
- Consumes: nothing code-level from earlier tasks — this task documents the FEATURE Tasks 1-3
  built, in prose, for humans reading the docs (not agent-consumed text).
- Produces: nothing for later tasks (this is the last task of this plan).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_orchestrator_objective_gate.sh` (before the final `if` block):

```bash
# --- bilingual docs mention the gate ---
usage_en="$(cat "$PLUGIN_ROOT/docs/USAGE.md" 2>/dev/null)"
usage_es="$(cat "$PLUGIN_ROOT/docs/USAGE.es.md" 2>/dev/null)"
assert_eq "0" "$(has "$usage_en" 'objective interpretation')" "USAGE.md mentions the objective interpretation gate"
assert_eq "0" "$(has "$usage_es" 'interpretación del objetivo')" "USAGE.es.md mentions the objective interpretation gate"

readme_en="$(cat "$PLUGIN_ROOT/README.md" 2>/dev/null)"
readme_es="$(cat "$PLUGIN_ROOT/README.es.md" 2>/dev/null)"
assert_eq "0" "$(has "$readme_en" 'ambiguous')" "README.md's /swarm:run diagram/prose mentions the ambiguous-objective case"
assert_eq "0" "$(has "$readme_es" 'ambig')" "README.es.md's /swarm:run diagram/prose mentions the ambiguous-objective case (ambiguo/ambigüedad)"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash tests/test_orchestrator_objective_gate.sh
```

Expected: the four new assertions FAIL.

- [ ] **Step 3: Add the USAGE.md paragraph**

```bash
grep -n '^### `/swarm:run`' docs/USAGE.md
```

Immediately after that section's existing intro paragraph (before its first code block or
sub-bullet — read the surrounding 15 lines with `Read` to place it naturally), add:

```markdown
Before tier classification, the root judges its own confidence in the objective it was given. A
clear objective sees zero change — no new question, no new output line. An ambiguous or vaguely
worded one triggers a single `AskUserQuestion` offering the root's interpretation (plus up to 2
alternatives, plus a free-rewrite option) — the owner's confirmed answer becomes the objective used
for classification, discovery, and everything downstream. Cross-run "already asked this" detection
stays exact and deterministic regardless: it matches against the untouched raw argument, recorded
separately, never against a non-deterministic LLM interpretation.
```

- [ ] **Step 4: Add the USAGE.es.md paragraph (same location, translated, not just similar)**

```bash
grep -n '^### Flujo de `/swarm:run`' docs/USAGE.es.md
```

Add at the equivalent location:

```markdown
Antes de clasificar tier, la raíz juzga su propia confianza en el objetivo recibido. Un objetivo
claro no ve ningún cambio — ni pregunta nueva ni línea de output nueva. Uno ambiguo o mal redactado
dispara una única `AskUserQuestion` con la interpretación de la raíz (más hasta 2 alternativas, más
una opción de reescritura libre) — la respuesta confirmada del owner pasa a ser el objetivo que usan
la clasificación, discovery, y todo lo posterior. La detección de "esto ya se preguntó" entre runs
sigue siendo exacta y determinista de todos modos: compara contra el argumento crudo sin tocar,
guardado aparte, nunca contra una interpretación no determinista del LLM.
```

- [ ] **Step 5: Add the README.md mermaid diagram step**

```bash
grep -n 'sequenceDiagram' README.md | head -3
```

Find the `/swarm:run` flow diagram (the one with `participant DO as discovery-orchestrator`). Add
one new optional step right after `O->>O: classify tier (direct / light / full)` — actually BEFORE
it, since the gate now runs first:

```mermaid
    O->>O: classify tier (direct / light / full)
    alt tier = direct
        O-->>User: OK (no run opened)
    else tier = light or full
        alt objective ambiguous (root's own judgment)
            O->>User: AskUserQuestion (ONE call: interpretation + alternatives + free rewrite)
            User-->>O: confirmed/alternative/rewritten objective
            Note over O: raw: + objective: recorded separately<br/>(idempotency matches raw:, never the interpretation)
        end
        O->>O: open run (run-id, .swarm/run/<id>/)
```

Insert the new `alt objective ambiguous...end` block right after `else tier = light or full` and
before `O->>O: open run (run-id, .swarm/run/<id>/)` — read the existing diagram first with `Read`
to match its exact current indentation and participant names before editing (they may have shifted
since this plan was written).

- [ ] **Step 6: Add the README.es.md mermaid diagram step (mirrored, same location)**

```bash
grep -n 'sequenceDiagram' README.es.md | head -3
```

Same insertion, Spanish participant labels matching the existing diagram's convention:

```mermaid
    O->>O: clasifica tier (direct / light / full)
    alt tier = direct
        O-->>User: OK (sin abrir run)
    else tier = light o full
        alt objetivo ambiguo (juicio propio de la raíz)
            O->>User: AskUserQuestion (UNA llamada: interpretación + alternativas + reescritura libre)
            User-->>O: objetivo confirmado/alternativo/reescrito
            Note over O: raw: + objective: se registran aparte<br/>(la idempotencia compara contra raw:, nunca contra la interpretación)
        end
        O->>O: abre run (run-id, .swarm/run/<id>/)
```

- [ ] **Step 7: Run tests, verify they pass**

```bash
bash tests/test_orchestrator_objective_gate.sh
```

- [ ] **Step 8: Run the FULL test suite**

```bash
for f in tests/test_*.sh; do bash "$f" || echo "FAIL: $f"; done
```

Expected: 100% green (should now be ~57 files: the 56 baseline + this plan's new
`test_orchestrator_objective_gate.sh`).

- [ ] **Step 9: Commit**

```bash
git add docs/USAGE.md docs/USAGE.es.md README.md README.es.md tests/test_orchestrator_objective_gate.sh
git -c user.name="David García Gordo" -c user.email="garcia.gordo.david@gmail.com" commit -m "docs: objective interpretation gate — USAGE.md/.es.md paragraph, README mermaid step (EN+ES)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Post-plan: expected review pattern (not a task — context for the executor)

After all 4 tasks are committed, this plan's own Global Constraints require the SAME pattern
already used twice today in this session for `agents/orchestrator.md` changes:

1. Dispatch an Opus review of the full diff against master (all 4 commits together, one review —
   these tasks are tightly coupled, not independently mergeable).
2. Expect at least one round of findings — both prior `agents/orchestrator.md` changes today
   (refactor-routing, push-url= pinning) needed 2-3 rounds before a clean approval. Do not be
   surprised or treat a first-round "concerns" verdict as a plan defect.
3. Common risk areas a reviewer will likely probe, worth self-checking before dispatch: (a) does
   the raw-match reuse path (Task 1, Paso 1) genuinely never re-ask the `AskUserQuestion` for a
   repeated raw text, even across DIFFERENT runs, not just within one run; (b) does the
   `[pendiente]` handling in Paso 1 correctly avoid an infinite "keep re-asking" loop if the owner
   cancels the SAME raw text twice in a row (it should — each cancel writes a NEW `[pendiente]`
   line and the next run's Paso 1 just doesn't find a non-pendiente match, falls through to Paso 2
   again, which is correct, not a loop bug); (c) whether §1.0bis interacts safely with an explicit
   `--tier=light` or `--tier=full` flag (the gate still fires — only `--tier=direct` exempts it,
   per Global Constraints; a reviewer may ask whether `--tier=light`/`full` should ALSO skip it,
   which is a legitimate question to surface back to the owner if raised, not something to decide
   unilaterally mid-review).
4. Merge to `master` locally, run the full suite once more on the merged result, push — same
   pattern as every other merge in this session.
