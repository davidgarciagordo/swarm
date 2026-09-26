# planner · plan template
On demand from agents/planner.md — trigger: WHEN operation: plan, BEFORE your Write.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## Plan structure

Same header as this repo's `writing-plans` skill PLUS two mandatory literal lines (`**Objective:**`,
`**Grill:** pending`): `design-orchestrator` greps exactly this format in `docs/superpowers/plans/*.md` to
detect whether an objective already has a plan AND whether it already went through the review panel.

```markdown
# <Feature name> Implementation Plan

**Objective:** <the owner's literal objective, as-is, not summarized>

**Grill:** pending

**Goal:** [one sentence]

**Architecture:** [2-3 sentences, based on pattern-advisor's verdict]

**Tech Stack:** [from the context-pack / active stack pack]

## Domain Model

[aggregates/VOs/events/invariants from domain-modeler, in prose — each real invariant becomes an
explicit test requirement in the corresponding step]

## Global Constraints

[whole-project requirements that apply to every phase]

---

## Phases

### Phase 1: <Short phase description>

**Files**: (concrete files/modules this phase touches)
- `src/Module/File.php:10-50` (description of changes)

**Risks**: (what can go wrong; mitigations if any)
- Risk 1
- Risk 2

**Tests**: (what must pass; reference to domain-modeler invariants if applicable)
- Unit: …
- Integration: …

- [ ] Step 1: <concrete 2-5 minute action, with real code, not "add validation"> (`file:line`)
- [ ] Step 2: <concrete 2-5 minute action, with real code> (`file:line`)
- [ ] Step 3: …

### Phase 2: <Short phase description>

**Files**: …

**Risks**: …

**Tests**: …

- [ ] Step 1: …
- [ ] Step 2: …
```

## Content rules

- Each phase groups several bite-sized `- [ ] Step N` items (2-5 minutes each, `writing-plans` grain);
  `Files`/`Risks`/`Tests` live at phase level, not repeated per step. Each step is task-shaped: `implementer`
  executes ONE closed plan task at a time.
- More than 4 phases ⇒ split into versions (v1 MVP, v1.1 extensions, v2 refactor), one plan per version.
- No placeholders ("TBD", "similar to Step N"); every step has real code (not just "add validation");
  disjoint file areas between phases; risks explicitly named at phase level when the objective or the
  review findings leave something open.
