# swarm-protocol · authoring agents
On demand from skills/swarm-protocol/SKILL.md — trigger: you are creating or editing a file under `agents/` or `skills/` of this plugin.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## 7. Mandatory frontmatter

Every agent in this plugin declares, without exception: `name`, `description` (a "Use when…" phrase that
triggers proactive use), `model: inherit`, `tier: judgement|standard|mechanical` (protocol §7bis),
`tools`, `maxTurns`, `memory: project`, `skills: [swarm-protocol]`. No agent or skill file ever names a
concrete model. Never declare `hooks`, `mcpServers` or `permissionMode` in the frontmatter — they're
ignored for plugin subagents and only confuse whoever reads the file.

## Core vs on-demand files

- Budgets: leaf agent ≤80 lines, domain orchestrator ≤150, root orchestrator ≤250, `SKILL.md` ≤120,
  each playbook/reference ≤200.
- A block that only matters in some situation moves to `playbooks/<agent>/<topic>.md` (agent-specific)
  or `skills/swarm-protocol/references/<topic>.md` (protocol). The core keeps ONE trigger line:
  `WHEN <observable condition> → Read <var>/playbooks/<agent>/<file>.md (§ids) BEFORE <action>`, where `<var>`
  is the variable `CLAUDE_PLUGIN_ROOT` written in `${…}` form.
- Core files write that `${…}` variable form (substituted to an absolute path when the agent or preloaded
  skill loads). On-demand files are returned RAW by `Read`: they never contain that variable and write
  `<plugin-root>` instead. The Bash environment has no such variable either.
- Moved sections keep their heading id (`### 4.1 …`) so existing `§` citations still resolve.
