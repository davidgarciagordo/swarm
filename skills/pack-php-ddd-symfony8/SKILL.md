---
name: pack-php-ddd-symfony8
description: Stack pack for PHP + DDD + Symfony 8 repositories — detection marker, canonical tool commands, layering and naming conventions, untouchable boundaries, and in-use precedents. Read by swarm leaves when .swarm/context-pack.md declares stack php-ddd-symfony8.
---

# pack-php-ddd-symfony8

First stack pack of the `swarm` plugin. **It's not invoked: it's READ.** The
domain orchestrator resolves this directory's absolute path and passes it as a header line
`pack: <path>` in the leaf's prompt; the leaf does a `Read` of the files it needs
(frontmatter is never mutated at runtime, it's never preloaded as a skill).

## Detection

| marker | exact condition | result |
|---|---|---|
| `composer.json` | exists at the repo root **and** contains a reference to `symfony/` ANYWHERE in the file (not only inside `require`) | `stack: php-ddd-symfony8` |

This is exactly what `scripts/mem-scan.sh` already implements (a `grep -q "symfony/"` over the
whole file, not scoped to any section) and what `memory-builder` writes as the `stack:` line in
`.swarm/context-pack.md`. Without that marker, the stack is `generic` and no leaf
receives the `pack:` line — each falls back to its documented generic mode.

## What it contains

| file | for whom | content |
|---|---|---|
| `commands.md` | `quality-fixer`, `test-writer`, `implementer`, `migration-engineer`, `vulnerability-scanner`, `dependency-auditor` | canonical form of each deterministic command, with its detection condition and its executor |
| `conventions.md` | `implementer`, `test-writer`, `quality-fixer`, `data-model-auditor`, `doc-writer`, `vulnerability-scanner` | layers, directory layout, naming, style, expected PHP extensions |
| `boundaries.md` | `implementer`, `test-writer`, `quality-fixer`, `migration-engineer` (write), `data-model-auditor`, `vulnerability-scanner` (read-only) | what is NEVER touched |
| `precedents.md` | `doc-writer` | patterns already in use, reused before introducing a new one |
| `requirements.json` | `requirements-orchestrator` → `env-checker` | OS/project/library requirements this stack adds to the plugin's own |

**Two distinct consumption patterns** (don't confuse them): `data-model-auditor`,
`vulnerability-scanner`, `dependency-auditor`, `quality-fixer`, `test-writer`, `implementer`,
`migration-engineer`, `doc-writer` receive the pack's already-resolved path as the `pack:` line of
their own launch header (the domain orchestrator injects it) and do a direct `Read` of
the files they need. `pattern-advisor`/`domain-modeler` receive NO `pack:` line at all —
they only honor the `stack:` already declared in `.swarm/context-pack.md`, without
resolving or reading any pack file directly.

## Precedence rule

What this pack says WINS over the leaf's generic knowledge, and its `requirements.json`
entries win over the equivalent ones in the plugin's `requirements.json` (same identity key →
the pack wins). Whatever the pack does NOT cover, the leaf resolves with its
own generic judgment — an incomplete pack never blocks, it just stops contributing.
