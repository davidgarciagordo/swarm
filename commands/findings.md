---
description: Filtered query of the swarm's findings — by agent or by tag, open-only by default.
argument-hint: [agent|TAG] [--all]
allowed-tools: Bash, Read
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/swarm-findings.sh` passing it the user's argument, and
report its output as-is — don't reformat or summarize it.

The argument is at most **one** filter (agent name or TAG) plus the optional `--all` flag. The
script itself rejects any filter that doesn't match `[A-Za-z0-9_-]+` and exits with `exit 64`
without touching anything: don't try to "fix" a weird filter or build a variant of the command —
pass it quoted and let the script decide.

On the normal path it launches no subagent and consumes no model turn (spec §11 and
principle 4). Based on the exit code:

- **0** — its output is the result; report it as-is and stop.
- **1** (no `.swarm/`) and **64** (invalid filter) — show its stderr line as-is and
  stop. Both are correct responses from the script to a situation it resolves itself; **they are
  not the fallback trigger** and don't justify even one extra read.
- **any other code (2, 127, a traceback…)** — and ONLY then, degraded path: there are
  entries the script can't classify (`- [` lines missing the `[key:agent|TAG|…]` header,
  typically a hand-edited `findings/*.md` or one written by a different version) or the script
  couldn't even start. Do this, and nothing more:
  1. Show first the literal line
     `- warn: degraded mode — swarm-findings.sh failed (exit <code>)`, followed by whatever the
     script did manage to print.
  2. Read with `Read` **at most three** files from `.swarm/findings/` — if the user passed a
     filter, the one matching its name first.
  3. List the entries **literally, without reinterpreting them** (≤8 lines), and say which ones
     lack metadata and therefore can't be filtered by agent or tag.
  4. **Don't edit any findings file, don't "normalize" any entry, don't rerun the script, and
     don't launch any subagent.**

User argument:

$ARGUMENTS
