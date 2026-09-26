# memory-orchestrator · claude-mem mirror
On demand from agents/memory-orchestrator.md — trigger: `policy.read` or `policy.write` in `.swarm/memory.json` includes `claude-mem`.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

`claude-mem` is `required: false`: every rule below is **strict best-effort** — if the tool fails, doesn't
exist or is slow, DON'T retry and DON'T fail/`KO`/`BLOCKED` the operation: add ONE warning line and continue
with `files`.

## query

If `policy.read` includes `claude-mem`, ALSO try `mcp__plugin_claude-mem_mcp-search__memory_search` (or
`observation_search`) with the same text. Merge both sources, each line citing its source. On failure:
```bash
"<plugin-root>/scripts/mem-manifest.sh" summary --run "<run>" --line "warn: claude-mem unavailable, query served by files only"
```

## write

If `policy.write` includes `claude-mem`, also replicate the fact with
`mcp__plugin_claude-mem_mcp-search__observation_add` (or `memory_add`). A failure there is a warning line,
never a `BLOCKED`.

## build hints

If `policy.read` includes `claude-mem` and the tool responded, add to the `memory-builder` spawn prompt up
to 5 `hint: <historical observation>` lines pulled from `mcp__plugin_claude-mem_mcp-search__get_observations`
/ `memory_search`. They are the builder's only path to the historical backend (it has no MCP tools) and are
optional: tool fails ⇒ launch the `build` without hints.

## curate — historical seal (mandatory)

As soon as you have the curator's `DONE`, YOU write the historical observation: ONE call to
`mcp__plugin_claude-mem_mcp-search__observation_add` with a one- or two-sentence summary of the run just
closed: `run-id` (or `adhoc`), tier/domain if it was in your prompt, and what the curator curated per its
evidence line (findings resolved/pruned, run gc, MEMORY.md trimming). On failure:
```bash
"<plugin-root>/scripts/mem-manifest.sh" summary --run "<run>" --line "warn: claude-mem unavailable, run closed without observation_add"
```
The verdict for `curate` is the curator's `DONE`, whether or not `observation_add` succeeds.
