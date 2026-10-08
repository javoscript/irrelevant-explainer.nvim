# Design

## Context

See `proposal.md` for motivation. `diff.lua` already collects complete comparison context when affordable, but constructs one selected-file/hunk target. `prompt.lua` asks for target-only notes, and `model.lua` validates a version-1 result with at most one whole-file overview. `session.lua` owns one displayed session per tab; its identity includes selected file and source buffers. Navigation calls `discard_pending`, and acceptance requires the currently displayed pending snapshot. `fresh_async` and `restore_async` recollect through the selected source window. Removing cancellation alone would therefore neither accept off-screen results nor validate the right file.

The right-hand pane in `ui.lua` has an aligned overview buffer and an in-pane Markdown detail buffer. Detail still uses source anchors, synchronized scrolling, and focus decorations. `pane:set` collapses detail, so it cannot be the unconditional destination for background completion or header updates. Existing model/session tests and `tests/review.lua` provide grounded fixtures; real-Diffview tests currently assert cancellation on navigation and must change deliberately.

## Goals / Non-Goals

**Goals:**
- Separate request/content identity from the currently displayed windows without weakening unsaved-buffer, staged-content, or revision freshness checks.
- Reuse file-note validation, retention, alignment, and detail rendering after distributing a review response.
- Preserve one external invocation at a time per tab and explicit user control over generation.

**Non-Goals:**
- Streaming partial JSON into the UI, per-file retries of a failed review, automatic batching/chunking, provider-token estimation, or billing guarantees.
- Persistent jobs/history, continuation after reader/view closure, cross-tab shared job scheduling, or support for currently unsupported comparison types.
- New floating windows, a chat interface, or changing code-mode navigation.

## Decisions

### 1. Explicit review generation, separate display-only entrypoint

Extend `ExplainrDiff` completion and the Lua `diff` API with `review`; keep `file` as the default. Review scope always requires complete comparison coverage, independently of `context.diff`, which remains the coverage preference for file/hunk requests. This avoids the ambiguity of requesting a whole review while silently supplying focused context. Respect the captured revision pair, filters, untracked policy, and staged/working set.

Add `:ExplainrReview`, `require("explainr").review()`, and a buffer-local `<Plug>(ExplainrReview)` action to display the current comparison's retained narrative or pending/empty/stale state without generation. Users can map a preferred shortcut; no global default mapping is installed. `ExplainrDiff review` selects Review pending mode immediately, without moving focus, so completion can populate it naturally. If the user switches to File or navigates before completion, completion only updates storage/status and does not switch back.

Both Review actions also accept the live DiffviewFiles panel as their origin. The adapter resolves the currently displayed comparison's source pane without selecting the tree row or moving focus, and the normal coherent-panes checks still apply. File/hunk actions remain source-cursor scoped.

Alternative: a separate generation command or automatic full-review generation on navigation. Rejected because scope already belongs to `ExplainrDiff`, while automatic generation would unexpectedly expand external-agent usage.

### 2. One immutable comparison snapshot, many file targets

Separate comparison capture from the selected display binding in `diffview.lua`/`diff.lua`. At invocation, capture comparison identity, selected target/cursor, config, and loaded mutable-buffer data needed to survive buffer replacement. Resolve Git/filesystem data asynchronously against that descriptor, not whichever file is selected when callbacks run. Retain the double-read/content guards; a real capture race must fail rather than silently retarget.

A review snapshot carries the complete manifest, supplied old/new text and patches, and deterministic per-file whole-file targets. Assign each manifest entry a host-owned `file_id`, with old/new paths retained separately for renames and deletions. Text entries with at least one nonempty available side are annotation targets; binary and both-empty entries remain visible metadata with an explicit no-text-annotations reason. Existing unsupported types and unreadable required text fail collection. A comparison with no eligible textual targets fails before inference.

The input byte check includes instructions, response contract, all context, and all target descriptors. Review overflow fails with advice to filter Diffview, increase the budget, or request file/hunk scope. Never silently fall back, omit a required file, or split into several calls.

### 3. Review-specific version-2 envelope, legacy version 1 unchanged

Use version 2 only for review requests. Keep version 1 for code/file/hunk requests and all existing wrappers. The review response has this shape (field values here describe the contract rather than literal output):

