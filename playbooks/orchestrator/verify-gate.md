# orchestrator · verify gate (non-OK answers)
On demand from agents/orchestrator.md — trigger: a `verifier-<domain-tag>` answer is anything other than a clean `OK`.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 4 Verifier non-OK branches

- **`KO <reason>`** (1st attempt): `SendMessage(to: "<domain name>", "verify KO: <reason> — fix it and return your
  verdict again")` — the domain is still alive/resumable (protocol §2bis); its response reaches you as a message in a
  later turn.
  - **The response is a normal corrected verdict** (`OK`/`DONE` or another GREEN closing line equivalent to what you
    had): register again (same `--agent verifier-<domain-tag>`):
    ```bash
    "<plugin-root>/scripts/mem-manifest.sh" register --run <run-id> --agent verifier-<domain-tag> --domain verify --area "." --owner orchestrator
    ```
    and relaunch a SECOND time with the corrected verdict — a new instance under the same name, nothing carried over
    (the verifier is purely read-only):
    ```
    Agent(subagent_type: "swarm:verifier", name: "verifier-<domain-tag>", prompt:
    "run-id: <run-id>
    swarm-root: <absolute path of .swarm>
    operation: verify
    domain: <name of the domain orchestrator that just closed>
    verdict: <the full literal corrected verdict>")
    ```
  - **The response is a well-formed `BLOCKED <reason>`** (e.g. the domain exhausted its turn budget while correcting —
    `hooks/validate-output.py` turns `turns_k >= turns_max` into a maxTurns `systemMessage`): do NOT relaunch
    `swarm:verifier` (nothing corrected to reverify). Propagate that `BLOCKED <reason>` LITERALLY as the closing line,
    then normal `curate`.
  - **The response is NOT a well-formed corrected verdict at all** (empty, truncated, parses neither as a closing line
    nor as a literal `BLOCKED <reason>` — `hooks/validate-output.py`'s separate two-strike for malformed stops lets a
    SECOND malformed stop with the same reason through via a `systemMessage`, so the turn can end with anything): do
    NOT relaunch `swarm:verifier`; SYNTHESIZE the closing line
    `- run closed: BLOCKED verification failed for <domain>: the domain did not return a valid corrected verdict after the verifier's KO`
    and continue with normal `curate`. **"Propagate literal" (previous branch) only applies when a well-formed
    `BLOCKED <reason>` actually exists to copy — never invent a `BLOCKED <reason>` the domain never wrote.**
- **The response from `swarm:verifier` to EITHER of its two launches (the first, or the relaunch after the domain's
  correction) is neither a clean `OK` nor a clean `KO <reason>`** (e.g. `verifier-<domain-tag>` closes `BLOCKED` after
  exhausting its 10 turns — normal usage ~3-4 — or its text parses as neither form despite the hook's double attempt):
  a verification FAILURE, NEVER an implicit `OK`, on either launch. This branch is DIFFERENT from the ones above: there
  the DOMAIN fails to answer after a `KO`; here `verifier` ITSELF didn't complete its check — nothing to fix in the
  domain, so do NOT relaunch `swarm:verifier` for this reason and don't apply the `KO` two-strike (that one is about the
  content of a REAL corrected verdict). Close directly:
  `- run closed: BLOCKED verification failed for <domain>: verifier did not complete (<what it returned, summarized>)`
  and continue with normal `curate`.
- **`KO` the second time** (same reason or not, after a REAL corrected verdict that went through the relaunched
  `swarm:verifier` AND that launch completed with its own clean `KO <reason>` — otherwise it's the branch above):
  two-strike, same as `hooks/validate-output.py` — don't try to fix anything; the closing line becomes
  `- run closed: BLOCKED verification failed for <domain>: <verifier's reason>` and you continue with normal `curate`
  (the run closes `BLOCKED`, never a false green).

**Known limitation**: the domain-qualified `name:` does NOT separate `hooks/validate-output.py`'s retry counter — its
`retry_key` is `agent_type.split(':')[-1]` (always `verifier`) plus the hash of the rejection reason, so two different
`verifier-<domain-tag>` instances in the same run share a counter for a malformed `SubagentStop` with the same reason.
