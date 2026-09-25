# Review panel & judgement policy

Owned by `agents/review-orchestrator.md`. Shared contract for every caller of the panel
(`design-orchestrator`, `implementation-orchestrator`, the root `orchestrator` for analysis
verdicts). Model tiers and `scripts/model-resolve.sh` are defined in `SKILL.md`; this file only
says how the panel uses them.

## 1. Why a panel

Measured on a real repo: the swarm was faster and cheaper than a plain workflow but scored 7.0 vs
8.5 on blind quality, and its errors were veracity errors (a `jq -S` proposed over an unfiltered
dump; a fact marked "unverified" that one command would have checked). Every stage that produces an
artifact someone will act on (a plan, a diff, a report) is therefore reviewed by independent,
single-objective lenses, filtered by a refuter, and scored by a blind judge. Veracity first, then
quality, cost, speed.

## 2. Launch header (caller → `review-orchestrator`)

```
run-id: <uuid|adhoc>
swarm-root: <absolute path of .swarm>
operation: review
artifact-type: plan|diff|report
artifact: <absolute path(s), comma-separated>
objective: <owner's literal objective>
tier: <light|full>            (optional, absent ⇒ full)
round: <1|2>                  (informative; the real round is `review-dedup.sh round`, §7)
stage: <design|implementation-phase-<n>|analysis>   (mandatory: missing ⇒ BLOCKED missing stage)
producer-model: <model id that produced the artifact>   (optional, used ONLY to pick the judge)
base: <sha>  branch: <branch>  (diff only: the range to review)
```

## 3. Lens selection (deterministic: `scripts/review-dedup.sh lenses`)

| tier / artifact | lenses |
|---|---|
| light (any type) | fact-checker, defect-hunter |
| full · plan | completeness-critic, defect-hunter, rules-auditor, operator, fact-checker, simplicity-critic |
| full · diff | defect-hunter, rules-auditor, fact-checker, completeness-critic |
| full · report | fact-checker, completeness-critic |

| lens (role) | agent file | TAG | one objective |
|---|---|---|---|
| completeness-critic | `completeness-critic` | `MISSING` | what is MISSING vs the objective / reference |
| defect-hunter | `grill-engineer` | `DEFECT` | what BREAKS: edge cases, concurrency, partial failures |
| rules-auditor | `grill-architect` | `RULES` | what VIOLATES repo rules/precedents (cites file:line) |
| operator | `grill-operator` | `OPERATOR` | misuse and friction at the point of use |
| fact-checker | `fact-checker` | `FACT` | re-verifies every load-bearing claim with the cheapest read-only check |
| simplicity-critic | `simplicity-critic` | `SIMPLER` | what is SUPERFLUOUS, cheaper alternative |

**working-methods interop.** If `claude plugin list` shows `working-methods` installed and enabled,
its `working-methods:grill-{engineer,architect,operator}` REPLACE defect-hunter, rules-auditor and
operator (`lenses --working-methods`). Never both families in one panel. Their lines come as
`Pn · where · problem → fix`: the orchestrator prefixes the lens TAG (`DEFECT · P1 · where · …`)
before dedup, which normalizes both forms.

**Every lens:** read-only, reads the shared context-pack (`<swarm-root>/context-pack.md`) instead of
re-scanning the repo, opens only what it must verify, returns terse findings.

## 4. Finding format and severity

`TAG · where · Pn problem → fix` — `where` is `file:line` whenever one exists (the artifact's own
line when the finding is about the artifact). `P1` = blocking (would make the artifact wrong or
unsafe to act on), `P2` = significant, `P3` = minor. A finding without `Pn` is treated as `P1`
by `review-dedup.sh` (checked by the refuter, never silently hidden). Mapping to the old reviewer
vocabulary: P1 = Critical, P2 = Important, P3 = Minor.

## 5. Flow

1. Launch the selected lenses in ONE batch (each spawn named after its agent, model resolved for
   tier `judgement`).
2. `review-dedup.sh dedup` over all lens lines: same TAG + same `where` + same problem text
   (case/space/punctuation-insensitive) = duplicate, the most severe copy is kept; a different
   problem at the same `file:line` is a different finding and is kept.
3. `review-dedup.sh dedup --blocking` → the P1 list. If non-empty, ONE `refuter` receives all of
   them and tries to refute each (verifying against the real artifact/repo). `REFUTED` findings are
   dropped and logged (the refuter persists each one as a `REFUTED` finding with its reason);
   `UPHELD` ones survive. The refuter never adds findings.
