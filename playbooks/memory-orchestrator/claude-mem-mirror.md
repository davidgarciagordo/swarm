# memory-orchestrator · claude-mem mirror
On demand from agents/memory-orchestrator.md — trigger: `policy.read` in `.swarm/memory.json` includes `claude-mem`.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

`claude-mem` is `required: false` and READ-ONLY for you: it records sessions through its own hooks and exposes no
write tool, so there is nothing to mirror on `write` or `curate`. Every rule below is **strict best-effort** — if the
tool fails, doesn't exist or is slow, DON'T retry and DON'T fail/`KO`/`BLOCKED` the operation: add ONE warning line
and continue with `files`.

## query

If `policy.read` includes `claude-mem`, ALSO try `mcp__plugin_claude-mem_mcp-search__search` with the same text. Merge
both sources, each line citing its source. On failure:
```bash
"<plugin-root>/scripts/mem-manifest.sh" summary --run "<run>" --line "warn: claude-mem unavailable, query served by files only"
```

## build hints

If `policy.read` includes `claude-mem` and the tool responded, add to the `memory-builder` spawn prompt up to 5
`hint: <historical observation>` lines pulled from `mcp__plugin_claude-mem_mcp-search__search` (details with
`get_observations`). They are the builder's only path to the historical backend (it has no MCP tools) and are
optional: tool fails ⇒ launch the `build` without hints.

## A `.swarm/memory.json` whose `policy.write` still lists `claude-mem`

Written by an older `swarm-init`. Ignore that entry: write to `files` only, no warning.
