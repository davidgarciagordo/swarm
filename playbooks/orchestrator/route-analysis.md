# orchestrator · route analysis
On demand from agents/orchestrator.md — trigger: the route is analysis (§8.1).
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 8.2 Launch (sequential relative to memory)

Launch `analysis-orchestrator` **after** the `OK`/`DONE` from `memory-orchestrator` (`operation: build`, §2.2) — NOT in
the same batch: the pack must exist when its leaves start. Register it beforehand in the manifest, then launch:
```bash
"<plugin-root>/scripts/mem-manifest.sh" register --run <run-id> --agent analysis-orchestrator --domain analysis --area "." --owner orchestrator
```
```
Agent(subagent_type: "swarm:analysis-orchestrator", name: "analysis-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <absolute path of .swarm>
  operation: audit
  tier: <light|full>
  objective: <the owner's literal objective, without the --tier flag>
  lenses: <only the lenses sizing pulled — optional line, omit to let it choose>)
```

### 8.3 Forwarding the findings (no `AskUserQuestion` — nothing to ask)

`analysis-orchestrator` produces already-formatted findings (`TAG · file:line · problem → fix`, protocol §4) which you
forward DIRECTLY as your own output lines — no `AskUserQuestion`, no reformatting, no `mem-files.sh` (each leaf already
persisted its detail). Copy its `- lenses: …`, `TAG · file:line · …`, `- N additional findings …` and
`- <leaf> BLOCKED: …` lines as-is (§4 forwarding rule: no §5.0 in output). Its `BLOCKED …`/`KO …` is propagated
literally, and the closing `summary --line` goes through §5.0's sanitization (a leaf's reason can cite repo code with
backticks/`$(...)`); then `curate`, wait for `DONE`, return.

### 8.4 Close — summary lines (extends §4)

Before this close, a green analysis goes through `swarm:verifier` (§4) and then the review panel (§13.6); a panel
failure after two rounds closes `KO`, never green.
- analysis completed (`DONE`/`OK` with or without findings): `- run closed: DONE · analysis completed, <n> findings`
- propagated `BLOCKED`/`KO` from analysis: `- run closed: <literal verdict from analysis-orchestrator>`
- infra objective audited then designed (§8.1/§9.1 path 3):
  `- run closed: DONE · analysis completed, <n> findings; design completed, plan at <path>`

### 13.6 Review panel for the final verdict of analysis runs

After `analysis-orchestrator` closes `DONE`/`OK` and `swarm:verifier` confirms traceability (§4 — verifier checks that
claims trace to persisted findings; it never judges quality), send the report to the panel before closing. Register it
in the manifest first (`--agent review-orchestrator --domain review --owner orchestrator`), then:
```
Agent(subagent_type: "swarm:review-orchestrator", name: "review-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <absolute path of .swarm>
  operation: review
  artifact-type: report
  artifact: <absolute paths of .swarm/findings/<lens>.md for every lens in the `- lenses:` line>
  objective: <the owner's literal objective>
  tier: <light|full>
  round: 1
  stage: analysis
  producer-model: <the id you resolved for the analysis leaves' tier, or inherit>)
```
Policy: `<plugin-root>/skills/swarm-protocol/judgement.md`.
- Panel `OK`: close with §8.4, adding `- review: OK score=<n>` to your output.
- Panel `KO` on round 1: relaunch `analysis-orchestrator` ONCE with an extra header line
  `review-findings: <the surviving finding lines, sanitized §5.0, joined by " | ">` and the escalated tier (§13.2), then
  call the panel again with `round: 2`.
- Panel `BLOCKED review KO after 2 rounds: …`: do NOT close green. Your verdict is
  `KO review failed twice: <worst finding>` with the surviving findings, so the owner decides.

### 8.5 Output example

Findings forwarded directly as your own, same vocabulary as `analysis-orchestrator`'s "## Output":
```
DONE
evidence: files=2 cmds=6 turns=11/30
- lenses: security-auditor, vulnerability-scanner, reason: objective matched "security"
SEC · src/Controller/InvoiceController.php:14 · CRITICAL: tenant query with no filter → add WHERE tenant_id
SEC · src/Controller/InvoiceController.php:22 · mutating endpoint with no role check → validate permission server-side
VULN · config/services.php:3 · possible secret in cleartext (api_key= pattern) → move to environment variable
```