4. `blind-judge` receives ONLY: the artifact path(s), the owner's objective, the surviving
   findings (P1 upheld + P2/P3). Never the producer's name, model, reasoning, self-assessment,
   verdict, the lens names, or the refuted list. It re-verifies itself the 3 most load-bearing
   claims of the artifact and returns a score 0-10.
5. Record: `review-dedup.sh record …` appends one line to `<swarm-root>/judgements.jsonl`
   (`{run,stage,artifact_type,score,verdict,lenses,model}`, `model` = the judge's), always, OK or
   KO — it is the calibration log. `/swarm:status` shows its last scores; `swarm-init.sh`
   gitignores it (it is per-machine run data, like `run/`).

## 6. Scoring (judge)

- **KO iff score < 7.** Any upheld P1, or any load-bearing claim that failed the judge's own
  re-verification, caps the score at 6.
- 9-10: objective fully met, claims re-verified, no P1/P2. 7-8: met, only P2/P3 left.
- The hook's verdict line accepts `OK` alone and `KO <reason>`, so the judge writes
  `OK` / `KO score=<n> <worst problem>` on line 1 and ALWAYS `- score: <n>` on line 3.

## 7. Loop until dry (the caller owns the retry)

The round limit is enforced by a counter, never by the caller's `round:` header alone:
`review-orchestrator` runs `review-dedup.sh round --swarm-root <abs> --run <id> --stage <stage>
--artifact <artifact>` first (one counter per stage + artifact, under `mem-lock.sh`); past 2 it
returns `BLOCKED review KO after 2 rounds: round limit reached` without launching anything, so a
caller that forgets `round: 2` cannot loop. On `OK` it runs `review-dedup.sh reset` with the same
flags, so a later review of the same stage (another phase, a re-run after a failed verify) starts
at round 1. Round 2 must carry the same `stage:` and `artifact:` as round 1.

- Panel `OK` ⇒ the caller proceeds.
- Panel `KO` on `round: 1` ⇒ the caller re-runs ITS stage ONCE with the surviving findings as
  input, spawning the producer with the escalated tier (`model-resolve.sh --escalate <tier>`,
  judgement escalates to itself), then calls the panel again with `round: 2`.
  Exception: a worktree-bound producer (`implementer`) is RESUMED in place via `SendMessage` to
  keep its worktree, so its model cannot be escalated.
- Panel `KO` on `round: 2` ⇒ `review-orchestrator` returns `BLOCKED review KO after 2 rounds: …`
  and the caller escalates to the owner. Never a third round, never a silent merge/close.
- A lens/refuter/judge whose own output fails the hook or a spawn failure for a missing model:
  mark the model unavailable (`model-resolve.sh --mark-unavailable <id>`) and retry that spawn
  once with the next resolution.

## 8. Judge independence

Resolve the judge with `model-resolve.sh judgement --swarm-root <abs> --avoid <producer-model>`
when `producer-model:` is known: a candidate different from the producer is preferred; if none is
available the judge runs on `inherit`. `producer-model: inherit` means the producer ran on the
session model, which is UNKNOWN: the script prints the plain resolution plus a stderr note. Any
stderr note ⇒ the orchestrator adds `- warn: judge independence not guaranteed`.

## 9. Callers

- `design-orchestrator`: after `planner` writes the plan (artifact-type `plan`, tier full). Replaces
  the old ad-hoc grill×3: the grill lenses now run inside the panel.
- `implementation-orchestrator`: before the local merge (artifact-type `diff`). `reviewer` is kept
  only as a thin alias: its checks (plan compliance, invariants, quality, tests) are fully covered
  by completeness-critic + rules-auditor + defect-hunter on a diff, so a separate reviewer would
  only pay twice for the same signal.
- root `orchestrator`: final verdict of analysis runs (artifact-type `report`).

**Not paneled:** a `direct` objective (the root answers a trivial one-file objective itself, opens
no run, persists no artifact). `light` never launches design; an implementation phase (no tier
header ⇒ full panel on the diff) and an analysis report (light panel) are still reviewed.

## 10. No overlap with `verifier`

`verifier` checks TRACEABILITY: that a domain's closing verdict traces to findings actually
persisted in `.swarm/` and satisfies that domain's `## Output` contract. The panel checks the
QUALITY and TRUTH of the artifact itself against the objective and the repo. The verifier never
scores an artifact; the panel never checks persistence.
