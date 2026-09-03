# Using swarm

A complete, standalone guide for someone who has never seen this plugin before. If you just want
the project status (what's built, what's planned), read `README.md` — this doc is about how to
actually run it.

## 1. What is this

`swarm` is a Claude Code plugin: it runs a swarm of single-responsibility subagents that help you
through the software development lifecycle on a real repo — understanding a codebase, auditing it,
designing a change, and implementing it. Every agent has one job (a security auditor never writes
code, a planner never implements), and a root orchestrator wires them together and reports back a
short, evidence-backed verdict instead of a wall of narration. The human stays in control of what
actually gets built: the swarm asks real questions when a decision needs a person, and it never
pushes anything anywhere on its own.

## 2. Installation

There is no marketplace listing for this plugin yet, so today the only real install path is local:
point Claude Code at the checkout directly.

```bash
claude --plugin-dir /path/to/multiagents
```

Replace `/path/to/multiagents` with wherever you cloned this repo (for example
`/Users/davidgarciagordo/projects/multiagents`). This loads the plugin's commands, agents, skills
and hooks for that session — the three `/swarm:*` slash commands become available, and its agent
definitions become invokable from anywhere in the conversation. There's nothing to `npm install` or
build first: it's a set of markdown agent/command/skill files plus a few shell scripts, read
directly by Claude Code.

Once loaded, run `/swarm:init` once inside the target repo (the repo you actually want to work on —
it doesn't have to be this one) before doing anything else. That creates the `.swarm/` directory
this plugin uses for memory. See §3 below.

If this plugin is ever published to a marketplace, installation would instead go through Claude
Code's normal plugin-marketplace flow (`/plugin install swarm` or equivalent) — but that path does
not exist yet, so don't follow instructions that assume it does.

## 3. The 3 commands

These are the *only* three slash commands this plugin defines — real files under `commands/`:
`commands/init.md`, `commands/run.md`, `commands/doctor.md`. Nothing else (`/swarm:status`,
`/swarm:findings`, etc.) is implemented yet, even though the design spec sketches them for a later
phase — don't type them expecting them to work.

### `/swarm:init`

Bootstraps `.swarm/` in the current repo: the directory tree, `memory.json` (declaring the `files`
backend as required), `decisions.md` with its header, and a `# swarm` block appended to
`.gitignore` so the swarm's working state never gets committed. It also runs a health-gate on the
backend before declaring success. Takes no arguments.

```
/swarm:init
```

You run this once per repo, before your first `/swarm:run`. Internally it just executes
`${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh` and reports the script's own plain-text summary
verbatim — if the script exits non-zero, the command tells you `/swarm:init` aborted and shows the
stderr line that explains why (from `docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md`
item 1: the expected result is `.swarm/` created, `memory.json` with the `files` backend required,
`decisions.md` with its header, the `.gitignore` block marked `# swarm`, and the health-gate green).

### `/swarm:run`

The main entry point. Launches the root `orchestrator` agent on a goal you describe in plain
language, with an optional tier flag.

```
/swarm:run <goal> [--tier=direct|light|full]
```

For example: `/swarm:run "añadir export CSV del listado de facturas" --tier=full`. The command
always invokes the `swarm:orchestrator` subagent with your exact argument text, even if it's empty
— the orchestrator itself decides whether the goal is valid and returns its own verdict; the
outer session never answers on your behalf or asks you to clarify before spawning it.

**Tiers** (from `agents/orchestrator.md` §1.1 and the spec §9.1):

- `direct` — a trivial, single-file, no-architectural-decision goal. The root answers you directly,
  without opening a run or launching any domain. Nothing gets written to `.swarm/run/`.
- `light` — a single domain. Judgment leaves (auditors, planner, pattern-advisor, etc.) run on
  `sonnet` instead of `opus`, no adversarial grill, and the memory pack is only rebuilt if stale.
- `full` — multi-domain or explicitly critical work. Judgment leaves run on `opus`, and design goes
  through the grill×3 adversarial review before it's considered done.

If you don't pass `--tier`, the orchestrator classifies it for you by scope. You can always force
it explicitly with the flag — an invalid value (anything other than exactly `direct`, `light`, or
`full`, case-sensitive) is rejected outright rather than guessed at.

**Routing — how your goal picks a domain.** The root never runs everything; it reads your goal and
picks the domain(s) that apply:
- A **product** goal ("add X", "build a new Y", any user-visible behavior change) routes to
  **discovery** first — and, only in `tier: full`, chains into **design** afterward once discovery's
  questions are answered.
- An **analysis** goal ("audit X", "review the security of Y", "find performance problems in Z")
  routes to **analysis** instead — read-only, no questions asked. Discovery and analysis are
  mutually exclusive in the same run: if your goal reads as "product", analysis never runs, and vice
  versa.
- A bugfix, refactor, docs change, or infrastructure task skips discovery and analysis — the root
  just says so in the output (`- discovery omitido: ...`) and, in `tier: full` with no product
  decisions to design against, design is skipped too.
- **Implementation** never auto-chains after discovery or design, in any tier — it only runs when
  you explicitly ask the swarm to build a plan that already exists ("implement the plan for X",
  "build X per the design already written"). This is a deliberate human checkpoint: writing and
  merging real code is the most consequential thing the swarm does, so a discovery+design run always
  stops with a reviewable plan file instead of silently proceeding to code.

**Real worked example** (`docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md`, items 2, 6
and 7 — verified live):

```
/swarm:run "audita memoria" --tier=light
```
Result (after a real bug fix mid-smoke): pack rebuilt for real (`context-pack.md` with a real
`stack: php-ddd-symfony8` line), `index.md` sealed, run closed via `curate`. A second identical run
against the same, unchanged repo does *not* rebuild the pack — the staleness check short-circuits
it (item 3).

```
/swarm:run
```
(no argument at all) returns, without opening any run:
```
BLOCKED objetivo vacío — describe qué quieres que haga el enjambre
```

```
/swarm:run "audita memoria" --tier=medium
```
(`medium` is not a valid tier) returns, again without opening a run:
```
BLOCKED --tier inválido: medium (usa direct, light o full)
```

### `/swarm:doctor`

Checks the repo's environment requirements — the OS-level tools the plugin (and any active stack
pack) needs — against `requirements.json`. Takes no arguments; any text you type after the command
is ignored.

