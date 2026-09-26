# planner · revise
On demand from agents/planner.md — trigger: WHEN operation: revise, BEFORE your first Edit.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## Revision after review (only when design-orchestrator relaunches you)

With `operation: revise` a draft already exists (its path comes in your prompt) and `design-orchestrator`
summarizes which review findings are load-bearing. Use `Edit` on THAT same file — never create a new one
for a revision. Incorporate the `P1`s it summarizes (if any) phase by phase.

**Arbitration-closed marker (idempotency):** the `operation: revise` that `design-orchestrator` sends as
ITS LAST action before `DONE` — with findings to incorporate or none — carries in `context:` the explicit
instruction to change, as the last `Edit` of the call, the line `**Grill:** pending` to
`**Grill:** arbitrated <ISO date YYYY-MM-DD>` (today). That call may carry nothing else: then your only
change is that line. **Never** set `arbitrated` on your own initiative if the prompt doesn't explicitly ask
for it — only `design-orchestrator` knows whether the review was fully resolved or the run ends in
`BLOCKED <question>` (then the line stays `pending` on purpose, so a future run resumes the cycle). Close with the same evidence discipline as always.
