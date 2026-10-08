## MODIFIED Requirements

### Requirement: Exact review comparison

Diff explanations SHALL derive exact old/new identities, path filters and staged/working scope from the selected coherent two-way Git Diffview comparison. An explicit review outside Diffview SHALL first open a HEAD-to-working-tree comparison; this default SHALL NOT replace an existing originating comparison. Review coverage SHALL include the complete changed-file manifest; focused coverage SHALL include supplied entries and an omission count. Unsupported, loading or ambiguous comparisons SHALL fail explicitly.

#### Scenario: Review differs from working-tree diff
- **WHEN** Diffview compares two revisions and the working tree contains unrelated edits
- **THEN** the request uses the displayed revision comparison and excludes unrelated working-tree changes

#### Scenario: Working version has unsaved changes
- **WHEN** a supported comparison includes a working-buffer side with unsaved changes
- **THEN** the snapshot reflects those buffer contents and its patches agree with the displayed comparison

#### Scenario: Unsupported conflict or mixed comparison
- **WHEN** the view is a merge-conflict layout or its selected review scope has no unambiguous old/new comparison
- **THEN** the plugin reports the unsupported comparison without invoking AI on a guessed pair

#### Scenario: Supported mutable and fixed pairs
- **WHEN** the view compares commit-to-commit, commit-to-stage-0-index, commit-to-working or stage-0-index-to-working versions
- **THEN** the snapshot retains the exact pair, pathspec and untracked-file setting, with staged and working sets kept separate

#### Scenario: Unsupported content or revisions
- **WHEN** a focused comparison uses reversed/custom revisions, nonzero stages, symlinks, submodules, nonregular files, or only binary/empty target versions
- **THEN** collection reports the limitation without fabricated source lines or a guessed fallback comparison

### Requirement: Hunk and file explanation focus

Explainr SHALL support file (default), hunk, and review scope in Diffview sources. Hunk scope SHALL select exact changed spans at the invocation cursor, including zero-line insertion/deletion boundaries, and reject ambiguous/unchanged positions. File prompts and each review file target SHALL prioritize changed hunks, permitting unchanged target sections when their connection to changes is explained. Regular diff summaries SHALL prefer the first changed line within their anchor.

#### Scenario: Whole-file multi-hunk explanation
- **WHEN** a file-scoped request or a review file target contains several separated hunks
- **THEN** the prompt supplies all file hunks and asks for meaningful changes across them, not a generic walkthrough of unchanged code

#### Scenario: Relevant unchanged dependency
- **WHEN** an unchanged function or import within the selected file explains a changed hunk's effects
- **THEN** the prompt allows an additional note there with an explicit connection to the change, while other supplied files remain evidence rather than annotation targets for that file's result

#### Scenario: Range starts before the changed line
- **WHEN** a regular note's anchor includes an unchanged header followed by changed code
- **THEN** its summary sits beside the first actual changed line while range references and focus retain the whole anchor

#### Scenario: Hunk outside a source pane
- **WHEN** hunk scope is requested from an ordinary source or Diffview file panel
- **THEN** the plugin reports that a coherent Diffview source pane is required without opening a view or guessing a hunk

### Requirement: Whole-comparison explanation scope

Explainr SHALL support explicit review scope through the command and explain() Lua API. One uncached successful review request SHALL use one external invocation to obtain a whole-change narrative and file explanations for every eligible text entry in the exact comparison. File SHALL remain the default scope. Review generation SHALL not start automatically on navigation.

#### Scenario: Explain the selected comparison once
- **WHEN** the user runs `:Explainr review` or `require("explainr").explain("review")` in a supported comparison with three eligible files
- **THEN** one request supplies all three file targets and requests the narrative plus their notes
- **AND** reading any of those returned files or expanding its detail requires no additional inference

#### Scenario: Trigger Review from the file tree
- **WHEN** the user invokes Explainr review or display-only ExplainrReview from the live DiffviewFiles panel
- **THEN** the action uses the currently displayed comparison's source panes without requiring a source cursor or changing tree focus/selection
- **AND** file/hunk requests retain their source-pane requirement

#### Scenario: Filtered or staged comparison
- **WHEN** Diffview has path filters or a selected staged rather than working set
- **THEN** review scope uses that exact comparison, not unrelated repository changes or a merged staged/working set

