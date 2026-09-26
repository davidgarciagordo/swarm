# implementation-orchestrator · review gate (sequence step 6)
On demand from agents/implementation-orchestrator.md — trigger: `quality-fixer` returned `OK` (step 5), before launching `review-orchestrator`.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 6. `review-orchestrator` — gate BEFORE merging, never after

The pre-merge review is the review panel (`<plugin-root>/skills/swarm-protocol/judgement.md`;
`reviewer` is only a thin alias of it — its checks are covered by the panel's diff lenses). Register
`review-orchestrator` in the manifest (same `register` command as the other children), resolve tier
`judgement`, then launch it with this literal header:
```
run-id: <run>
swarm-root: <absolute path to .swarm>
operation: review
artifact-type: diff
artifact: <the same absolute path from sequence step 5 (quality-fixer)>
objective: <the plan's **Objective:** line, verbatim> — phase <the chosen phase>
tier: <your own tier: header, or full if absent>
round: 1
stage: implementation-phase-<the chosen phase number>
producer-model: <the model id you passed to implementer, or inherit>
base: <the SHA you noted in step 1>
branch: worktree-agent-<agentId from step 2>
plan: <absolute path to the plan>
```
Its verdict:
- **`OK`** (score ≥ 7): go to "## Merge". Surviving P2/P3 lines never block the merge; copy them to
  your output.
- **`KO score=<n> …`** (round 1): resume `implementer` with `SendMessage(to: "implementer")` — SAME
  `agentId`, same worktree, `operation: implement-fix` and the surviving findings in `context:` —
  then repeat step 5 and this step with `round: 2`. A resume keeps the worktree but cannot change the
  model: the tier escalation of judgement.md §7 does not apply to this retry (a fresh spawn would
  lose the worktree). **Maximum 2 review rounds**, never a third.
- **`BLOCKED review KO after 2 rounds: …`**: never merge. Clean up the worktree ("## Worktree
  cleanup") and your final verdict is `BLOCKED <concrete finding>` without merging anything — the root
  escalates it to the owner. No "risk parked" merge of an upheld P1.
- `review-orchestrator` fails without a usable verdict: clean up the worktree and return
  `KO review-orchestrator: <its literal verdict>`.
