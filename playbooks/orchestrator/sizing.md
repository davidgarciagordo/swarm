# orchestrator · sizing (native first, swarm à la carte)
On demand from agents/orchestrator.md — trigger: WHEN the objective isn't done natively and you consider any spawn
(§1.1), BEFORE the first spawn or `swarm-init`.

## Value vs cost
Every spawn costs a fresh context (its own reads of the repo) plus, for the FIRST one, opening a run: `swarm-init` if
`.swarm/` is missing, `memory-orchestrator` + the context pack (§2). That fixed cost is paid once; count it before the
first component, not before each. Native work pays none of it. Pull a component only for what native work can't give:
an independent judgement, a deterministic scanner, parallel breadth, or a written artifact others will act on.

| need detected (objective + probe) | pull only | never pull for it |
|---|---|---|
| question / explanation / "how would you…" answerable by reading | nothing — answer natively | discovery, analysis, panel |
| small reversible edit (1-3 files, decision already made) | nothing — `/swarm:run` edits natively before launching you | design, implementation |
| one audit angle (auth/tenant diff, hot path, schema drift) | `analysis-orchestrator` with `lenses: <only those>` | the other lenses |
| broad audit explicitly asked ("audit everything") | `analysis-orchestrator` without `lenses:` (its own table) | discovery |
| an open product decision the owner must take | `discovery-orchestrator` | analysis |
| multi-component build, or a redesign with high blast radius (`tier: full`) | `design-orchestrator` (planner + grill) | analysis unless asked |
| implement an already-written plan (explicit request) | `implementation-orchestrator` (§10) | discovery, design |
| a written plan/strategy IS the deliverable, nothing is built in this run | `design-orchestrator` with `tier: light` (planner + ONE panel round) | discovery, analysis, writing the plan yourself |
| …and that plan needs facts the repo can't give (market, prices, external tools) | `discovery-orchestrator` first, for its research | discovery when the repo already answers it |
| a plan/report that ALREADY exists and someone will act on with high blast radius | the review panel on THAT artifact | a panel on a native answer |
| dependencies / publish | `requirements-orchestrator` / `delivery-orchestrator` | everything else |

**You never author the artifact.** A plan is written by `planner` (through `design-orchestrator`), never by you: the
root coordinates, and a deliverable written by the coordinator skips the producer tier and the panel's independence.
**Unattended runs** (questions forbidden, §13.4): discovery's questions would all be `ASSUMED`, so pull
`discovery-orchestrator` only for research the plan depends on, and say so in the spawn line.
Repo-wide context shared by several agents is what the memory pack is for; with ONE component the pack is still built
(the component reads it) — another reason one component beats three. The route tables (§5.1, §8.1) say WHICH domain an
objective belongs to; this table decides WHETHER it is worth pulling. A native answer never passes the panel.

## Escalation (one step at a time)
Native first. Add ONE component only when native provably can't finish, and say what is missing
(`- spawn analysis-orchestrator lenses: security-auditor: 40 controllers touch auth/, a grep sweep can't judge authorization`). Never jump straight to
the full pipeline; a second component needs its own reason line.

## Forced `--tier` vs a read-only objective
`--tier=light|full` on a read-only objective ("analysis only", "don't modify", a question) in a repo WITHOUT `.swarm/`:
never initialize. Answer natively and add `- skipped: <component> (read-only request, no .swarm/ — run /swarm:init
first to enable it)`. With `.swarm/` present the forced tier applies; writes go only to the gitignored `.swarm/`.

## Report
The final report lists every component considered: `- ran: <component> (<why>)` and `- skipped: <component> (<why>)`,
so the owner can audit the native/swarm split. A native-only answer lists `- ran: none (native)`.