```
/swarm:doctor
```

It always invokes the `swarm:requirements-orchestrator` subagent with `operation: check`, which in
turn spawns `env-checker` to run the deterministic check (`scripts/req-check.sh`) rather than
re-implementing tool-presence logic itself. The plugin's own `requirements.json` currently declares
`git`, `python3`, and `uuidgen` as `required: true`, and `jq`, `gh`, `docker` as optional. Real
worked example, run against the plugin's own checkout (which has all three required tools):
`docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md` item 1 confirms
`requirements-orchestrator` launches `env-checker` (named exactly `env-checker`, spawned with
`Agent`, never `SendMessage`) and the final verdict is `OK`. If a required tool is missing, the
verdict is `BLOCKED <tool>` with the install hint from `requirements.json` (`brew`/`apt` command),
propagated literally from `env-checker` up to what you see — verified against the script directly
in item 2 of that same checklist.

## 4. The domains

Every domain below is a real, built, working part of the swarm today — verified in a live smoke
test, not just designed on paper. `/swarm:run` routes to these automatically per §3 above; you never
invoke a domain orchestrator by its subagent name yourself in normal use.

### Memory

**What it does for you:** keeps a compact, reusable understanding of your repo (`.swarm/`) so every
other domain reads the same shared context instead of re-scanning the codebase from scratch each
time, and records every decision and finding so a later run over the same goal doesn't ask the same
question twice. It owns `.swarm/context-pack.md` (the repo snapshot: stack, structure, key
excerpts), `.swarm/decisions.md` (every discovery answer, keyed by the literal objective text), and
`.swarm/findings/` (every audit/design/review finding, deduplicated by agent+tag+file:line).

**What triggers it:** automatically, on every `light`/`full` `/swarm:run` — you don't invoke it
directly. `memory-orchestrator` is the first domain orchestrator the root launches after opening a
run, before discovery, analysis, design, or implementation, and it owns two leaves of its own:
`memory-builder` (rebuilds the pack) and `memory-curator` (compacts findings, garbage-collects old
runs).

