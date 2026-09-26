# orchestrator · route design
On demand from agents/orchestrator.md — trigger: the route includes design (§9.1).
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 9.2 Launch

Register it beforehand in the manifest, then launch (path 3 adds the line
`context: analysis findings in .swarm/findings/ for run <run-id>` after `objective:`):
```bash
"<plugin-root>/scripts/mem-manifest.sh" register --run <run-id> --agent design-orchestrator --domain design --area "." --owner orchestrator
```
```
Agent(subagent_type: "swarm:design-orchestrator", name: "design-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <absolute path of .swarm>
  operation: design
  tier: full
  objective: <the owner's literal objective, without the --tier flag>)
```

### 9.3 Forwarding the result (no `AskUserQuestion` — same as analysis, different reason)

`design-orchestrator` never produces questions: it produces a short synthesis (tag `PLAN`) pointing to the real plan
file. Forward its `PLAN · …` line and its `- grill: …` line (if present) as-is (§4 forwarding rule: no §5.0 in output).
Its `BLOCKED …`/`KO …` is propagated literally, and the closing `summary --line` goes through §5.0's sanitization
(design-orchestrator's reason can cite repo code with backticks/`$(...)`); then `curate`, wait for `DONE`, return.

### 9.4 Close — summary lines (extends §4)

- design completed (`DONE`), via product decisions OR via refactor/migration (§9.1 — both close the same way):
  `- run closed: DONE · design completed, plan at <path>`
- infra objective audited then designed (§9.1 path 3):
  `- run closed: DONE · analysis completed, <n> findings; design completed, plan at <path>`
- propagated `BLOCKED`/`KO` from design: `- run closed: <literal verdict from design-orchestrator>`
- Omissions never open their own `summary` call: pure bugfix/docs/tests/infra and refactor/migration in `tier: light`
  fold into §4's COMBINED line; design omitted because analysis ran instead (normal classification or precedence over
  refactor/migration) is covered by analysis's verdict (§8.4). On the refactor/migration path in `tier: full` design is
  never omitted.

### 9.5 Output examples

Design forwarded directly, same mechanism as analysis:
```
DONE
evidence: files=3 cmds=7 turns=15/30
PLAN · docs/superpowers/plans/2026-09-03-export-csv-invoices.md:1 · plan ready, 4 phases → review before phase 5
- grill: 1 P1 incorporated (export idempotency), 2 P2 noted as risk
```
Substantial refactor/migration in `tier: full` — discovery skipped, design runs with the literal objective:
```
DONE
evidence: files=3 cmds=6 turns=12/30
- discovery omitted: substantial refactor/migration objective, no product decision to ask about
PLAN · docs/superpowers/plans/2026-09-03-refactor-billing-solid.md:1 · plan ready, 5 phases → review before phase 5
- grill: 2 P1 incorporated (circular coupling, hot data migration), 1 P2 noted as risk
```
