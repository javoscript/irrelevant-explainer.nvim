# Tasks

## 1. Separate request identity from display binding

- [x] 1.1 Refactor comparison descriptors and snapshot collection in `diffview.lua`/`diff.lua` so captured target/configuration and content guards can be checked without reading the currently selected file as the request target; preserve current behavior first and verify the existing diff/session suites still pass.
- [x] 1.2 Separate comparison ownership, request lifecycle tokens, and current file/window bindings in `session.lua` without changing cancellation policy yet; verify existing queue, late-callback, retained-batch, and background-tab closure tests before enabling new behavior.
- [x] 1.3 Add detached-collection/freshness tests for A-to-B navigation during collection, clean buffer recreation, unsaved working/index changes, and fixed-commit comparisons; verify A's captured target never becomes B and unrelated working changes do not invalidate fixed revisions.

## 2. Let file and hunk work survive navigation

- [x] 2.1 Change same-comparison file navigation to preserve collection/inference and retain off-screen completion under its original target; update the real-Diffview cancellation expectation and verify A finishes while B is visible, returning to A makes no extra agent call, and returning before completion deduplicates pending work.
- [x] 2.2 Extend explicit FIFO scheduling to file/hunk targets across files, capturing configuration and promoting matching automatic work without duplication; verify one active invocation per tab, request-order execution despite out-of-order collection, and queue continuation after collection/provider/validation failure.
- [x] 2.3 Coalesce unstarted automatic navigation work to the latest eligible file, prioritize explicit requests, and drop only automatic candidates when Auto is disabled; verify A-running/B-then-C navigation, explicit B retention, runtime toggle boundaries, and no layout/focus/failure retry loops.
- [x] 2.4 Preserve comparison-wide Cancel/Close/Refresh cleanup and invalidate content-stale requests independently of navigation; verify cancellation during collection, late success after cancellation, comparison/filter/staged-set switches, and closure in one background tab cannot affect another tab.
- [x] 2.5 Separate retained-result updates from visible-file rendering and display selected/background/queued status without putting hidden-file loading rails on the current file; verify delayed A success/failure preserves B's expanded buffer, cursor, viewport, focus, and Ready state in UI and real-Diffview tests.
- [x] 2.6 Update README and `doc/explainr-ui.txt` for navigation-surviving requests, explicit FIFO/coalesced Auto work, and comparison-wide cancellation; check examples against the implemented request tests and remove obsolete cancel-on-navigation claims.

## 3. Collect and validate one whole-review response

- [x] 3.1 Add complete review targets and deterministic manifest file identities in `diff.lua`, retaining exact filters/revisions, rename paths, old-only/new-only ranges, and metadata-only entries; verify multi-file review fixtures, binary/empty states, unsupported content failures, and no-text-target rejection.
- [x] 3.2 Add review prompting and full serialized-budget enforcement in `prompt.lua`, requiring complete coverage regardless of file/hunk context strategy; verify all targets plus cross-file decision/test content occur once as context, exact-budget/one-byte-over cases, and overflow starts zero agent invocations with no focused fallback.
- [x] 3.3 Add scope-specific version-2 narrative/file validation in `model.lua` while preserving version-1 code/file/hunk contracts; verify valid asymmetric add/delete/rename cases, independent file overviews, missing versus explicitly empty file entries, duplicates/unknown IDs, cross-file anchors versus evidence, and invalid narrative citations.
- [x] 3.4 Exercise plain/OpenCode/Codex/custom decoding with version-2 completed output and unsuccessful/truncated output; verify final-output selection remains transport-owned, wrong-scope versions fail validation, and version-1 regression fixtures still pass without introducing provider-specific fallback.
- [x] 3.5 Document the review envelope, narrative grounding, eligible-file coverage, and atomic rejection in `doc/explainr-agents.txt`; verify documented payload examples with the same model validation fixtures and explicitly describe wrapper compatibility and provider output-limit failures.

## 4. Integrate review requests, retention, and commands

