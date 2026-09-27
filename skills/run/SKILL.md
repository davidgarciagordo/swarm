---
name: run
description: "Run a goal through the swarm end to end. Use when the user wants work done by the swarm."
argument-hint: "<goal>"
allowed-tools: Agent, Read, Grep, Glob, Edit, Write, Bash, SendMessage, AskUserQuestion
---

**Native first.** Before launching anything, size the goal (same rule as `agents/orchestrator.md`
§1.1). When there is no `--tier=` flag and the goal is (a) a question, explanation or "analysis
only / don't modify" request answerable by reading the repo, or (b) a small reversible edit (1-3
files, the decision already made), do it YOURSELF with `Read`/`Grep`/`Glob` (and `Edit` for b):
no subagent, no `/swarm:init`, no `.swarm/`, and for (a) no write to any file. Start the answer
with `- path: direct · <one-line reason>` and end it with `- ran: none (native)`. If Bash is denied,
read with `Read`/`Grep`/`Glob` and never retry the denied command.

Otherwise invoke the `Agent` tool with `subagent_type: swarm:orchestrator`, `name: "orchestrator"`
(the owner relay addresses `SendMessage(to: "orchestrator")`, protocol §2ter/§2bis) and `prompt` set
to the user's text verbatim, even when `$ARGUMENTS` is empty or whitespace. On that path don't
answer or ask for clarification yourself: the `orchestrator` validates the goal (including the
empty-goal guard), extracts the `--tier=` flag if present and returns its own verdict.

**Proportional by design.** The `orchestrator` pulls a swarm component (one audit lens, discovery,
design, the review panel on a plan…) only when that component's value beats its cost, logs each
spawn with its reason, and lists what ran and what was skipped. No flag is needed;
`--tier=direct|light|full` is an optional override (`direct` = native only, `light` = one focused
component, `full` = the whole pipeline for a multi-component build) and always goes to the
`orchestrator`.

If the user's text forbids questions ("no questions", unattended), pass it anyway: the
`orchestrator` takes the recommended option wherever it would ask and lists each as `ASSUMED`
(§13.4). An artifact someone will act on (a plan, a diff before merge, an audit report) gets an
independent verdict from the review panel before the run closes green; a native answer does not.

User argument:

$ARGUMENTS
