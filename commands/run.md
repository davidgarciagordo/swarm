---
description: "/swarm:run — the swarm's single entry point: describe what you want in natural language, no prior steps needed."
argument-hint: "<goal>"
allowed-tools: Agent, Read, Bash, SendMessage, AskUserQuestion
---

ALWAYS invoke the `Agent` tool with `subagent_type: swarm:orchestrator`, `name: "orchestrator"`
(the owner relay addresses `SendMessage(to: "orchestrator")`, protocol §2ter; never anonymous,
§2bis) and `prompt` equal to
exactly what the user wrote, EXACTLY as written, no exceptions — even if `$ARGUMENTS` is empty or
just whitespace. Never answer yourself, never ask for clarification before invoking: the
`orchestrator` itself decides whether the goal is valid (including the empty-goal guard) and
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
