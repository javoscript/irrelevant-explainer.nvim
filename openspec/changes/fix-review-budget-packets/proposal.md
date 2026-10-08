# Proposal

## Why

Whole-change reviews can reject otherwise affordable output under a fixed per-unit allocation, or fail reduction because several independently affordable findings from one annotation call are treated as indivisible. Large split reviews also need clearer supplied-range boundaries and actionable diagnostics when a model cites unsent lines.

This change records the fixes already implemented and verified in the current worktree; it does not introduce additional implementation work.

## What Changes

- Share available annotation response capacity among assigned units, reserving the response envelope and array separators while retaining sparse text/count limits and the whole-response cap.
- Partition oversized child finding bundles into individual findings with deterministic child IDs, preserving every finding's complete original evidence and checkpoint/replay behavior.
- Supply explicit review chunk end coordinates, clarify original-line arithmetic and fragment boundaries in prompts, and identify offending ranges and first unsent lines in validation errors.
- Advance prompt/planner identities so old checkpoints and completed answers cannot be reused under changed request construction.
- Document the contract and add offline regression coverage without provider calls, automatic repair, source truncation, or relaxed grounding validation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-explanation`: Split oversized finding bundles before reporting an indivisible finding/evidence failure, preserving bounded synthesis and deterministic reuse.
- `external-agent-execution`: Share annotation output capacity, disclose exact review chunk coordinates, and make unsent-range rejection diagnostics actionable without accepting invalid output.

## Impact

- Implementation: `lua/explainr/review.lua`, `prompt.lua`, `model.lua`, and `identity.lua`.
- Verification: `tests/review_test.lua`, `model_test.lua`, `prompt_test.lua`, and existing identity/integration suites.
- Documentation: `doc/explainr-agents.txt` and this change's delta specs, design, and completed task record.
- No new dependencies, commands, configuration options, provider settings, or wire-version change. Code/file/hunk remain version 1 and review remains version 3. Restarting Neovim loads the new planner; changed identities intentionally invalidate previous reusable generation records.
