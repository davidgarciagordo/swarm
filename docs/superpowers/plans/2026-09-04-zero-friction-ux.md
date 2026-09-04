# Cero fricción técnica — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recalibrate swarm's UX surface for a non-technical owner — single `/swarm` entry point
with transparent auto-init, deterministic vocabulary translation, and business-impact-framed
decision gates — without touching the internal engine (agent roster, guard, evidence contract,
tier logic).

**Architecture:** Three disjoint-file tasks (no two touch the same file), safe to implement in
parallel: (1) `agents/orchestrator.md` — auto-init + vocabulary table + its own BLOCKED-path style;
(2) `agents/discovery-orchestrator.md` + `agents/release-manager.md` — business-impact question
style; (3) bilingual docs. Same TDD + prose-presence-test pattern as every other change to this
repo today; `agents/orchestrator.md` is this project's most regression-prone file, full-file grep
sweep required after Task 1.

**Tech Stack:** Prompt-text agent files (Markdown, LLM-followed, not executable code). Bash test
suite asserting prose presence via `grep`/`has()`.

**Spec:** `docs/superpowers/specs/2026-09-04-zero-friction-ux-design.md`

## Global Constraints

- **No new model roundtrip.** Vocabulary translation is a static substitution table + prose
  written at the source by agents that already construct that text — never a dedicated "translate
  after the fact" pass.
- **Internal engine untouched.** No change to agent roster, `hooks/bash-guard.py`,
  `hooks/validate-output.py`'s evidence-contract parsing, tier-classification logic, or any
  domain's actual routing/gating mechanism — this plan only changes what text is shown and which
  command the owner types.
- **`--tier=` stays functional, only hidden from simple docs.** Do not remove or deprecate the
  flag — power-user/CI workflows (used extensively this session) depend on it.
- **`commands/init.md`/`doctor.md` are NOT deleted** — they stay as independent commands, only
  stop being a documented required step for normal use.
- **Findings files (`findings/*.md`) stay technical** — only owner-FACING text (final turn output,
  `AskUserQuestion` prompts) gets the plain-language treatment.
- **Real mechanism verified against the repo (do not re-derive):** `scripts/mem-files.sh:45-55`'s
  `cmd_health()` — both "`.swarm/` doesn't exist" and "`.swarm/` exists but not writable" return
  the SAME exit code (`1`); they differ only in the stderr TEXT ("SWARM_ROOT not found" vs
  "SWARM_ROOT not writable"). Task 1 must distinguish these by grepping the Bash tool's stderr
  output text, not by exit code alone — auto-init only for the "not found" case, still `BLOCKED`
  for "not writable" (a filesystem-permissions problem auto-init cannot fix).
- **`git -c user.name="David García Gordo" -c user.email="garcia.gordo.david@gmail.com" commit`**
  for every commit — never touch global git config.
- **`.swarm/decisions.md`** — unrelated real dogfood data with uncommitted changes in this repo —
  never touch it, never `git add` it.
- **Execution pattern (established today, this same session, for every `agents/orchestrator.md`
  change):** TDD per task (RED against the unmodified file, GREEN after), full-file regression
  grep sweep for any task touching `agents/orchestrator.md`, and 2-3 rounds of Opus adversarial
  review before merge — do not treat "tests pass" as "done."

---

## File Map

- **Modify:** `agents/orchestrator.md` — §2.1 (auto-init), a new vocabulary-substitution
  instruction near §4 (Cierre), style instruction on §1.0/§1.0bis's own BLOCKED-path prose.
- **Modify:** `agents/discovery-orchestrator.md` — style instruction for its question-construction
  step (before it hands questions back to the root).
- **Modify:** `agents/release-manager.md` — style instruction for its gate/error messages.
- **Modify:** `commands/run.md` — description/argument-hint updated to present `/swarm` as the
  simple name; no `--tier=` in the primary description.
