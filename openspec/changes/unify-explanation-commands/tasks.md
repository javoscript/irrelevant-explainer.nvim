# Tasks

## 1. Unified entrypoint and source routing

- [x] 1.1 Separate source-window ownership classification from strict readiness in `diffview.lua`, reuse session reader-source resolution, and verify real-Diffview tests distinguish ordinary and diff windows sharing one buffer, the file panel, loading/conflicting views, and native vimdiff; ordinary code must not load Diffview.
- [x] 1.2 Introduce `Explainr [file|selection|hunk|review]` and `explain(scope, selection)`, remove public code/diff entrypoints, and migrate their callers; verify command registration/completion/defaults, absence of aliases, invalid/retired scopes, exact Visual descriptors and source resolution from notes/detail in session tests.
- [x] 1.3 Update README, help, Lua mapping examples, visual fixtures and the empty-review hint; verify ExplainrReview remains display-only, hunk/file panel errors do not invoke the agent, and render/inspect the empty Review state with the new command hint.

## 2. Open the intended working-tree comparison

- [x] 2.1 Add asynchronous source-repository/worktree and HEAD resolution plus argument-safe Diffview opening in the adapter; verify disposable-repository tests for named-source versus cwd precedence, unnamed cwd fallback, linked worktrees, and paths containing spaces/quotes.
- [x] 2.2 Validate the opened repository, HEAD-to-working pair, unfiltered scope and compatible selected entry before collecting; verify staged-only, unstaged-only, mixed and fully undone staged edits produce independently expected net contents, while conflicting default arguments fail without inference.
- [x] 2.3 Preserve originating existing comparisons and effective untracked/unsaved-overlay policy; verify staged/revision/path-filtered views remain unchanged, unrelated tabs are not adopted, eligible untracked entries follow policy, and missing dependencies, absent HEAD, clean and metadata-only comparisons report errors with zero agent calls.
- [x] 2.4 Document HEAD-to-working net semantics, repository selection, untracked policy, unsaved-only manifest limitations and no-save/no-stage behavior; verify documented examples against fixture comparisons and unchanged source/index bytes.

## 3. Pending opening lifecycle and review handoff

- [x] 3.1 Own opening as cancellable session preflight with origin/configuration capture, event-driven readiness checks and a bounded timeout; verify delayed panes never start inference early, timeout releases handlers, and invocation-time configuration reaches the eventual review request.
- [x] 3.2 Integrate cancellation, closure, incompatible replacement, duplicate-request coalescing and Auto suppression before handoff; verify repeated events/commands submit exactly one review, Cancel/Close and source/view closure prevent late invocation, unrelated views/accepted notes survive, and ordinary file navigation does not retarget the review.
- [x] 3.3 Transfer readiness into the existing review queue/collector/cache path without changing focus on late completion; verify reading/navigation, Refresh, freshness and retained results match a manually opened equivalent comparison, and document/inspect the opening-to-Review transition with the fixture agent.

## 4. Integration and migration

- [x] 4.1 Reconcile any already-applied scope-removal or batching/cache changes in touched artifacts, runtime callers and tests; verify no structural scopes, old public commands, single-call regression after batching, or alternate cache/agent path is reintroduced, then run `openspec validate unify-explanation-commands --strict`.
- [ ] 4.2 During authorized local-config synchronization, migrate the user's Explainr mappings to one context-aware file action and unified selection/hunk/review calls while preserving captured Visual endpoints, provider settings, budgets and unrelated edits; verify the config loads headlessly and mappings reference only supported entrypoints without invoking a provider.
- [x] 4.3 Run `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`, including the isolated real Diffview suite; inspect the final diff and report any skipped dependency coverage, visual limitations and actual delivery state. No real external-agent request is needed.