```text
version: 2
review:
  title: nonempty single-line text
  sections: nonempty array of
    heading: nonempty single-line text
    detail: nonempty Markdown
    intent_basis: documented | inferred | unknown
    evidence: supplied path/side/range citations
    file_ids: unique references to supplied manifest entries
files: one entry per eligible textual target
  file_id: exact host-supplied identity
  notes: existing file-scoped note array
```

Prompt for a short overall explanation, how files connect, and intent/caveats, not a concatenation of file summaries. Sections have explicit intent/evidence so documented rationale remains grounded without inventing a source anchor for the narrative. Render selectable file-reference rows from validated IDs after sections, rather than interpreting arbitrary Markdown paths as commands or executable links. Metadata-only references can navigate to a file but show its explicit no-text state.

Require exactly one result entry for every eligible file, with no duplicates/unknown IDs. Allow empty `notes` for an explicitly returned file: structural coverage does not guarantee useful model analysis. Validate each file's notes using its own version-1 file target and the shared supplied evidence context; cross-file evidence is allowed, cross-file annotation anchors are not. Existing optional overview semantics apply once per file, not once per review. Reject the entire response on any invalid section, file result, missing file, wrong version, or unsuccessful process completion. Install narrative and file results atomically after freshness validation; preserve previous fresh results on failure.

Alternative: flatten all notes into the current envelope and fake an overview spanning the comparison. Rejected because notes have one old/new file pair and the narrative has no source range. Transport remains generic final-output decoding; test plain/OpenCode/Codex/custom decoders with both supported envelopes.

### 4. Comparison-owned request lifetime, selection-owned rendering

Within the existing tab session, separate comparison ownership (repository, revision pair, path filters, staged/working set and untracked policy), explicit request records (target, config, snapshot, lifecycle token), and display selection (current file/windows, File/Review, reading position). Keep this responsibility in `session.lua` rather than introducing a separate global job service.

File switches update display bindings and exit file detail, but do not change request tokens or cancel collection/inference. Completion validates its own request, writes the original file/comparison store, then notifies the view. The view projects only results matching its selection. Off-screen completion changes status only; replacement of a currently expanded batch is deferred until the user exits that detail, unless content is stale and must be cleared. Background failure identifies its target without changing another file's Ready state.

Split freshness checks into content/comparison validity and display attachment. Revalidate captured Git revisions/index/files and relevant mutable buffers without selecting hidden Diffview files. Clean recreated buffers with identical content are acceptable; disappearing unsaved state or changed relevant content invalidates the request. Bind windows only when displaying a matching selected entry. Retained results are checked again on return. Switching the comparison/filter/staged set, entering another explanation mode, or closing the owning view/reader cancels old owned work; switching tabs alone does not. Unrelated tabs and fixed-commit comparisons retain their existing isolation.

### 5. Explicit FIFO queue with one coalesced automatic candidate

Keep one active invocation per tab. Distinct explicit file/hunk/review requests for the same comparison queue in invocation order; capture each target and configuration at invocation. Equivalent pending requests reuse one record, including an explicit request promoting an automatic candidate to explicit ownership. Returning to a pending file only reconnects its display. Ordinary collection, provider, or validation failure advances the queue without dropping accepted results.

Keep at most one unstarted navigation-generated file candidate, updated to the latest coherent unexplained selected file. Explicit requests have priority over this candidate; active automatic inference is not cancelled on navigation. Turning Auto off drops only an unstarted automatic candidate. Preserve navigation-only toggle semantics, no retry on layout/focus/edit events, and background-tab start rules.

A queued/active review suppresses automatic file candidates for its comparison; success supplies their notes, while failure/cancellation does not fan out into automatic retries. Explicit requests are not silently discarded. Before starting one after a review, skip external inference only if its exact target, effective coverage/content, and captured config genuinely match an accepted result; a hunk or deliberately focused request is not equivalent merely because its file has review notes.

`ExplainrCancel` clears active and queued work for the owning comparison across all its files. `ExplainrClose` additionally tears down the reader but retains completed process-local answers. `ExplainrRefresh` preserves today's explicit queue reset, then bypasses cache for the visible target: Review regenerates narrative plus all files; File refreshes its followed file or selected hunk scope, never implicitly the entire review. A file result distributed from a review has file refresh scope.

### 6. Review/File modes inside the same pane

