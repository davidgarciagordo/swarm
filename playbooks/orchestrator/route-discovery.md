# orchestrator · route discovery
On demand from agents/orchestrator.md — trigger: §5.1 classifies the objective as product.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 5.1 How you check "already closed" (the HOW matters)

The match is against the **`raw:`** field and **never** against `objective:`: `objective:` can be an LLM interpretation
that differs between runs for the SAME raw text, so it would never match and the owner would answer the same batch
forever. `raw:` is deterministic: the owner's text, byte for byte.

Take THIS run's raw `/swarm:run` argument without the `--tier` flag — the same one §1.0bis Step 1 used, NOT the text
resolved by the gate — and run it through the **sanitization in §5.0**, the same one §5.3/§5.4 applied when saving it.
BOTH sides must be sanitized: the saved `raw:` is already sanitized, so an unsanitized comparison never matches as soon
as the text carries a backtick, `$`, `"` or `\` ("let's migrate the old `parseCSV()`" is a normal objective).

`Read` `.swarm/decisions.md` and look for a line that meets BOTH conditions:
1. its **`raw:`** field (§5.3/§5.4 always write it first) equals it, and
2. it's a **discovery close** line — it carries the `discovery <run-id>` marker.

Condition 2: `decisions.md` is one flat file, and §2.3 may have written a `resolved interpretation` line with the same
`raw:` in THIS run; without condition 2 the run would skip discovery by its own side effect. Explicitly ignore any line
marked `resolved interpretation`. Several discovery-close lines ⇒ keep the LAST one (append-only, chronological).
- A line with no `raw:` field doesn't match — never force it by comparing its `objective:` (the objective gets asked
  once more; the §5.4 line written then carries both fields).
- The match is also **never** against the question text: `value-critic` regenerates questions every run.
- A matched line marked `[pending]` (§5.3: owner cancelled) or `ASSUMED` (§13.4) is NOT closed — present the batch
  again (non-interactive: §13.4 applies again).

**"Already closed" and `tier: full`:** don't stop at `- discovery omitted: …` — chain §9 (design) with the already-closed
decisions as context, exactly as §5.4 chains after a fresh batch. In `tier: light` you don't chain: the
`- discovery omitted: <reason>` line is all you emit before closing (§4).

### 5.2 Launch (sequential relative to memory)

Launch `discovery-orchestrator` **after** the `OK`/`DONE` from `memory-orchestrator` (`operation: build`, §2.2) — NOT in
the same batch: the pack must exist when its leaves start, and `memory-orchestrator` must already be alive to enter
`feasibility-spiker`'s roster (it writes `.swarm/` only through it, protocol §3). This breaks §2.2's same-batch rule on
purpose: leaf → `memory-orchestrator` works (it was alive at the leaves' snapshot); the reverse direction uses the
protocol's **mailbox mirror** (protocol §1/§4.1: `mem-files.sh write mailbox --to <agent>`, which
`memory-orchestrator` mirrors into the peer-to-peer `SendMessage`s it forwards — the real scope of the mandatory mirror,
agents/memory-orchestrator.md "Mailbox mirror"; each agent reads `run/<run>/mailbox/<your-name>.md` at startup). The
mailbox doesn't depend on the roster snapshot.

Register it beforehand in the manifest, then launch:
```bash
"<plugin-root>/scripts/mem-manifest.sh" register --run <run-id> --agent discovery-orchestrator --domain discovery --area "." --owner orchestrator
```
```
Agent(subagent_type: "swarm:discovery-orchestrator", name: "discovery-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <absolute path of .swarm>
  operation: discover
  tier: <light|full>
  objective: <the owner's literal objective, without the --tier flag>)
```

### 5.3 Presenting the batch (`AskUserQuestion`, one single round)

Its output carries up to four lines in this exact format:
```
- Q<n> [<header>] · <question> · A) <option> · B) <option> [· C) <option>] [· D) <option>] · rec: <letter>
```
**MANDATORY pre-flight before calling `AskUserQuestion`** (the tool rejects the ENTIRE call if a SINGLE question is
malformed — you'd lose the run's only interactive moment). Validate every `- Q` line:
- **options**: 2 to 4 markers, consecutive from `A)` (`A)`+`B)`, `A)`+`B)`+`C)`, or all four; never 1, never a gap);
- **header**: the `<header>` in brackets is ≤12 characters;
- **`rec:`**: present, and its letter is one of the options in the line.

Any failure ⇒ don't call `AskUserQuestion`; your verdict is:
```
BLOCKED malformed batch from discovery-orchestrator: <what failed, citing the specific Q<n>>
```
**Before returning that `BLOCKED`, close the run** — summary first, `curate` after, wait for its `DONE`:
```bash
"<plugin-root>/scripts/mem-manifest.sh" summary --run <run-id> --line "- run closed: BLOCKED malformed batch from discovery-orchestrator"
```
```
SendMessage(memory-orchestrator, "curate")
```
A `BLOCKED` without `curate` leaves the manifest open and the run's history lost.

With the batch validated, ONE `AskUserQuestion` call, `questions` = one entry per `- Q` line:
- `header`: the `<header>`; `question`: the `<question>`;
- `options`: one per letter, `label` = the option text; the `rec:` one goes **FIRST** with the suffix ` (Recommended)`
  in its `label`; `description` = `recommended by discovery-orchestrator` for it and `alternative` for the rest;
- `multiSelect: false` (the owner always has "Other" for free text).
Never one call per question, never a second round: a follow-up question becomes a pending decision, not a re-ask.
`- findings: …` and `- warn: …` lines are NOT questions.

- **`BLOCKED …`/`KO …` with no `- Q` lines:** don't call `AskUserQuestion`; propagate its literal verdict, but close the
  run like any terminal verdict (`summary` with `- run closed: <literal verdict from discovery-orchestrator>`, then
  `curate`, wait for `DONE`) before returning — a run left open hides the failed attempt from a retry.
- **`KO …` WITH `- Q` lines** (partial batch, one judgment leaf down): present the batch anyway and propagate its
  literal reason in a `- …` line of your output; `summary`+`curate` come after the owner answers (§5.4).
- **`DONE`/`OK` with ZERO `- Q` lines (empty batch) is a producer bug, not a green run** — unless YOU sent `leaves:`
  (research-only, sizing.md): then no batch is expected, skip the questions and continue. No other legitimate discovery path
  ends that way: 0 value questions + 1 viable approach still yields ONE confirmation `- Q` (`Approach`, A) that approach
  · B) don't build yet); no viable approach ⇒ `BLOCKED no viable approach` (path above);
  `- warn: no viability question, spiker not launched` accompanies Qs, never replaces them. Otherwise your verdict is
  `BLOCKED empty batch from discovery-orchestrator`; close it like any terminal path (`summary`, `curate`, `DONE`).
- **The owner cancels or dismisses the dialog** (normal, not an error): don't retry, don't re-ask, don't take `rec:`.
  Register the batch as a **PENDING** decision — ONE write, same one-line format and §5.0 sanitization as §5.4:
  ```
  SendMessage(memory-orchestrator, "write decision --text \"raw: <sanitized raw argument> · objective: <sanitized literal objective> · discovery <run-id> [pending] batch left unanswered (owner cancelled) · Q1 [<header>] <sanitized question> · Q2 [<header>] <sanitized question> · …\"")
  ```
  Wait for its `OK`/`written`, close with `summary`+`curate` (§4) and your verdict is `KO batch left unanswered`.
  BOTH fields, `raw:` first (without it §5.1 can't see the line), plus the mandatory `discovery <run-id>` marker (it
  distinguishes the line from §2.3's `resolved interpretation`). `[pending]` lets a later run detect "discovery already
  ran, answers pending" instead of losing the batch.

### 5.4 Recording the answers (ONE single write, never one per question)

You never write `decisions.md` yourself: it goes through `memory-orchestrator`, and **all the answers go in ONE single
`write decision` call** — it has `maxTurns: 12` (startup, `build`, `curate`, plus a claude-mem mirror per write); four
sequential writes exhaust it and silently lose the last decisions **and the closing `curate`**.
`write decision` accepts only `--text` and appends `- <date> · <text>` as ONE line (`scripts/mem-files.sh`,
`_write_decision`): the answers go separated by ` · `, never line breaks. Exact format — `raw:` FIRST, `objective:`
right after (same order as §2.3 and §5.3):
```
SendMessage(memory-orchestrator, "write decision --text \"raw: <sanitized raw argument> · objective: <sanitized literal objective> · discovery <run-id> · Q1 [<header>] <question> → <answer> · Q2 [<header>] <question> → <answer> · …\"")
```
- `<sanitized raw argument>`: the `/swarm:run` argument without `--tier`, as typed, through §5.0 — the text §1.0bis Step
  1 and §5.1 compare against. It's the RAW one, **NEVER the already-interpreted objective** (that would break the
  deterministic idempotency). If the gate didn't fire, `raw:` and `objective:` are identical — write both anyway (one
  format, one parser).
- `<sanitized literal objective>`: THIS run's objective (resolved by §1.0bis, or the raw argument), through §5.0.
- `discovery <run-id>`: the discovery-CLOSE marker §5.1 requires (condition 2) — never omit it.
- `<answer>` (the chosen option or the owner's "Other" text — the most dangerous input) and `<question>` (generated by
  `value-critic`): **always** through §5.0.
- Only the questions actually answered (a cancelled dialog is §5.3's `[pending]` case).

Wait for its `OK`/`written` — a single one. If `tier: full`, chain §9 (design) with these decisions as context — do NOT
close the run yet. If `tier: light`, the run ends here: close with `summary`+`curate` (§4) and return `DONE` with the
decisions as `- …` lines (§7).

### 5.5 Discovery closing lines (§4 summary, one call)

- normal close (§5.4): `- run closed: DONE · discovery answered, <n> decisions saved` (after the §4 verifier gate)
- malformed batch: `- run closed: BLOCKED malformed batch from discovery-orchestrator`
- propagated `BLOCKED`/`KO`: `- run closed: <literal verdict from discovery-orchestrator>`
- empty batch: `- run closed: BLOCKED empty batch from discovery-orchestrator`
- dialog cancellation: `- run closed: KO batch left unanswered (owner cancelled)`
- already closed, `tier: light`: `- run closed: <your verdict> · discovery omitted: <reason>`

### 5.6 Output examples

`tier: light`, discovery legitimately SKIPPED because `decisions.md` already closed this objective — a green run, not a
missing domain (in `tier: full` it chains to §9 instead):
```
DONE
evidence: files=2 cmds=5 turns=7/30
- discovery omitted: decisions.md already closed this objective (objective: student CSV export)
- prior decision: Q1 [Value] who is the CSV export for? → admins
```
Owner cancelled the question dialog — the batch is recorded as `[pending]`, not lost:
```
KO batch left unanswered
evidence: files=2 cmds=5 turns=9/30
- discovery: 4 questions presented, owner cancelled the dialog
- batch saved as [pending] decision in .swarm/decisions.md
```
