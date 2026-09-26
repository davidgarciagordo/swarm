# swarm-protocol · worktree mode
On demand from skills/swarm-protocol/SKILL.md — trigger: your frontmatter has `isolation: worktree`, or your cwd is not the repo root.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## 3. Worktree mode (§9.3)
With `isolation: worktree` your launch prompt gives the ABSOLUTE path of the main repo's `.swarm/`: **read** it by that
path (never a worktree copy, never cwd-relative); **never write there directly** — every write (finding, decision,
mailbox) goes via `SendMessage` to `memory-orchestrator`. Scripts default to `$PWD/.swarm` (wrong in a worktree): prefix
reads with ONE `SWARM_ROOT=<abs>`, on ONE line, no `\` continuation (`export` is denied). `bash-guard` accepts the prefix
only for an EXISTING `.swarm` directory:
```bash
SWARM_ROOT=<swarm-root> "<plugin-root>/scripts/mem-files.sh" query "tenant" --scope findings
```