**What you get back:** nothing visible on its own in normal use — its job is to make every other
domain's output better and cheaper. You *do* see its effect: a rebuilt pack is announced in the run
summary, and a second identical run against an unchanged repo visibly skips the rebuild.

**Real example** (phase 1 smoke checklist, items 2–3): first `/swarm:run "audita memoria"
--tier=light` rebuilt `context-pack.md` with a real `stack: php-ddd-symfony8` line and sealed
`index.md`; the identical run repeated immediately after, with the repo untouched, left
`context-pack.md`'s file-modification time unchanged — confirming the staleness check
(`mem-stale.sh check`, a tree-state hash) avoided relaunching the pack builder.

### Requirements

**What it does for you:** three separate jobs behind one domain. It verifies the tools your OS
actually has against what the plugin (and any active stack pack) declares it needs (`env-checker`,
operation `check`); it audits your project's own dependencies for CVEs, outdated packages and
license risk (`dependency-auditor`, operation `audit-deps`); and, only with your explicit,
itemised approval, it installs or updates exactly the packages you approved (`dependency-installer`,
operation `install`).

**What triggers it:** `check` runs via `/swarm:doctor` (see §3) — a separate, explicit step, not
part of the `/swarm:run` pipeline. `audit-deps` and `install` run *inside* a `/swarm:run` (phase
5b) when your goal is dependency-shaped: "audit the dependencies", "what libraries are outdated",
"install phpstan", "bump doctrine to 3" — see `agents/orchestrator.md` §11.

**The install gate — the swarm never installs anything on its own judgement.** Installing or
updating dependencies mutates the repo outside any worktree, without going through `reviewer`.
So the root always audits first, then presents you with **one** `AskUserQuestion` **multi-select**
batch — one option per concrete package, plus "install nothing" — and only the packages you
actually check get translated into a literal `approved: <pkg>:<version> ...` line that
`dependency-installer` executes exactly, and nothing more. If you check nothing or dismiss the
dialog, nothing gets installed, and the run still closes cleanly reporting that. `dependency-
installer` never commits: it leaves the manifests modified on disk and tells you exactly which
files changed, so you (or a later `implementer`, inside its own phase) commit them with context.
System tools (`brew`/`apt`) are never installed by the swarm — they come back as a hint with the
exact command for you to run yourself.

**What you get back:** `check` → `OK` if everything `required: true` is present, or `BLOCKED <tool>`
naming the exact missing tool plus its install hint (a `brew`/`apt` command). `audit-deps` → a list
of `DEP · file:line · problem → fix` findings. `install` → a `- instalado: ...` / `- modificado:
...` summary of exactly what changed, or `BLOCKED sin aprobación del owner` if the `approved:` line
is missing, empty, or not a literal package list.

**Real example** (`docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md`, item 1): run
against the plugin's own checkout, `requirements-orchestrator` launches `env-checker`, which shells
out to `scripts/req-check.sh`, and the verdict comes back `OK` because `git`, `python3`, and
`uuidgen` are all present on the real machine.

### Discovery

**What it does for you:** turns a vague product goal into a small set of concrete decisions.
`discovery-orchestrator` runs four leaves in parallel — one asks the highest-value question first (`value-critic`), one
researches prior art (`research-analyst`), one generates 2-3 real approaches with trade-offs
(`options-generator`), and one runs a disposable spike to answer a feasibility question
(`feasibility-spiker`) — then merges everything into a single batch of up to four questions that
Claude Code presents to you directly with `AskUserQuestion`.

**What triggers it:** a product-shaped goal ("add X", "build a new feature that does Y", any
user-visible behavior change) in tier `light` or `full`. Skipped for bugfixes, refactors, docs,
tests, and infra work, and skipped (without re-asking) if `.swarm/decisions.md` already closed the
exact same objective in an earlier run.

**What you get back:** an interactive question dialog (this is the one point in the whole swarm
where it pauses and waits for you), then a single recorded decision line in `.swarm/decisions.md`
listing every question and your answer, prefixed with the literal goal text so a later run
recognizes it. If you dismiss the dialog, your (unanswered) batch is still saved, marked
`[pendiente]`, instead of being silently lost.

