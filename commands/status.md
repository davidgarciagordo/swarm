---
description: Shows the swarm's status in this repo — current run, tier, registered agents, summary and open findings.
allowed-tools: Bash, Read
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/swarm-status.sh` and report its output to the user as-is — don't
reformat it, don't summarize it, and don't add interpretation: it's already a plain-text summary,
and any rewriting strips the user of the exact values (run-id, tier, counts) they asked to see.

`/swarm:status` takes no arguments: any text the user adds after the command is ignored. On the
normal path it **launches no subagent and consumes no model turn** — reading `.swarm/`
and formatting doesn't need judgment (spec §11 and principle 4: deterministic tool before model).

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/swarm-status.sh"
```

Based on the script's exit code:

- **0** — its output is the result. Report it as-is and **stop there**: no further tool calls.
- **1** — no `.swarm/` exists. Show its stderr line as-is (it says this is fixed with
  `/swarm:init`) and stop. **This is not a script failure**: it's the correct response.
- **any other code (2, 127, a traceback…)** — and ONLY then, degraded path: the script couldn't
  parse the data (a `run.json` truncated by an interrupted run, or written by another plugin
  version; `findings/*.md` entries missing the expected `[key:…]` header) or it couldn't even
  start. Do this, and nothing more:
  1. Show first the literal line
     `- warn: degraded mode — swarm-status.sh failed (exit <code>)`, followed by whatever output
     the script did manage to produce.
  2. Read **at most three** files, with `Read`, and only these: `.swarm/run/current`,
     `.swarm/run/<that id>/run.json` and `.swarm/run/<that id>/summary.md`.
  3. Summarize in **≤8 lines**: which run looks current, what can be read from it, and what
     cannot.
  4. **Don't rerun the script, don't "fix" it, don't touch any file under `.swarm/`, and don't
     launch any subagent.** A degraded result is ALWAYS presented as degraded; never fill in with
     assumptions the gap the script couldn't read.