- **Modify:** `docs/USAGE.md`, `docs/USAGE.es.md` — quickstart rewritten around the single command;
  `--tier=` moved to a clearly-marked "Advanced" section.
- **Modify:** `README.md`, `README.es.md` — quickstart example updated to `/swarm "<goal>"`.
- **Create:** `tests/test_zero_friction_ux.sh` — new test file covering all 3 tasks' assertions
  (single file, since the tasks are small and thematically one feature — mirrors this repo's own
  precedent of one test file per feature area).

---

## Task 1: `agents/orchestrator.md` — auto-init + vocabulary table + BLOCKED-path style

**Files:**
- Modify: `agents/orchestrator.md` §2.1 (Health-gate, currently ~lines 202-213 — re-locate with
  `Grep` first, line numbers shift), plus a new subsection near §4 (Cierre) for the vocabulary
  table, plus §1.0/§1.0bis's existing `BLOCKED` lines (get a one-line style-instruction addendum,
  not rewritten wholesale).
- Test: `tests/test_zero_friction_ux.sh` (new file, this task's section)

**Interfaces:**
- Consumes: nothing from other tasks (fully self-contained).
- Produces: nothing other tasks depend on (Task 2/3 are independent).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_zero_friction_ux.sh`:

```bash
#!/usr/bin/env bash
# tests/test_zero_friction_ux.sh — zero-friction UX recalibration
# (docs/superpowers/specs/2026-09-04-zero-friction-ux-design.md): single /swarm entry point with
# transparent auto-init, deterministic vocabulary translation, business-impact-framed gates. Prose
# tests only — this repo's agents are LLM-followed Markdown, not executable code.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# ===== Task 1: agents/orchestrator.md =====
F="$PLUGIN_ROOT/agents/orchestrator.md"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"

# --- auto-init replaces the hard BLOCKED for the "not found" case ---
assert_eq "0" "$(has "$body" 'SWARM_ROOT not found')" "§2.1 distinguishes the not-found stderr text (auto-init path)"
assert_eq "0" "$(has "$body" 'SWARM_ROOT not writable')" "§2.1 distinguishes the not-writable stderr text (still-block path)"
assert_eq "0" "$(has "$body" 'BLOCKED falta /swarm:init')" "the not-writable case still has a real BLOCKED path (must not vanish entirely)"
not_found_pos="$(echo "$body" | grep -n 'SWARM_ROOT not found' | head -1 | cut -d: -f1)"
autoinit_pos="$(echo "$body" | grep -n 'swarm-init\|scripts/swarm-init' | head -1 | cut -d: -f1)"
assert_eq "0" "$([ -n "$not_found_pos" ] && [ -n "$autoinit_pos" ] && echo 0 || echo 1)" "auto-init actually invokes the real init script (scripts/swarm-init.sh), not a reimplementation"

# --- vocabulary substitution table exists with all 4 verdict words ---
for word in "DONE" "BLOCKED" "KO" "OK"; do
  assert_eq "0" "$(has "$body" "$word")" "vocabulary table covers $word"
done
assert_eq "0" "$(has "$body" 'lenguaje llano')" "orchestrator has a plain-language instruction for its own output"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd /Users/davidgarciagordo/projects/multiagents
bash tests/test_zero_friction_ux.sh
```

Expected: multiple `FAIL:` lines.

- [ ] **Step 3: Locate §2.1 and rewrite the health-gate branch**

```bash
grep -n '### 2.1 Health-gate' agents/orchestrator.md
```

Replace the "Exit 1" paragraph (currently: *"Exit 1 (`.swarm/` no existe o no es escribible) → tu
veredicto es `BLOCKED falta /swarm:init`..."*) with two distinct branches based on the Bash tool's
stderr text from `mem-files.sh health`:

```markdown
Exit 1 con `SWARM_ROOT not found` en stderr (`.swarm/` no existe todavía): NO es un `BLOCKED` —
inicialízalo tú misma, transparente para el owner, invocando el mismo script real que
`/swarm:init` usa (`Bash`, mira `commands/init.md`/`scripts/swarm-init.sh` para el comando exacto —
nunca reimplementes esa lógica a mano). Tras inicializar con éxito, repite el `health` check una
vez (debe salir `ok` ahora) y continúa normalmente con la apertura del run — el owner nunca ve
nada de esto, es exactamente como si `.swarm/` ya hubiera existido.

Exit 1 con `SWARM_ROOT not writable` en stderr (`.swarm/` existe pero el filesystem lo rechaza —
permisos, disco de solo lectura): esto SÍ es un `BLOCKED` real, auto-inicializar no lo arregla. Tu
veredicto es `BLOCKED falta /swarm:init` (mismo texto que antes — el owner necesita arreglar
permisos, no volver a correr `/swarm:init`, así que el mensaje sigue siendo preciso). No abras el
run: `mem-manifest.sh open` haría `mkdir -p` y dejaría un `.swarm/` a medias.
```

Verify `commands/init.md`/`scripts/swarm-init.sh` first (`Read` them) to get the EXACT command
this new auto-init branch should invoke — do not guess the script's arguments.

- [ ] **Step 4: Add the vocabulary substitution table near §4 (Cierre)**

```bash
grep -n '^## 4. Cierre' agents/orchestrator.md
```

Add a new subsection right after §4's opening paragraph (before its existing content, as a
prefacing instruction that applies to every line §4 already emits):

```markdown
### 4.0bis Traducción de vocabulario (owner sin conocimientos técnicos)

Antes de emitir tu línea final de veredicto al owner (no a otro agente, no a un `--line` interno —
solo lo que el owner lee), sustituye el prefijo técnico por su equivalente en lenguaje llano. El
resto de la línea (el `<motivo>`/detalle) ya debe venir en lenguaje llano por construcción (ver la
instrucción de estilo de más abajo) — esta sustitución solo cambia la PALABRA del prefijo, nunca el
contenido:

| prefijo técnico | equivalente owner |
|---|---|
| `DONE` | "Listo:" |
| `BLOCKED <motivo>` | "No he podido continuar: <motivo>" |
| `KO <motivo>` | "Algo no salió bien: <motivo>" |
| `OK` | "Todo en orden." |

Esta tabla aplica SOLO a lo que el owner lee — los `--line` internos que pasan a `mem-manifest.sh
summary` (protocolo, evidencia, ficheros de hallazgos) siguen usando el vocabulario técnico tal
cual, sin tocar: esos son para el propio enjambre, no para el owner.
```

- [ ] **Step 5: Add the plain-language style instruction to §1.0/§1.0bis's own BLOCKED prose**

```bash
grep -n 'BLOCKED objetivo vacío\|BLOCKED interpretación de objetivo' agents/orchestrator.md
```

Add one sentence near each (or a single shared note right before §1.0 if that reads more
naturally — your call, keep it minimal): "el `<motivo>` que acompaña este `BLOCKED` va siempre en
lenguaje llano — impacto de negocio, nunca jerga interna del proyecto (nunca 'tier', 'run',
'idempotencia', nombres de fichero/función salvo que el propio owner los haya mencionado)."

- [ ] **Step 6: Run tests, verify they pass**

```bash
bash tests/test_zero_friction_ux.sh
```

- [ ] **Step 7: Full-file regression sweep**

```bash
grep -n 'BLOCKED falta /swarm:init\|SWARM_ROOT not\|swarm-init' agents/orchestrator.md
```

Confirm no other site in the file still assumes the health-gate is a single unconditional
`BLOCKED` (check any prose elsewhere that references "§2.1" or describes this gate's behavior —
e.g. the ledger/handoff-style cross-references some domain-close sections make to §2.1).

- [ ] **Step 8: Run the FULL test suite**

```bash
for f in tests/test_*.sh; do bash "$f" || echo "FAIL: $f"; done
```

Expected: no new failures (~55 files baseline plus this new one).

- [ ] **Step 9: Commit**

```bash
git add agents/orchestrator.md tests/test_zero_friction_ux.sh
git -c user.name="David García Gordo" -c user.email="garcia.gordo.david@gmail.com" commit -m "feat(orchestrator): transparent auto-init + plain-language vocabulary for the owner

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: Business-impact question style — `discovery-orchestrator.md` + `release-manager.md`

**Files:**
- Modify: `agents/discovery-orchestrator.md` (its question-construction step, before handing the
  batch back to the root)
- Modify: `agents/release-manager.md` (its gate/error/discrepancy messages)
- Test: `tests/test_zero_friction_ux.sh` (append)

**Interfaces:**
- Consumes: nothing from Task 1 (fully independent, different files).
- Produces: nothing Task 3 depends on.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_zero_friction_ux.sh` (before the final `if` block):

```bash
# ===== Task 2: discovery-orchestrator.md + release-manager.md =====
DF="$PLUGIN_ROOT/agents/discovery-orchestrator.md"
dbody="$(awk '/^---$/{n++; next} n>=2{print}' "$DF")"
assert_eq "0" "$(has "$dbody" 'lenguaje llano')" "discovery-orchestrator has the plain-language question style instruction"
assert_eq "0" "$(has "$dbody" 'recomendada')" "discovery-orchestrator's questions mark the recommended option explicitly"

RF="$PLUGIN_ROOT/agents/release-manager.md"
rbody="$(awk '/^---$/{n++; next} n>=2{print}' "$RF")"
assert_eq "0" "$(has "$rbody" 'lenguaje llano')" "release-manager has the plain-language message style instruction"
```

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd /Users/davidgarciagordo/projects/multiagents
bash tests/test_zero_friction_ux.sh
```

- [ ] **Step 3: Add the style instruction to `discovery-orchestrator.md`**

Read the file's existing section where it constructs its questions (before returning the batch to
the root — search for where it builds the `- Q` lines / the options it hands upward). Add a short
instruction: questions and their options must be phrased in plain language — business impact, not
technical vocabulary (e.g. "¿quieres que sea al instante, o puede tardar unos minutos si hay mucho
volumen?" instead of "¿síncrono o cola asíncrona?") — and the recommended option must be visibly
marked as such in its label/description (not just implied).

- [ ] **Step 4: Add the style instruction to `release-manager.md`**

Read the file's gate/approval/error-message sections (the push preview, the discrepancy messages
from today's `url=`/SSH work). Add the same style instruction: messages the owner reads must be
plain-language, business-impact framed — the exact command/technical detail can still be SHOWN
(the owner may need to copy it, or a technical reader may follow up) but the EXPLANATION around it
must not assume the owner understands git/push/remote vocabulary unassisted.

- [ ] **Step 5: Run tests, verify they pass; full suite**

```bash
bash tests/test_zero_friction_ux.sh
for f in tests/test_*.sh; do bash "$f" || echo "FAIL: $f"; done
```

- [ ] **Step 6: Commit**

```bash
git add agents/discovery-orchestrator.md agents/release-manager.md tests/test_zero_friction_ux.sh
git -c user.name="David García Gordo" -c user.email="garcia.gordo.david@gmail.com" commit -m "feat(discovery,delivery): business-impact question/message style for non-technical owners

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: Bilingual docs — quickstart rewrite, `--tier=` moved to Advanced

**Files:**
- Modify: `docs/USAGE.md`, `docs/USAGE.es.md`
- Modify: `README.md`, `README.es.md`
- Modify: `commands/run.md`
- Test: `tests/test_zero_friction_ux.sh` (append)

**Interfaces:**
- Consumes: nothing from Tasks 1-2 (docs describe the feature, don't depend on its code existing
  yet at test-time — the assertions are prose-only, same as every other doc test in this repo).
- Produces: nothing (final task).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_zero_friction_ux.sh` (before the final `if` block):

```bash
# ===== Task 3: bilingual docs =====
usage_en="$(cat "$PLUGIN_ROOT/docs/USAGE.md" 2>/dev/null)"
usage_es="$(cat "$PLUGIN_ROOT/docs/USAGE.es.md" 2>/dev/null)"
readme_en="$(cat "$PLUGIN_ROOT/README.md" 2>/dev/null)"
readme_es="$(cat "$PLUGIN_ROOT/README.es.md" 2>/dev/null)"
cmd_run="$(cat "$PLUGIN_ROOT/commands/run.md" 2>/dev/null)"

assert_eq "0" "$(has "$usage_en" '/swarm "')" "USAGE.md quickstart uses the single /swarm command"
assert_eq "0" "$(has "$usage_es" '/swarm "')" "USAGE.es.md quickstart uses the single /swarm command"
assert_eq "0" "$(has "$usage_en" 'Advanced')" "USAGE.md has an Advanced section for --tier="
assert_eq "0" "$(has "$usage_es" 'Avanzado')" "USAGE.es.md has an Avanzado section for --tier="
assert_eq "0" "$(has "$readme_en" '/swarm "')" "README.md quickstart example uses /swarm"
assert_eq "0" "$(has "$readme_es" '/swarm "')" "README.es.md quickstart example uses /swarm"

# --- init.md/doctor.md are NOT deleted (regression guard) ---
assert_eq "0" "$([ -f "$PLUGIN_ROOT/commands/init.md" ] && echo 0 || echo 1)" "commands/init.md still exists (not deleted)"
assert_eq "0" "$([ -f "$PLUGIN_ROOT/commands/doctor.md" ] && echo 0 || echo 1)" "commands/doctor.md still exists (not deleted)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd /Users/davidgarciagordo/projects/multiagents
bash tests/test_zero_friction_ux.sh
```

- [ ] **Step 3: Rewrite `docs/USAGE.md`'s quickstart, add an Advanced section**

Read the current quickstart section (near the top, search for the first code block showing
`/swarm:run`). Replace the primary example with `/swarm "<goal>"`. Add a new `## Advanced` section
(or extend an existing one if the file already has a natural place) documenting `--tier=` for
power users — this is where the flag's documentation MOVES to, not duplicated.

- [ ] **Step 4: Mirror in `docs/USAGE.es.md`** (same location, translated, `## Avanzado`)

- [ ] **Step 5: Update `README.md`/`README.es.md`'s quickstart example** to `/swarm "<goal>"`

- [ ] **Step 6: Update `commands/run.md`'s frontmatter** — `description`/`argument-hint` present
  the command as the simple `/swarm` surface, no `--tier=` in the primary description (it can stay
  functional/accepted, just not advertised there).

- [ ] **Step 7: Run tests, verify they pass; full suite**

```bash
bash tests/test_zero_friction_ux.sh
for f in tests/test_*.sh; do bash "$f" || echo "FAIL: $f"; done
```

- [ ] **Step 8: Commit**

```bash
git add docs/USAGE.md docs/USAGE.es.md README.md README.es.md commands/run.md tests/test_zero_friction_ux.sh
git -c user.name="David García Gordo" -c user.email="garcia.gordo.david@gmail.com" commit -m "docs: zero-friction quickstart — single /swarm command, --tier= moved to Advanced

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Post-plan: expected review pattern

Same as every `agents/orchestrator.md`-touching change today: after all 3 tasks are committed,
dispatch an Opus review of the full diff against master. Expect 1-3 rounds before clean approval —
Task 1 touches this session's most regression-prone file and introduces a genuinely new control
flow branch (auto-init) in the health-gate, worth adversarial scrutiny on: does the auto-init
branch correctly re-check health after initializing (not just assume success)? Does it avoid a
partial-init state if `swarm-init.sh` itself fails mid-way? Merge to `master`, run the full suite
once more on the merged result, push.