- [x] 4.1 Extend the comparison queue to review requests and install a validated narrative plus normalized per-file batches atomically; verify one uncached review invokes the agent once, navigating all returned files invokes it zero more times, identical full-file batches replace, and distinct fresh hunk batches remain.
- [x] 4.2 Retain whole-review provenance in distributed file results and review-cache keys; verify shared decision edits invalidate all dependent results, explicitly empty files do not trigger Auto, config/decoder changes prevent false reuse, and focused/hunk requests are not mistakenly satisfied by broader review notes.
- [x] 4.3 Suppress automatic candidates while a review is queued/running without discarding explicit requests; verify review failure preserves prior fresh data, continues explicitly queued work, and never initiates repair or per-file fan-out.
- [x] 4.4 Add `ExplainrDiff review` and Lua scope support with completion, keeping default file scope; add display-only `ExplainrReview`/Lua access and mode-aware Refresh dispatch, verifying command behavior, unsupported-context errors, repeat-review cache reuse, and file refresh after a distributed review result.
- [x] 4.5 Update README and `doc/explainr.txt` with generation versus display-only access, complete-review budget semantics, retained results, and File versus Review refresh; verify commands and completion match the documented API tests.

## 5. Add the Review reader in the existing pane

- [x] 5.1 Add an independent read-only Review buffer and Review/File header state in `ui.lua`, reusing Markdown syntax support but not anchor-linked detail synchronization; verify long wrapped prose and source scrolling are independent, native diff bindings/source options remain unchanged, and missing parsers are harmless.
- [x] 5.2 Add the pane-local `<Plug>(ExplainrReview)` action, saved narrative reading position, Esc-to-File and q-to-close behavior; verify Review can reopen without inference, empty/stale/pending states are explicit, code-mode mappings stay unchanged, and repeated mode changes leave no stale detail gutters or dimming.
- [x] 5.3 Render validated narrative file-reference rows and resolve them through the Diffview adapter, preserving configured navigation/explorer actions; verify Enter selects the exact renamed/deleted/metadata-only entry after coherent loading, prose is inert, actual file switches enter File, and no-op/disabled actions preserve Review.
- [x] 5.4 Preserve active reading state on background completions and defer replacement of a currently expanded fresh file batch until detail exits; verify review completion while reading File never switches modes or steals focus, status updates preserve buffers/views, and stale content is not presented as fresh.
- [x] 5.5 Extend `tests/visual.lua` and the existing capture workflow for Review, File overview/detail, selected/background pending, narrow headers, stale/failure, and return-from-reference states; capture and inspect the rendered results for readable mode/status, no source displacement, no misplaced rails, and correct cleanup.
- [x] 5.6 Update `doc/explainr-ui.txt` with the Review/File reading flow, selectable references, shortcut mapping example, independent scrolling, header priorities, and close controls; verify the documented sequence with the real-Diffview fixture and retain existing File detail behavior.

## 6. Verify the integrated behavior

- [x] 6.1 Run the full suite with `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'` using the repository's Diffview test setup; verify all legacy code/file/hunk and new review/background scenarios pass without paid inference.
- [x] 6.2 Run one end-to-end delayed-agent review scenario covering navigation during collection and generation, file-reference jumps, mode-aware refresh, shared-context invalidation, and close-before-callback; verify exact invocation counts, selected-file output, no late result installation, and no focus/view/gutter regressions.
- [x] 6.3 Reconcile final implementation and help against all three delta specs, run `openspec validate add-whole-review-explanations --strict` and `git diff --check`, and record verification results plus any genuine limitations before marking implementation complete.

## Verification — 2026-10-07

- Full offline suite: 275 passed, 0 failed; its isolated real-Diffview child: 24 passed, 0 failed.
- Final header adjustment: UI suite rerun, 159 passed, 0 failed. Session queue/freshness suite: 24 passed, 0 failed.
- Real-Diffview coverage includes file-tree Review generation/display/refresh with unchanged focus, delayed navigation, FIFO/Auto promotion, exact rename/deletion/binary references, shared-evidence invalidation, and late callbacks after Close.
- Added the requested Review-body loading animation, including empty and retained narratives; checked frame changes, unchanged buffer/view state, and terminal-state cleanup. No invented completion percentage.
- Rendered and inspected Review ready/pending/empty/narrow/stale/failed, File overview/detail with background status, selected-hunk loading, return-from-reference, and File stale/failed states. Captures are local artifacts under `.amp/in/artifacts/`; the capture font lacks the existing header spinner glyph, but body rails render correctly.
- Strict OpenSpec validation and `git diff --check` pass. Local Neovim review mappings and the 512-KiB input budget load successfully.
- No paid inference or authenticated provider smoke test was run; provider output limits and CLI compatibility still depend on the user's configured tool. Changes are local, not committed or archived.
