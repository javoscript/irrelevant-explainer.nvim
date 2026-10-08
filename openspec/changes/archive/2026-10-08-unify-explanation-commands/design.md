# Design

## Context

See proposal.md for motivation. `init.lua` currently exposes thin public `code()`/`diff()` wrappers and separate commands. `session.start()` already resolves notes/detail to their source, owns request configuration, cancellation, queues and freshness, and delegates collection by mode. `diffview.lua` is the optional integration boundary: `current(win)` verifies actual source roles, revisions and loaded buffer identities; `review_source(win)` resolves a live file panel without moving selection or focus.

`current(win)` currently combines ownership and readiness checks. Treating every failure as "not Diffview" would misroute loading or conflicting views. Ordinary code must remain usable without loading Diffview. The runtime already supports commit-to-working comparisons, so the new outside-review action needs opening/orchestration rather than a new diff collector.

Existing offline coverage is in `tests/session_test.lua` and isolated real-plugin cases in `tests/diffview_test.lua`. The latter creates disposable Git repositories, loads the installed Diffview runtime, waits for validated state and uses the fixture agent, not a provider. Documentation and the empty Review hint still use the old commands.

## Goals / Non-Goals

**Goals:**
- Resolve the source and route once before entering the existing request pipeline.
- Keep dependency-specific inspection/opening inside `diffview.lua`, with cancellation ownership in the session lifecycle.
- Establish the intended comparison before collection; reuse all subsequent snapshot, queue, budget, result and cache semantics.

**Non-Goals:**
- No general diff-buffer detector, forced-mode public aliases, parser targeting, new inference scheduler, batching or cache implementation.
- No synthesis of a second manifest from all dirty editor buffers. Unsaved overlays apply to files already represented by the comparison, as today.
- No automatic empty-tree fallback for unborn HEAD, automatic save/stage, mutation of global Diffview defaults, or user-configurable revision picker.

## Decisions

### One public dispatcher, existing internal collectors

Expose `explain(scope, selection)` and `Explainr [file|selection|hunk|review]`; default to file. Remove public `code()`/`diff()` and their commands, without deprecated wrappers. Keep `review()`/`ExplainrReview` display-only. Internal mode-specific calls remain appropriate for automatic navigation and Refresh: those already have a captured target and must not guess a new mode from current focus.

Resolve associated-reader sources before routing. File uses Diffview source-window ownership; selection uses the existing exact code-selection collector, never becomes hunk scope; hunk requires a coherent Diffview source; review uses the owning comparison, including its file panel, or opens a comparison from an ordinary source. Reject unrelated utility buffers. Preserve the existing Lua visual descriptor and Ex selection reconstruction rather than inventing new range semantics.

Alternative: keep both commands as aliases. Rejected because compatibility is explicitly not required and duplicate public modes would retain the mapping burden. Do not collapse code/diff collectors merely because the command is unified.

### Classify ownership independently from readiness

Extend the optional adapter with an ownership inspection that distinguishes an ordinary source, a Diffview source, its file panel, and a recognized but unavailable/unsupported view. Inspect the loaded Diffview registry/layout in the source window's tab without requiring Diffview in the ordinary-code path. Use window membership, not buffer names, filetypes or `vim.wo.diff`. Keep the existing strict `current()` validation for actual collection; do not weaken it to make classification succeed.

A native vimdiff window is still an ordinary code source for file scope. A Diffview source showing the same working buffer as an ordinary split remains a diff source. File/hunk from the explorer still report a source-pane requirement; only review resolves that panel. Loading/unsupported owned views report an error instead of opening a different comparison or explaining their contents as ordinary code.

### Open HEAD to working tree, not the default index comparison

Resolve repository/worktree from the originating named source path with async argument-list Git commands. Use that window's effective cwd only for unnamed sources; do not fall back to cwd when a named source lies outside a repository. Preserve linked-worktree identity. Resolve HEAD; fail clearly when absent. Capture origin and configuration before any asynchronous work.

Open a new, operation-owned Diffview comparison for that worktree, semantically `DiffviewOpen -C<root> HEAD`, without a path restriction or `--cached`. Do not reuse an unrelated existing tab. The resulting commit-to-working comparison represents staged plus unstaged changes as their final net difference. Separate staged/index groups in an existing view are still never merged.

Use the dependency's opening API with argument lists and safe path handling, not interpolated Ex/shell strings. Diffview prepends `default_args.DiffviewOpen`; validate the resulting repository, pair and absence of path filters instead of trusting the supplied arguments. If defaults prevent the intended comparison, fail with an actionable message rather than mutate user configuration or review the wrong content. Respect the effective untracked policy and include it in normal comparison identity.