**Real example** (`docs/superpowers/plans/2026-09-02-phase2-smoke-checklist.md`, item 1, run live by
the owner): `/swarm:run "añadir export CSV del listado de facturas" --tier=full` produced a real
4-question batch, presented via `AskUserQuestion`, answered, and recorded in `decisions.md` complete
with the literal `objective:` field. The run also caught a genuine conflict between two of the
answers (full history vs. a synchronous endpoint) that `value-critic` had already flagged to
`options-generator` via mailbox — resolved by the owner picking an async queue job, recorded as a
`SUPERSEDE`/`CONFLICTO RESUELTO` line.

### Analysis

**What it does for you:** a read-only audit of your codebase. `analysis-orchestrator` picks a subset
of up to six lenses — architecture
(`architecture-auditor`), security (`security-auditor`), dependency/secret scanning
(`vulnerability-scanner`), performance (`performance-analyst`), schema/data-model drift
(`data-model-auditor`), and technical-debt/ROI opportunities (`opportunity-analyst`) — chosen by
keyword match against your goal, run in parallel, and forwarded to you as findings.

**What triggers it:** an explicitly analysis-shaped goal ("audit X", "review the security of Y",
"find performance issues", "audita todo") in tier `light` or `full`. It never runs in the same run as
discovery — a goal is either "product" (discovery) or "analysis" (this domain), never both.

**What you get back:** a list of findings, each one line: `TAG · file:line · problem → fix`, plus a
line naming which lenses ran and why. No questions asked — analysis never invokes `AskUserQuestion`.

**Real example** (`docs/superpowers/plans/2026-09-02-phase3-smoke-checklist.md`, item 1):
`/swarm:run "audita la seguridad de InvoiceController" --tier=full` selected
`security-auditor` + `vulnerability-scanner` (goal matched "seguridad") and returned real findings
against the fixture: `CRITICO` tenant isolation missing at `InvoiceController.php:12`, `ALTO` SQL
injection at `:14`, `ALTO` missing authorization check at `:9`. The run closed with
`- run cerrado: DONE · análisis completado, 3 hallazgos`.

### Design

**What it does for you:** turns closed product decisions into a real, reviewable implementation
plan. `pattern-advisor` and `domain-modeler` run together first (pattern fit and domain modeling),
then `planner` writes an actual plan file under `docs/superpowers/plans/` with phases, disjoint
areas, and risks. In `tier: full` the plan is then adversarially reviewed by three external grill
lenses (`working-methods:grill-architect/operator/engineer` — the platform-architecture lens,
the real-user lens, and the technical-engineering lens), and `design-orchestrator` itself arbitrates
their findings and revises the plan — without ever asking you anything mid-design.

