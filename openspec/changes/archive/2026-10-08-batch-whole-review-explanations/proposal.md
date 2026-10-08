# Proposal

## Why

Large whole-review requests can trigger external-agent compaction or output truncation, losing expensive work or exact source grounding. Separately, restarting Neovim loses completed explanations for unchanged inputs; bounded review generation and a shared persistent result cache avoid both kinds of repeated work.

## What Changes

- Replace the monolithic explicit review request with a host-controlled job: one immutable comparison snapshot, bounded annotation requests, then bounded cross-file synthesis. Keep one external invocation at a time per tab and no inference when reading or expanding completed results.
- Separate complete local snapshot capture from per-request serialization. Remove redundant review patch text, group affordable files, and split oversized file versions into coordinate-preserving source ranges with explicit coverage accounting. Preserve all eligible source text across the job rather than silently dropping files or unchanged rationale.
- Bound request size, expected response size, captured snapshot size, and total external calls. Apply the same limits to synthesis; fail explicitly when an indivisible input or synthesis cannot fit rather than invoke agent compaction as a strategy.
- Checkpoint successfully validated units in memory. Repeating the explicit review command resumes matching work; Refresh starts fresh. Keep final installation atomic and preserve previous fresh explanations on failure.
- Persist completed visual-selection, code-file, diff-file, diff-hunk, and whole-review results in a shared, bounded local cache. Match exact normalized targets, supplied context, and generation identity across Neovim sessions; validate disk hits before display. Unfinished review checkpoints remain memory-only.
- Provide private atomic JSON storage under Neovim's cache directory, opt-out and clear controls, and Refresh bypass with success-only replacement. Normalize session-specific buffer IDs, including unnamed-buffer identities, without changing selection boundaries.
- Show measured annotation progress, synthesis state, and actionable failure/resume diagnostics without changing pane layout or displaying partial answers as a complete review.
- **BREAKING**: Explicit review may make multiple billable calls and uses a versioned phase-specific external payload instead of requiring a single version-2 response. Custom review wrappers must support the new contract. Code/file/hunk version-1 requests and generic CLI event decoders remain unchanged.

## Capabilities

### New Capabilities

None. Extend the existing diff, execution, and display contracts.

### Modified Capabilities

- `code-explanation`: Cross-session reuse of exact code-file and visual-selection requests, including unsaved/unnamed input and column-accurate selections.
- `diff-explanation`: Snapshot-wide coverage, bounded review planning, chunk-aware targets, evidence-grounded synthesis, and resumable comparison-owned job lifetime.
- `external-agent-execution`: Phase-specific review payloads, budgets, internal checkpoints, atomic installation, and shared persistent completed-result identity/storage/validation.
- `aligned-explanation-ui`: Measured review progress, synthesis, resumable-failure and cache-hit states in the existing header.

## Impact

Changes concern `lua/explainr/code.lua`, `diff.lua`, `prompt.lua`, `model.lua`, `session.lua`, configuration/commands in `init.lua`, status projection in `ui.lua`, and their tests and documentation. A review planner and shared completed-result cache separate those responsibilities from session display ownership. No provider SDK, credentials, or database dependency is introduced.

The implemented `remove-structural-explanations` and `unify-explanation-commands` changes are the baseline: `Explainr [file|selection|hunk|review]` and `explain(scope, selection)` serve exactly the five targets listed above, with no structural scopes or old code/diff aliases. Preserve context-aware file routing and the existing cancellable HEAD-to-working-tree opening for review outside Diffview. After readiness, that action enters the same batching/cache pipeline as an equivalent manually opened comparison; this change does not add a second opener or inference path. `ExplainrReview` remains display-only.

Out of scope: agent-driven repository/snapshot tools, persistent conversations or unfinished checkpoints, provider fallback, automatic error retries, lazy detail generation, concurrent inference, changing external OpenCode configuration, and a UI redesign. Fixing OpenCode's internal compaction is not part of this change. Reconcile overlapping delta requirements with the implemented changes during sync/archive without restoring retired commands or the single-invocation review contract.
