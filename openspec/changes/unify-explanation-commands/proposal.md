# Proposal

## Why

Separate code-file and diff-file commands make users choose a mode the originating window already identifies. Whole-review generation also requires manually opening a comparison; one explicit action should open and explain the current working-tree changes.

## What Changes

- Introduce `:Explainr [file|selection|hunk|review]`, defaulting to `file`, and `require("explainr").explain(scope, selection)`. Route file scope to code or diff by source-window ownership, including invocations from the associated reader.
- **BREAKING**: Remove `ExplainrCode`, `ExplainrDiff`, and public Lua `code()`/`diff()` entrypoints without compatibility aliases. Retain internal code/diff collectors and their distinct semantics.
- From outside Diffview, `Explainr review` opens the originating repository/worktree's HEAD-to-working-tree comparison, waits for coherent panes, then requests its whole review. This is the net effect of staged and unstaged edits, not index-to-working-tree alone or concatenated patches. Follow Diffview's effective untracked-file policy.
- From an existing Diffview source, file panel, or associated reader, review preserves the exact selected comparison and filters, including explicitly staged or revision comparisons.
- Keep selection as selected-code explanation, hunk as a source-pane diff action, and `ExplainrReview` as display-only narrative access. Preserve Refresh/Cancel/Close and automatic-explanation controls.
- Make comparison opening cancellable and duplicate-safe, without automatic saves, staging, or inference against guessed/loading/unsupported comparisons.
- Update command examples, Lua mappings, reader hints, and tests. Preserve the five targets: visual selection, code file, diff file, diff hunk, and whole review.

## Capabilities

### New Capabilities

None; extend the existing code, comparison, and reader contracts.

### Modified Capabilities

- `code-explanation`: Unified command/Lua entrypoint, context-aware file routing, exact selection handling, and removal of old public entrypoints.
- `diff-explanation`: Unified file/hunk/review requests and owned asynchronous opening of HEAD-to-working-tree reviews outside Diffview.
- `aligned-explanation-ui`: Update display-only narrative guidance to the new generation command without changing its no-inference behavior.

## Impact

Implementation concerns `lua/explainr/init.lua`, `session.lua`, the optional Diffview boundary in `diffview.lua`, reader hints in `ui.lua`, offline session/real-Diffview tests, and README/help/examples. Diffview remains optional for code explanations and required for diff explanations. Public mappings require migration; no compatibility layer is needed for this locally used plugin.

This change builds on the implemented `remove-structural-explanations` change, whose delta has not yet been synced to main specs. It is separate from `batch-whole-review-explanations`: no batching, protocol, cache policy, budget, or provider changes are included. Both changes must compose through the existing request pipeline; reconcile overlapping command wording when syncing their deltas rather than reverting either behavior. No UI redesign or general non-Diffview diff support is included.
