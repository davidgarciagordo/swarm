# design-orchestrator · light (the plan is the deliverable)
On demand from agents/design-orchestrator.md — trigger: WHEN your header carries `tier: light`.

The owner asked for a written plan, not a build (root sizing.md). Give the minimum that yields a judged plan;
everything not listed here stays as in the core file (startup, idempotency, registering, model tiers, verdict).

1. **No design leaves.** Skip `pattern-advisor` and `domain-modeler`. Launch `planner` (`operation: plan`) directly
   with the literal objective; `context:` = `.swarm/decisions.md` plus any `findings/research-analyst.md` of this run.
2. **ONE panel round.** The core file's panel header with `tier: light` and `round: 1`.
3. Panel `OK` ⇒ close exactly as on the full path.
4. Panel `KO` ⇒ `planner` `operation: revise` ONCE (escalated tier) with the surviving P1 lines, then stop: no second
   panel. Verdict `KO score=<n> revised once, not re-judged: <worst finding>` plus `- grill: …`. A second round
   costs as much as the first and is the owner's call, not yours.
5. Panel `BLOCKED …` ⇒ propagate it as on the full path.
