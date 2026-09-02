# swarm

Claude Code plugin. Single-responsibility agent swarm for the software development lifecycle — analysis, design, implementation, delivery — optimized for quality per token. Full design in `docs/superpowers/specs/2026-09-01-swarm-design.md`. **Built so far: phases 1, 1b and 2** — memory subsystem, root orchestrator, requirements domain and discovery domain (questions batch presented to the owner via `AskUserQuestion`).

## Install

No marketplace listing yet — local dev only:

```bash
claude --plugin-dir /path/to/multiagents
```

## Commands

- `/swarm:init` — creates `.swarm/` in the target repo, health-gated on the `files` backend.
- `/swarm:run <goal> [--tier=direct|light|full]` — launches the root orchestrator.
- `/swarm:doctor` — checks the repo's environment requirements against `requirements.json`.

## How it works

### Architecture — what exists vs what's planned

```mermaid
flowchart TD
    O["orchestrator (root · opus)"]
    MO["memory-orchestrator (haiku)"]
    MB["memory-builder (sonnet)"]
    MC["memory-curator (haiku)"]
    RO["requirements-orchestrator (haiku)"]
    EC["env-checker (haiku)"]
    DO["discovery-orchestrator (sonnet)"]
    VC["value-critic (opus)"]
    RA["research-analyst (sonnet)"]
    OG["options-generator (opus)"]
    FS["feasibility-spiker (sonnet)"]

    O --> MO
    MO --> MB
    MO --> MC
    O --> DO
    DO --> VC
    DO --> RA
    DO --> OG
    DO --> FS
    RO --> EC

    subgraph planned["planned, not built (spec §15, phases 3-6)"]
        direction TB
        AO["analysis-orchestrator"]
        DGO["design-orchestrator"]
        IO["implementation-orchestrator"]
        DLO["delivery-orchestrator"]
    end

    O -.-> planned

    classDef planned fill:#eee,stroke:#999,color:#888,stroke-dasharray: 5 5;
    class AO,DGO,IO,DLO planned
    class planned planned
```

The root `orchestrator` (opus) classifies the run tier and talks to two domains today: `memory-orchestrator`, which owns `memory-builder` (builds/refreshes the context-pack) and `memory-curator` (compacts findings, GC); and `discovery-orchestrator`, which owns the four discovery leaves and returns ONE batch of questions the root presents with `AskUserQuestion`. `requirements-orchestrator` (with `env-checker`) is a third domain, invoked by `/swarm:doctor` rather than inside a run. The remaining domains — analysis, design, implementation, delivery — are spec'd but not implemented (see status below).

### `/swarm:run` flow

```mermaid
sequenceDiagram
    actor User
    participant O as orchestrator
    participant MO as memory-orchestrator
    participant MB as memory-builder
    participant DO as discovery-orchestrator

    User->>O: /swarm:run "<goal>" [--tier]
    O->>O: classify tier (direct / light / full)
    alt tier = direct
        O-->>User: OK (no run opened)
    else tier = light or full
        O->>O: open run (run-id, .swarm/run/<id>/)
        O->>MO: spawn (run-id, swarm-root, operation: build)
        MO->>MO: check staleness (tree-hash)
        alt pack stale or missing
            MO->>MB: build/refresh context-pack.md + index.md
            MB-->>MO: DONE
        else pack fresh
            MO-->>MO: OK (skip build)
        end
        MO-->>O: OK / DONE
        alt product goal, not already closed in decisions.md
            O->>DO: spawn (run-id, swarm-root, operation: discover, tier, objective)
            DO->>DO: 4 leaves in ONE batch (value, research, options, feasibility)
            DO-->>O: DONE + up to 4 "- Q" lines (one batch)
            O->>O: pre-flight each "- Q" (2-4 options, header <= 12 chars)
            O->>User: AskUserQuestion (ONE call, all questions)
            alt owner answers
                User-->>O: chosen options / free text
                O->>MO: write decision (ONE call: objective + all answers)
            else owner cancels the dialog
                O->>MO: write decision (objective + [pendiente] batch unanswered)
            end
        else bugfix / refactor / docs, or objective already closed
            O->>O: skip discovery (reported as "- discovery omitido: ...")
        end
        O->>MO: curate (close the run)
        O-->>User: DONE\nevidence: files=N cmds=M turns=k/max
    end
```