Diffview's preferred current filename can select an unintended group. Within this newly owned view only, select a compatible working entry if necessary using the existing guarded internal integration pattern, then validate it. Do not change file selection when review originates in an already-open view. No eligible text entry means no inference; binary/empty entries remain metadata when text entries exist.

Alternative: open without a revision. Rejected because that compares index to working tree and misses staged-only changes. Concatenating staged and unstaged patches is also wrong: edits can cancel out.

### Opening is a cancellable preflight, not inference

Represent opening as owned pending work in the session layer, before a source-bound diff reader exists. Track origin, configuration, intended repository/comparison, opening view, cancellation generation and cleanup handles. Expose a pending-opening notification/status; do not create placeholder aligned notes against incoherent buffers. Bind Cancel/Close to this operation from both the origin and newly opened view. Leave an opened Diffview tab intact on cancellation/failure, and preserve unrelated accepted explanations.

Use relevant Diffview events to recheck strict readiness with a bounded asynchronous retry/watchdog when necessary; no fixed sleep or blocking `vim.wait` in production. `view_opened` and `view.ready` are not source-buffer readiness barriers. `DiffviewDiffBufWinEnter` can prompt a recheck, but is not itself proof both panes are coherent. Start with a 10-second opening deadline, independent of agent execution timeout; fail visibly and clean up if it expires. Timer/event details remain adapter-local.

Coalesce repeated equivalent opening requests from the same origin or owned view. Mark the explicit review as pending before file-navigation automation can enqueue work for that view. Check operation identity after every callback; cancellation, original source closure, view closure, replacement comparison or an incompatible new request retires it. Mere file navigation in the intended comparison does not. A callback must never adopt whichever view happens to be current in another tab.

Once ready, transfer the captured configuration and resolved source to one ordinary explicit review request. Collection then captures current coherent contents; opening is not a promise to freeze working files at the original keypress. Existing freshness checks cover changes during and after capture. Transfer cancellation ownership without a gap, and remove preflight handlers. Opening may switch to the new Diffview tab as explicitly requested; later callbacks must not steal focus if the user navigates away.

### Compose with scope removal, batching and caching

This design assumes the implemented scope-removal behavior, not stale structural-scope text still in main specs. Sync that completed delta before this change or merge its content deliberately; do not restore function/class support.

This delta preserves the current single-invocation wording of `Whole-comparison explanation scope` except for command/API names. The separate batching change owns replacement of that execution contract. When applying or syncing the second of these changes, combine the new command/API wording with batching's job/coverage requirements and its scenarios; never restore the single-invocation limitation or old commands. Likewise preserve the cache changes to code commands/refresh. No changes to the batching artifacts are part of this proposal.

Command spelling is not generation identity. The dispatcher must enter existing collectors and caches with the same semantic mode, scope and comparison as an equivalent request in an already-open view. No parallel cache or agent invocation path belongs in the opener.

## Risks / Trade-offs

- [Diffview internals and async lifecycle vary] → Keep guarded access in the compatibility boundary and cover the installed runtime with real integration tests, especially delayed readiness and staged initial selection.
- [A simpler command hides mode choice] → Define file routing by originating window, retain mode-specific reader behavior, and test the same buffer in ordinary and Diffview windows.
- [Configured defaults change comparison meaning] → Validate repository/revisions/filters and fail before inference; do not silently use whatever opened.
- [Unsaved-only files are absent from Diffview's manifest] → Document this existing limitation rather than claim all dirty editor buffers are reviewed.
- [Multiple planning changes modify the same requirements] → Explicitly reconcile scope-removal, new command names and batching/cache semantics during implementation/sync.

## Migration Plan

Replace internal public-wrapper callers, test fixtures, README/help/examples and reader hints with the dispatcher or the existing explicit internal session API as appropriate. In the user's local config during an authorized apply, replace code/diff file mappings with one file mapping, retain the captured Visual descriptor, and migrate hunk/review mappings. Preserve provider options, budgets, auto-explain and unrelated dotfiles changes. Do not edit the live config during this planning workflow.

Restart Neovim for removed commands to disappear; hot-reloading obsolete command registrations is not a compatibility promise. Rollback pairs the prior plugin revision with prior mapping text; no data migration is introduced. Run command/session tests, real Diffview integration, and the full offline suite. Inspect the rendered empty-review hint and opening-to-review transition when implemented, using existing render tooling. Do not invoke a real agent to test routing.

## References

- [Diffview command and event documentation](https://github.com/sindrets/diffview.nvim/blob/main/doc/diffview.txt)
- [Diffview opening and default arguments](https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/lib.lua)
- [Diffview asynchronous file selection](https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/scene/views/diff/diff_view.lua)
- [Git revision and file-list behavior](https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/vcs/adapters/git/init.lua)
