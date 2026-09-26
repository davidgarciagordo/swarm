---
description: Initializes .swarm/ in this repo (memory, gitignore, health-gate for the backend files).
allowed-tools: Bash
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh` and report its output to the user as-is — don't
reformat or summarize it, it's already a plain-text summary. If the script exits with a code other
than 0, report that `/swarm:init` aborted and show why (the stderr line from the health check).

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh"
```
