# swarm-protocol · model tiers
On demand from skills/swarm-protocol/SKILL.md — trigger: you are an orchestrator about to make your first `Agent` spawn of the run.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## 7bis. Model tiers (who runs on which model)

| tier | work |
|---|---|
| `judgement` | audit, grill/review lenses, judge, plan, design, arbitrate, orchestrate |
| `standard` | execute a closed plan, write tests/docs/code |
| `mechanical` | run scripts, format, curate memory, collect env facts |

Concrete model ids live ONLY in `<plugin-root>/models.json` (ordered candidates per tier + `escalation`).
A project file `<swarm-root>/models.json` with the same schema overrides it per tier — that is how a
non-Anthropic host maps tiers to its own ids. Resolution is deterministic, never a model's guess:

```bash
"<plugin-root>/scripts/model-resolve.sh" judgement --swarm-root "<swarm-root>"
"<plugin-root>/scripts/model-resolve.sh" --mark-unavailable "<model-id>" --swarm-root "<swarm-root>"
"<plugin-root>/scripts/model-resolve.sh" --escalate standard --swarm-root "<swarm-root>"
"<plugin-root>/scripts/model-resolve.sh" judgement --avoid "<producer-model-id>" --swarm-root "<swarm-root>"
```

Rules for every orchestrator that spawns a child:
1. **Resolve, then spawn.** Run `model-resolve.sh <child's tier>` and pass the printed id as the `Agent`
   tool's `model` parameter; when it prints `inherit`, OMIT the parameter.
2. **Missing model ⇒ mark and retry.** If the spawn fails because the model does not exist, run
   `--mark-unavailable <id>` and spawn again with the new resolution. Never guess an id.
3. **Veracity: judgement never goes down.** A tier only walks its own list; exhausted ⇒ `inherit` (the
   session model), never a weaker tier's candidate. The run tier (`light`) does not change this either.
4. **Escalate once on failed verification.** If a child's output fails verification (hook, review panel
   or judge), retry it ONCE on `--escalate <tier>` (judgement escalates to itself; a tier that resolves to
   the SAME model is skipped — a retry on the same model is no escalation).
5. **Judge independence.** Resolve the blind judge with `--avoid <id that produced the artifact>`; if no
   distinct candidate is available it prints `inherit` plus a stderr note, and `--avoid inherit` (producer
   model unknown) prints the plain resolution plus a note — record any note in your findings.
6. **Unavailable marks expire.** `--mark-unavailable` only writes inside an existing `.swarm/` and stamps
   the entry; it stops applying after 24h (`SWARM_MODEL_UNAVAILABLE_TTL`).