#### Scenario: Metadata-only files
- **WHEN** a supported review contains text files together with binary or both-empty entries
- **THEN** the complete manifest retains those entries and exposes why they have no text annotations
- **AND** no notes or source lines are fabricated for them; a comparison with no eligible text targets fails before inference

## ADDED Requirements

### Requirement: Working-tree review from ordinary code

Explicit review outside Diffview SHALL open a repository-wide HEAD-to-working-tree comparison for the originating named source's repository/worktree, using its effective working directory for an unnamed source. The review SHALL use the net current changes, including staged-only and unstaged edits, and the effective Diffview untracked policy. It SHALL NOT save buffers, alter the index, select an unrelated open view, or silently substitute another base.

#### Scenario: Staged and unstaged edits together
- **WHEN** one file differs only in the index, another only in the working tree, and a third has both staged and unstaged edits
- **THEN** an outside review explains their final working versions relative to HEAD in one coherent comparison
- **AND** it does not concatenate HEAD-to-index and index-to-working patches

#### Scenario: Unstaged edit undoes a staged edit
- **WHEN** a staged change is completely undone in the working tree so that the final file matches HEAD
- **THEN** that change is absent from the HEAD-to-working-tree review, even though Git still reports separate staged and unstaged differences

#### Scenario: File repository differs from editor directory
- **WHEN** the originating named source belongs to a different repository or linked worktree than the current directory
- **THEN** the opened comparison belongs to that source's worktree and uses its HEAD
- **AND** another open Diffview tab does not redirect the request

#### Scenario: Unnamed source
- **WHEN** review is requested from an unnamed ordinary source
- **THEN** the repository is resolved from that source window's effective working directory
- **AND** unnamed text is not invented as a repository file

#### Scenario: Unsaved text and untracked files
- **WHEN** a working-side file already in the comparison has unsaved buffer edits, or the view includes untracked files
- **THEN** collection preserves the existing unsaved-overlay and untracked-file contracts without saving or staging
- **AND** it does not promise discovery of unsaved-only files absent from Diffview's manifest or inclusion of ignored/untracked files excluded by the effective policy

#### Scenario: No usable comparison
- **WHEN** Git or Diffview is unavailable, the source has no repository, HEAD is unresolved, the view is unsupported, or no eligible text changes exist
- **THEN** the plugin reports the specific limitation without inference or fallback to a staged, empty-tree, or unrelated comparison

### Requirement: Owned comparison opening

Opening a review comparison SHALL be a nonblocking, cancellable pending operation tied to its originating request and new view. Inference SHALL wait for coherent source panes with the intended repository and revision pair. Duplicate invocations and readiness events SHALL NOT create duplicate views or review requests. Cancellation, closure, timeout, or incompatible replacement SHALL retire the operation and its callbacks without changing unrelated views.

#### Scenario: Delayed buffers and repeated events
- **WHEN** a new Diffview layout exists before its source buffers load and readiness events repeat
- **THEN** the action remains pending until a coherent HEAD-to-working-tree comparison is available, then submits exactly one review request through the normal pipeline
- **AND** automatic file explanation does not race the pending explicit review

#### Scenario: Conflicting defaults or selection
- **WHEN** Diffview defaults or initial selection produce a staged entry, path-limited view, or a different revision pair
- **THEN** the action establishes and validates the intended repository-wide HEAD-to-working-tree comparison or fails explicitly before inference

#### Scenario: Cancel or close while opening
- **WHEN** ExplainrCancel, ExplainrClose, or source/view closure occurs before readiness
- **THEN** pending opening work is retired and late callbacks cannot start inference or reopen an explanation pane
- **AND** cancelling Explainr leaves an already-open Diffview view available for ordinary use

#### Scenario: Repeated review request
- **WHEN** the same review is requested again while its view is opening, including from the newly opened view
- **THEN** the request joins the existing pending action rather than opening another tab or issuing a second review

#### Scenario: View or comparison replaced
- **WHEN** the owned view closes or changes to a different comparison before readiness
- **THEN** the pending action is cancelled rather than following the replacement
- **AND** navigation alone within the intended comparison does not retarget or duplicate the review

#### Scenario: Capture after opening
- **WHEN** an outside review reaches readiness
- **THEN** collection captures the coherent comparison at that point using the configuration captured at invocation
- **AND** subsequent freshness, queue, cache, and failure rules are those of an ordinary explicit review request
