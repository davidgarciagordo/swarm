---
description: "/swarm:run — the swarm's single entry point: describe what you want in natural language, no prior steps needed."
argument-hint: "<goal>"
allowed-tools: Agent, Read, Bash, SendMessage, AskUserQuestion
---

Invoke the `Agent` tool with `subagent_type: swarm:orchestrator`, `name: "orchestrator"` (the
owner relay addresses `SendMessage(to: "orchestrator")`, protocol §2ter/§2bis) and `prompt` set to
the user's text verbatim, even when `$ARGUMENTS` is empty or whitespace. Don't answer or ask for
clarification yourself: the `orchestrator` validates the goal (including the empty-goal guard) and
returns its own verdict. Pass it the full argument without reinterpreting it — the `orchestrator`
itself extracts the `--tier=` flag if present and classifies the rest as the goal.

If the user's text forbids questions ("no questions", "analysis only, don't ask", unattended), pass
it anyway: the `orchestrator` still runs every phase (discovery, analysis, design) and takes the
recommended option wherever it would ask, recording each as `ASSUMED` and listing them in its final
report (`agents/orchestrator.md` §13.4). Artifacts someone will act on (a design plan, a diff
before merge, an analysis report) get an independent verdict from the review panel
(`review-orchestrator`, `skills/swarm-protocol/judgement.md`) before the run closes green.
The one exception is `--tier=direct` (or a `direct` classification): the root answers a trivial,
one-file objective itself without opening a run, so no artifact is persisted and no panel runs.
`light` never launches design; an implementation phase and an analysis report are still reviewed.

User argument:

$ARGUMENTS
