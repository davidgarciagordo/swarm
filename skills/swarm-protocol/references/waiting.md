# swarm-protocol · WAITING
On demand from skills/swarm-protocol/SKILL.md — trigger: you launched `background: true` children and must end a turn before they report.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 4.5 `WAITING <n>` — not a verdict (only agents with background children)

An agent that launched `background: true` children and must end a turn BEFORE they report does NOT emit a
verdict; it ends the turn with exactly:

```
WAITING <n>
pending: <child-1>, <child-2>
```

- `n` ≥ 1 and `pending:` names exactly `n` distinct children (their role names, protocol §2bis).
- `hooks/validate-output.py` accepts it silently and counts it per agent instance and run
  (`run/<run>/waiting/`); a real verdict from that instance resets the count. At most 6 WAITINGs per
  instance: the 7th is rejected ("emit a verdict with what you have"). If the counter cannot be stored
  (no writable `.swarm/`), WAITING is rejected — emit a verdict instead.
- Whoever receives `WAITING <n>` from a child treats it as "not done yet": never as `DONE`/`OK`, never as
  a reason to relaunch the child or to start the next phase. Wait for its later verdict.
- A leaf (no children) never emits `WAITING`.
