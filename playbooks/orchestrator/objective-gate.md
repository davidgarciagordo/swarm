# orchestrator · objective gate
On demand from agents/orchestrator.md — trigger: §1.0bis Step 2 confidence is low or the objective is ambiguous.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 1.0bis Step 3 — ask, in ONE single round (same pattern as discovery, §5.3)

Build ONE `AskUserQuestion` with:
- your optimized interpretation of the objective, as the recommended option;
- up to 2 alternatives if there genuinely are any (never invent artificial alternatives to fill space — if you only see
  one reasonable reading, one extra option plus the free rewrite is enough);
- `AskUserQuestion`'s "Other" option serves as "I want to rewrite it myself" — free text from the owner, with no
  suggestion from you in between.

**Style, always in plain language (same discipline as discovery §5.3):** neither the question nor the options use
meta-language about your interpretation process or project jargon; ask in terms of what's going to be done, each option
describing in business-impact terms what would be built.

```
AskUserQuestion(questions: [{
  question: "What exactly do you want me to do?",
  header: "Objective",
  multiSelect: false,
  options: [
    { label: "<your interpretation, in one clear sentence> (recommended)", description: "<what you base it on>" },
    { label: "<alternative 1, if any>", description: "<what you base it on>" }
  ]
}])
```

**Resolve the result:**
- The owner confirms your interpretation, picks an alternative, or writes their own in "Other": THAT final text is the
  `objective:` used by the rest of this run — tier classification (§1.1), discovery, analysis, design, and what gets
  persisted to `.swarm/decisions.md`. Go to §1.1 with that text. **Don't write anything yet**: `memory-orchestrator`
  isn't launched until §2.2 and the run doesn't open until §2.1 (a `SendMessage` to it from here reaches no one). Keep
  BOTH texts already run through §5.0's sanitization (the sanitized raw argument and the sanitized final text) and
  persist them in **§2.3**.
- The owner cancels the dialog (closes it without choosing — normal behavior, not an error): **the run ends here and
  never gets to open.** Don't classify a tier, don't open a run, don't launch anyone. No `<run-id>` ⇒ no `summary --run`
  (exit 64 without `--run`) and no live `memory-orchestrator` ⇒ no `curate` or `write decision` (§4's never-opened
  branch). Your verdict goes out as-is, with no summary line and no memory close:
  ```
  BLOCKED unconfirmed objective interpretation
  ```
  No `[pending]` is recorded here (unlike a cancelled discovery batch, §5.3: there the run and `memory-orchestrator`
  already exist). Nothing is lost: Step 1 treats a `[pending]` line as absent, so a future run with the same raw text
  asks again either way.
- Non-interactive launch: §13.4 (take the recommended interpretation, record it `ASSUMED` after `resolved interpretation`).

### 2.3 Deferred persistence of the objective interpretation (§1.0bis Step 3)

**Only if §1.0bis reached Step 3 and the owner CONFIRMED an interpretation** (yours, an alternative, or "Other"). If the
gate passed via high confidence (Step 2) or reused a `raw:` match from Step 1 (that line already exists), write NOTHING.

Here both preconditions hold: the run is open (§2.1, there's a `<run-id>`) and `memory-orchestrator` is alive (§2.2, the
only writer of `.swarm/`). As soon as it answers its `operation: build` (`OK`/`DONE`), and BEFORE launching any domain
orchestrator, persist the TWO texts §1.0bis already sanitized — don't rebuild or reinterpret them:
```
SendMessage(memory-orchestrator, "write decision --text \"raw: <sanitized raw argument> · objective: <sanitized final text> · resolved interpretation (run <run-id>)\"")
```
Wait for its `OK`/`written` before continuing. The `raw:` field goes FIRST (same as §5.3/§5.4): it's the idempotency key
and carries the sanitized RAW argument — never the already-interpreted text. The `<run-id>` goes LITERAL.

**ONE write, only on this path.** `memory-orchestrator` has `maxTurns: 12`; a run with the gate spends startup + `build`
+ this write + §5.4's single write + `curate`. Never split it or repeat it "just in case".

**This line is NOT a discovery close.** THIS run writes it a few steps before §5.1 reads the same flat file for the same
`raw:`; if §5.1 accepted it as "already closed", the run would skip discovery by its own side effect. That's what the
`resolved interpretation` marker is for, and why §5.1 only accepts lines carrying the `discovery <run-id>` marker.
