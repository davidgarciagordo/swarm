# swarm-protocol · shell and guard
On demand from skills/swarm-protocol/SKILL.md — trigger: `hooks/bash-guard.py` denied a command you believe is allowed, or you need the reason behind the §3 prefix / §4.4 sanitization rules.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## §3 The `SWARM_ROOT=` prefix

All memory scripts read `SWARM_ROOT` from the environment and, if unset, fall back to `$PWD/.swarm` —
WRONG in a worktree. `hooks/bash-guard.py` recognizes ONE `SWARM_ROOT=<value>` prefix as transparent: it
trims it and validates the rest of the segment with the normal rules (so
`SWARM_ROOT=/abs/.swarm scripts/mem-files.sh health` passes, and `SWARM_ROOT=/abs/.swarm rm -rf /` is still
denied). The value must end in `.swarm`, contain no `..` and, when absolute, ALREADY exist — the header's
`swarm-root:` always does; any other value leaves `SWARM_ROOT=…` as argv[0] and the call is denied.
`export SWARM_ROOT=…` as a standalone command is NOT allowed. Write every command on ONE single line: `\`
and newlines are banned anywhere, so a line continuation denies the ENTIRE command.

## §4.4 Why third-party text is sanitized (and why characters are DELETED, not escaped)

`hooks/bash-guard.py` never interprets shell syntax, it refuses it: `$`, backtick, `\`, `;`, `{`, `}`, `<` and
newlines are banned ANYWHERE in the command, quoted or not; read-only roles (not in `file_writers`) also ban
`| & > ( )` anywhere. So a question as ordinary as "should we migrate the old parseCSV()?" with the identifier
in backticks, interpolated as-is into `--text`, gets the ENTIRE call denied and the write is silently lost —
fail-closed, but nothing durable is left, which is what the evidence contract exists to prevent. Escaping
does not help (`\` is itself banned); deleting the characters is the only form the guard accepts. With no
escapes left, `'...'`/`"..."` are literal spans that `shlex` and the real shell read identically.

Globs `* ? [ ]`, `#` and a word-leading `~` pass only inside quotes: write `"<plugin-root>/agents"` +
`grep -r`, never `.../agents/*.md`; a literal `[` in a regex is `[[]`, never `\[`. No `$(…)`: run
`git rev-parse --show-toplevel`, then `cd <printed path>`. No heredoc: `Write`/`Edit` the file instead.
