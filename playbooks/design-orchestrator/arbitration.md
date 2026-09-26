# design-orchestrator · arbitration and closing
On demand from agents/design-orchestrator.md — trigger: WHEN review-orchestrator returns.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## Arbitration (it's your responsibility, not the owner's)

The panel already deduped, refuted and scored; you decide what to do with its verdict.
**Do NOT forward the grill lines verbatim** into your own output: they are the panel's; your output only
summarises the arbitration (`- grill: …`).

- **`OK`** (score ≥ 7): no upheld P1. P2/P3 lines: you decide whether they deserve a `planner` revision or
  are noted as a known risk within the plan itself (cheaper, equally honest) — document it
  (`- grill: 0 P1, M P2/P3 noted as risk`). Go to "Closing".
- **`KO score=<n> …`** on round 1: relaunch `planner` ONCE with `operation: revise`, the surviving findings
  as `context:`, and the ESCALATED tier (`<plugin-root>/scripts/model-resolve.sh --escalate <planner's tier>`;
  judgement escalates to itself) — **explicitly tell it to `Edit` the file that ALREADY EXISTS at `<path>`,
  never to write a new one** (a fresh `operation: plan` would hit planner's same-day slug rule and add a
  `-2` suffix). Then launch `review-orchestrator` again with `round: 2`.
  ```
  run-id: <RUN>
  swarm-root: <absolute path to .swarm>
  operation: revise
  objective: <the owner's literal objective>
  context: edit (Edit) the file that ALREADY EXISTS at <absolute path to the plan>, don't write a new one.
  Incorporate these review findings: <the surviving lines, your summary>
  ```
- **`BLOCKED review KO after 2 rounds: …`** (or any finding you judge only the owner can resolve — never
  invent an answer): your final verdict is `BLOCKED <the specific question, in ≤20 words>`. Do NOT close
  the arbitration: the plan's `**Grill:** pending` line stays, so a future run on the same objective
  detects the plan isn't finished and resumes the cycle.

## Closing: mark the plan as arbitrated (your LAST action before `DONE`)

ONLY on the full path (you launched leaves, `planner` and the panel for real in this turn) — NEVER on the
idempotency shortcut (that plan already said `**Grill:** arbitrated`; it relaunches no one).

Only if your verdict is going to be `DONE` (never `BLOCKED`): once the panel returned `OK`, relaunch
`planner` with `operation: revise` to mark the plan — ALWAYS necessary: you have no `Write`/`Edit`, and
`**Grill:** pending` → `**Grill:** arbitrated <date>` is a file `Edit`. P2/P3 you decided to revise fold
into this SAME call. The mark never goes into the round-1 fix call: it is written only after the panel
says `OK`. **In total `planner` is relaunched at most TWICE per run** (one fix after a round-1 `KO`, one
closing mark) and the panel runs at most twice — no cycle is possible.
```
run-id: <RUN>
swarm-root: <absolute path to .swarm>
operation: revise
objective: <the owner's literal objective>
context: edit (Edit) the file that ALREADY EXISTS at <absolute path to the plan>, don't write a new one.
[Incorporate these P2/P3 findings: <your literal summary>, if any.]
As the LAST Edit of this call: change the line "**Grill:** pending" to "**Grill:** arbitrated
<today's ISO date>" — the arbitration is closed, this plan is ready for human review.
```
Wait for its `DONE` before your own verdict. If `planner` returns `BLOCKED` on this closing call (e.g. it
can't find the line), your verdict is `KO planner BLOCKED: <reason>`, not `DONE` with the mark unconfirmed.