**What triggers it:** only `tier: full`, and only after discovery has closed its decisions (either
in this same run, or in an earlier one over the same objective). It's never launched in `tier:
light` (light is single-domain by design), and it's skipped whenever discovery was also skipped.

**What you get back:** a single `PLAN · <path>:1 · <short summary>` line pointing at the real plan
file on disk, plus a `- grill: ...` line summarizing what the adversarial review changed or flagged.
No questions asked here either.

**Real example** (`docs/superpowers/plans/2026-09-03-phase4-smoke-checklist.md`, item 1): with the
"añadir export CSV del listado de facturas" objective already closed in `decisions.md`,
`design-orchestrator` launched `pattern-advisor` + `domain-modeler` (real findings: `PATTERN ·
src/Controller/InvoiceController.php:11 · introduce Repository...`, `MODEL · ...Invoice raíz de
agregado...`), then `planner` wrote a genuine 154-line plan at
`docs/superpowers/plans/2026-09-03-export-csv-facturas.md`. All three grill lenses ran for real and
found substantive P1 issues (a missing UTF-8 BOM for Excel compatibility, a `StreamedResponse`
truncation bug after headers were already sent, a bounded-context mismatch between the aggregate and
its mapper) — `design-orchestrator` correctly relaunched `planner` with `operation: revise` to
incorporate them.

### Implementation

**What it does for you:** executes exactly one phase of an already-designed, already-arbitrated plan
— for real, with real tests and a real local merge, never partway. The sequence is strict, and each
step depends on the one before it, never in parallel: `test-writer` commits a failing (RED) test to
the run's branch; `implementer` runs in an isolated git worktree to make it pass (GREEN) and commits
there; `migration-engineer` runs next, *only if* the phase touches the persistence schema (entities,
mappings, tables/columns), writing a migration file inside that same worktree — it never applies a
migration against a real database; `doc-writer` runs next, *only if* the phase changes observable
behaviour (a new use case, endpoint, console command, public contract) and the turn budget allows
it, writing docs in the active stack pack's format plus a changelog entry, inside the same worktree;
`quality-fixer` then runs the stack's deterministic `--fix` (lint/format) and patches whatever it
can't auto-fix; and `reviewer` gates the result with severity-tagged findings *before* anything
merges. Only after that gate passes does `implementation-orchestrator` merge the worktree's commit
locally into the run's own branch and clean up the worktree.

**What triggers it:** only an explicit request naming a plan ("implement the plan for X", "build X
per the design already written") — never automatically after discovery or design finish, in any
tier. This is a deliberate safety checkpoint: writing and merging real code is the swarm's most
consequential action, so a plan always stops for human review before it's built.

**What you get back:** a `- implementation: ...` summary line naming which phase merged, to which
branch, through which agent chain, and how many plan steps got checked off — plus, if the reviewer
found anything below merge-blocking severity, explicit `- riesgo aparcado: ...` lines so nothing is
silently swallowed.

**Real example** (`docs/superpowers/plans/2026-09-03-phase5a-smoke-checklist.md`, item 1):
`implementation-orchestrator`, invoked adhoc on a real plan for a `Money` value object with a
currency invariant, produced two real commits on `run-branch` (`test-writer`'s RED commit
`7e144a9`, `implementer`'s GREEN commit `a293ff5` with real `fichero:línea` citations for each
checked-off step), `quality-fixer` iterated twice, and `reviewer` found three real `MINOR` issues
(unvalidated currency, `PHP_INT_MAX` overflow, `.gitignore` missing `vendor/`) that were explicitly
parked rather than blocking the merge. The final verdict:
```
DONE
evidence: files=9 cmds=17 turns=19/25
- implementation: Phase 1 fusionada a run-branch (test-writer→implementer→quality-fixer×2→reviewer), 2 steps [x]
```
It never touches `master` or a shared branch, and never runs `git push` — no agent in this domain
even has that tool in its allowlist.

**What's not built yet:** the `delivery` domain (release/PR/handoff automation) is still planned,
not available. See `README.md`'s "Current status" section for the exact, up-to-date built/planned
breakdown — this doc won't duplicate and risk drifting from that list.

### Stack packs

**What it is:** stack-specific knowledge — naming/layering conventions, the canonical form of each
lint/test/scan command, patterns already in use in the codebase, boundaries nothing should touch,
and extra OS/library requirements — that swarm leaves read instead of guessing generically. There is
exactly one today: `skills/pack-php-ddd-symfony8/` (PHP + DDD + Symfony).

**How it's detected:** automatically, no configuration needed. When `memory-builder` builds
`.swarm/context-pack.md`, it checks whether the repo's `composer.json` exists at the root and its
`require` block contains a `symfony/*` package; if so it writes `stack: php-ddd-symfony8` into the
pack. Every leaf that can use a pack (`quality-fixer`, `test-writer`, `implementer`,
`migration-engineer`, `doc-writer`, `pattern-advisor`, `domain-modeler`, `vulnerability-scanner`,
`dependency-auditor`, `env-checker` via `requirements-orchestrator`) resolves its absolute path from
that line and reads only the files it needs.

**What happens without one:** nothing breaks. A repo with no `composer.json`, or one that doesn't
match a known pack, gets `stack: generic` — no `pack:` line is ever sent to a leaf, and each one
falls back to its own documented generic behavior (detect whichever manifest is present, imitate the
newest matching file already in the repo, never invent a command it hasn't seen documented there). A
pack is purely additive: what it doesn't cover, a leaf resolves with its generic judgment instead.

## 5. How to read the output

Every agent in this swarm — root orchestrator, domain orchestrators, and leaves alike — reports
through the same evidence contract (`docs/superpowers/specs/2026-09-01-swarm-design.md` §6,
enforced live by a hook, `skills/swarm-protocol/SKILL.md` §4). Once you know this format, you can
read *any* domain's output the same way:

```
<verdict>
evidence: files=N cmds=M turns=k/max
<finding lines, optional>
```

- **Line 1 is always the verdict**, one of exactly four shapes:
  - `OK` — the agent checked something and it's fine, no changes needed.
  - `KO <reason>` — the agent checked something and found the worst problem is `<reason>`.
  - `DONE` — the agent did the work it was asked to do, successfully.
  - `BLOCKED <reason>` — the agent could not proceed, and `<reason>` says why.
- **Line 2 is mandatory**: `evidence: files=N cmds=M turns=k/max` — `N` files actually read, `M`
  deterministic commands actually run, and `k/max` the turn count against that agent's turn budget.
  A verdict without this line is rejected automatically by a hook before it ever reaches you — and
  so is an `OK` claiming `files=0` (a green verdict with no evidence behind it isn't trusted).
- **Everything after that is findings**, one per line, in the fixed shape
  `TAG · file:line · problem → fix` — a short tag (`SEC`, `ARCH`, `PATTERN`, `PLAN`, …), the exact
  file and line the finding is about, the problem in a few words, and the fix in eight words or
  fewer. Full detail (long context, snippets) lives in `.swarm/findings/<agent>.md`, never inline —
  what you see in the output is deliberately terse by design, not truncated by accident.

So a design run's output like
```
DONE
evidence: files=3 cmds=7 turns=15/30
PLAN · docs/superpowers/plans/2026-09-03-export-csv-facturas.md:1 · plan listo, 4 tareas → revisar antes de fase 5
- grill: 1 P1 incorporado (idempotencia del export), 2 P2 anotados como riesgo
```
reads as: the run succeeded (`DONE`), it's backed by real evidence (3 files read, 7 commands run,
finished on turn 15 of a 30-turn budget), the plan is at that exact path and line, and the
adversarial review incorporated one high-priority fix while flagging two lower-priority risks for
later.

## 6. Frequently asked questions / honest limitations

**Does the swarm ever push to git, or touch `master`/a remote branch on its own?** No, never.
`implementation-orchestrator` always merges locally, into the run's own branch — never into
`master` or any shared/remote branch, and no agent in the implementation domain has `git push` in
its tool allowlist. A guard checks `HEAD` isn't `master` before it ever merges.

**Can I run this fully headless / non-interactively?** Mostly, but not discovery. Discovery's whole
point is asking you real questions via `AskUserQuestion`, so a run that routes to discovery will
pause and wait for a human in an interactive session — it cannot complete in a scripted, non-TTY
invocation (`claude -p`) the way analysis, design, or implementation runs can, because there's no
one there to answer. If you dismiss the dialog instead of answering, the swarm doesn't lose your
place: it records the unanswered batch as a `[pendiente]` decision so a later run can pick it back
up instead of asking the same four questions again.

**What happens when something comes back `BLOCKED`?** The run still closes cleanly — a summary line
is written to `.swarm/run/<id>/summary.md` and the memory layer is curated before the verdict
reaches you, so a `BLOCKED` run is never left half-open. The `<reason>` after `BLOCKED` is meant to
be actionable: a missing tool names itself and its install command (`/swarm:doctor`), an empty
`/swarm:run` goal tells you to describe what you want, an invalid `--tier` lists the three valid
values. If a domain orchestrator itself returns `BLOCKED`/`KO`, the root propagates that exact
message rather than paraphrasing it, so what you read is literally what the domain that failed
said.

**Does it re-read my whole codebase every time?** No — that's the point of the memory domain (§4).
`.swarm/context-pack.md` is built once and reused across runs; it's only rebuilt when the repo's
tree-state hash shows it's actually stale. Findings are deduplicated by `agent+tag+file:line`
across runs too, so re-running the same audit twice in a row doesn't produce duplicate findings
(verified live in `docs/superpowers/plans/2026-09-02-phase3-smoke-checklist.md` item 6).