`direct` never opens a run and never touches memory — the root answers itself. `light`/`full` open a run and always check the pack before doing anything else; the pack is only rebuilt when stale (tree-state hash), never unconditionally.

Once the pack is ready, a **product** goal (new feature, new product, user-visible behavior change) goes through discovery before any design: the root spawns `discovery-orchestrator`, which runs its four leaves in a single batch and returns **one** batch of up to four questions. The root validates each question, presents them all in **one** `AskUserQuestion` call — so this is the one point where `/swarm:run` becomes interactive and waits for you — and records every answer as a **single** decision line in `.swarm/decisions.md`, prefixed with the literal `objective:` so a later run over the same goal detects that discovery already ran instead of asking again. If you dismiss the dialog, the batch is still recorded, marked `[pendiente]`. Discovery is skipped for bugfixes, refactors, docs, tests and infrastructure work, and for an objective `decisions.md` already closed; the skip is always reported in the output.

### Memory write / mailbox

```mermaid
sequenceDiagram
    participant L as leaf agent (e.g. memory-builder)
    participant MO as memory-orchestrator
    participant FS as mem-files.sh (.swarm/, lock)
    participant B as another agent's mailbox

    L->>MO: SendMessage(write finding: file:line, tag, fix)
    MO->>FS: write finding (acquire lock)
    FS-->>FS: dedup by agent+tag+file:line
    FS-->>MO: written / dup
    MO->>FS: write mailbox mirror (--to <agent>)
    FS-->>B: run/<id>/mailbox/<agent>.md
    MO-->>L: OK (ack)
    Note over B: a late-started agent reads its mailbox<br/>on startup, before acting
```

No agent scans the repo or `.swarm/` twice, and no agent writes `.swarm/` directly — every write (finding, decision, mailbox) goes through the single `memory-orchestrator` instance for the run, which serializes writes with a lock. Every `SendMessage` between leaves is also mirrored to the recipient's mailbox, so a sibling launched later in the run — or one addressed before it existed — still reads what it missed.

## Current status — what's built vs planned

Phases from spec §15:

1. **Core (built).** `orchestrator`, memory subsystem (`memory-orchestrator` + `memory-builder` + `memory-curator`, `files`/`claude-mem` backends), `swarm-protocol` skill, hooks (evidence-contract validation + bash allowlist), `/swarm:init`, smoke tests 1-8.
1b. **Requirements (built).** `requirements-orchestrator`, `env-checker`, `req-check.sh`, `requirements.json`, `/swarm:doctor`.
2. **Discovery (built).** `discovery-orchestrator` + `value-critic`, `research-analyst`, `options-generator`, `feasibility-spiker`; the root presents ONE batch of questions via `AskUserQuestion` and records each answer in `.swarm/decisions.md`.
3. **Analysis (planned).** `analysis-orchestrator` + 6 read-only lenses.
4. **Design (planned).** `design-orchestrator`, `planner`, `pattern-advisor`, `domain-modeler`, grill×3 integration.
5. **Implementation (planned).** 7 agents + `dependency-auditor`/`dependency-installer` + the `php-ddd-symfony8` stack pack.
6. **Delivery (planned).** 3 agents + `/swarm:status`, `/swarm:findings`.

## Naming convention

Every spawned agent is launched **named after its role** — the basename of its type, no suffixes or variants (`memory-orchestrator`, and in future phases `security-auditor`, `analysis-orchestrator`, …). This is what lets peer agents `SendMessage` each other by name without discovering it first, and lets the owner address a specific agent directly — "tell `memory-builder` when it's done" — without the caller having to look up who that is. `memory-orchestrator` is the one case that's mandatory today: a single named instance per run (spec §4.5).

## Tests

```bash
bash tests/run.sh
```

## License

MIT © David García Gordo
