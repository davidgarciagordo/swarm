**English** | [Español](README.es.md)

# swarm — Usage Examples

> Copy-paste prompts showing what fires at each step, for different kinds of goals.

These are real prompts — paste one into Claude Code with swarm installed. Each example shows which domains chain, which gates ask you something, and what "done" looks like for that path. See `docs/USAGE.md` for the full guide and `README.md`'s [How it works](../README.md#how-it-works) for the architecture.

---

## 1. A well-scoped feature — the full tier:full path

```
/swarm:run "add CSV export to the invoices list"
```

**What fires:** `.swarm/` initializes itself if it doesn't exist yet (no separate `/swarm:init` needed). `memory-orchestrator` checks the repo's tree hash — first run, no pack yet, so `memory-builder` scans once and writes `.swarm/context-pack.md`; every later agent in this run reuses it. `discovery-orchestrator` asks ONE batch of plain-language questions (e.g. "export as CSV or also Excel?", recommendation pre-marked) and records the answers. `design-orchestrator` runs `pattern-advisor` + `domain-modeler`, then `planner` writes a real plan file, then grill×3 attacks it — if a P1 finding surfaces (say, the operator lens flags "what happens when the invoice list is empty?"), `planner` revises the plan before it's marked arbitrated. `implementation-orchestrator` sequences TDD (RED → GREEN in an isolated worktree) → `reviewer` (severity-tagged, pre-merge) for each phase — only when you explicitly ask for implementation, never auto-chained. Delivery (push/PR) is a separate, explicit invocation with its own approval gate — swarm never merges or publishes on its own.

## 2. A refactor that skips discovery but still needs design

```
/swarm:run "extract the billing calculation logic into its own module, no behavior change"
```

**What fires:** a refactor/migration objective has no product decision to ask about, so `discovery-orchestrator` is skipped — but the objective is substantial enough to still need a real redesign, so `design-orchestrator` is launched directly (the second of its two entry paths). `pattern-advisor` + `domain-modeler` + `planner` + grill×3 run exactly as in example 1; the only difference is there's no discovery step first, and `design-orchestrator`'s decisions `context:` arrives empty (expected, not an error).

## 3. An ambiguous objective — the interpretation gate asks first

```
/swarm:run "make the dashboard better"
```

**What fires:** before anything else, the objective-interpretation gate checks confidence. "Better" names no concrete outcome, so instead of guessing, swarm asks in plain language — something like: *"¿Qué es lo que más te importa mejorar del dashboard?"* with options such as "que cargue más rápido", "que se entienda mejor de un vistazo", "que se pueda personalizar" — recommendation pre-marked, plus the option to type your own. The run doesn't even open until you answer. Reply to the same raw text again later and swarm reuses this same interpretation — it won't ask twice.

## 4. Same raw objective, already interpreted — no repeat question

```
/swarm:run "make the dashboard better"
```

**What fires (the second time you run this exact text):** the interpretation gate finds a prior decision in `.swarm/decisions.md` whose `raw:` matches, already resolved — it skips straight to the resolved objective and continues, no `AskUserQuestion`. This is why example 3's question only costs you once, not once per run.

## 5. A narrow, single-domain question — tier:light, no chaining

```
/swarm:run "which files touch the payments module?" --tier=light
```

**What fires:** `--tier=light` runs exactly one domain and stops — no discovery, no design, no chaining. For an objective this narrow, `analysis-orchestrator` picks the lenses that match ("architecture", here) and forwards their findings directly, `file:line` cited, no owner question involved. (Power-user/CI flag — see `docs/USAGE.md`'s Advanced section; most objectives don't need it, swarm infers `tier` from what you asked.)

---

## Composing with the family

Design's grill×3 reuses **`working-methods`**'s `grill-architect/operator/engineer` agents when that plugin is installed, and swarm's own native equivalents otherwise — same attack, same output contract, never both at once. No other plugin in the family is required for swarm to run end to end.