Review uses its own read-only `explainr` Markdown buffer, optional syntax highlighting, visible Markdown markers, native wrapping, and no range gutter/source dimming. Review scrolling and cursor movement never synchronize sources; source scrolling never moves the narrative. Keep the existing winbar row and source-placeholder lifecycle. File mode reuses the current aligned overview and expanded detail with their existing scroll, wrap, fold, and filler behavior.

Show active Review/File mode clearly in the winbar. File keeps its note counts/legend and Auto indicator; Review shows comparison/request state and Auto without pretending sections are file-note ordinals. Status distinguishes selected-target loading, queued work, and work running elsewhere; only pending ranges belonging to the currently displayed file receive loading decorations. No fabricated percentage or incrementally completed-file count while waiting for one validated response.

Pending Review also uses the loading tint and animated rail in its narrative viewport, including empty space before the first result. These are activity decorations, not source anchors or progress percentages. Reserve a narrow blank gutter while idle so pending transitions do not rewrap prose; use extmarks instead of rewriting content and skip the focused cursor row. Clear decorations on leaving Review or ending the request.

Enter on a rendered file reference asks the Diffview adapter to select that exact manifest entry, waits for coherent panes, then shows File notes without invoking AI. Arbitrary prose Enter is inert. Esc returns from Review to the currently selected File notes; q closes the reader. File's existing Enter/K and Esc/q behavior stays unchanged. Review inherits Diffview explorer/file-navigation mappings, respecting remaps and disabled bindings. An actual file selection change via those actions or the explorer selects File mode. A no-op next-file action at an edge does not reset reading state. Display-only return to Review restores its cursor/scroll position for the same result; a newly generated narrative starts at its beginning.

Alternative: a floating narrative or a preamble above aligned notes. Rejected because the former obscures code and the latter displaces source-row alignment. The accepted option-A mockup is conceptual, not a pixel/layout or line-number fixture.

### 7. Integrate complete review results with existing per-file retention

Store the narrative once per comparison snapshot/config and normalize each file entry into the existing file-target batch shape with shared review provenance. Replace an identical full-file batch; preserve distinct valid hunk batches under the existing accumulation rule. Mark explicitly returned empty file results as completed, preventing Auto from repeatedly requesting them. Do not remove hunk batches simply to eliminate intentional overlapping scopes.

Retain the original whole-review coverage for freshness checks, including after normalizing file targets. A changed supplied decision document invalidates the narrative and every file batch depending on it; independently focused batches retain their own guards. Manual file/hunk requests remain available regardless of review state. Repeating an unchanged review uses the exact matching review cache; switching reader modes only changes display and never generates. No cached focused result is mislabeled as complete review coverage.

## Risks / Trade-offs

- Larger answers can exceed provider output limits even when input fits → keep sparse-note guidance, surface truncation/schema errors atomically, recommend filtered reviews or explicit file/hunk requests; no automatic repair/fallback call.
- One malformed file rejects useful siblings → atomic acceptance keeps coverage honest and avoids presenting a partial review as complete; partial salvage is out of scope.
- Navigation-independent collection can miss unsaved/recreated buffers → capture editor inputs before yielding, use detached content guards, and test navigation during collection as well as inference.
- Whole-review context broadens invalidation → retain provenance rather than falsely treating each distributed file as independently fresh.
- Queueing increases time to a later explicit file → show active/background/queued state and keep Cancel/Refresh available; do not introduce provider concurrency.
- Completion can reset detail or write into replacement buffers → separate store updates from display projection, use request/view tokens, and test actual Diffview navigation with delayed callbacks.
- Existing user work in UI/test files → implement around those edits without reverting them; do not copy whole files from an older baseline.

## Migration Plan

Implement and test detached request ownership first while retaining existing file/hunk output, then add the review collector/contract and finally Review UI. Keep refactoring and changed navigation behavior independently verifiable. Update the existing cancellation-on-navigation expectations explicitly rather than weakening tests wholesale. Document `ExplainrReview` versus `ExplainrDiff review`, version-2 wrapper requirements, queue/cancel/refresh semantics, and complete-review limits.

Run the targeted suites and then `nvim --headless -u NONE -i NONE -n -c 'luafile tests/run.lua'`. Extend the existing visual fixture/capture workflow and inspect File overview, expanded detail, Review, pending/background, narrow-header, stale/failure, and navigation-return states. Use fake completed/delayed agents; verification must not require paid inference. No database or stored-history migration is required. Reverting the feature restores the old commands/behavior; restarting Neovim clears its process-local state.
