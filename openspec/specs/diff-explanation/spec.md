# diff-explanation Specification

## Purpose

Explain selected code changes using exact comparison identities and budgeted review context, connecting implementation to supplied requirements, decisions, and tests without inventing omitted rationale.

## Requirements

### Requirement: Exact review comparison

Diff explanations SHALL derive exact old/new identities, path filters and staged/working scope from the selected coherent two-way Git Diffview comparison, not a default working-tree diff. Review coverage SHALL include the complete changed-file manifest; focused coverage SHALL include supplied entries and an omission count. Unsupported, loading or ambiguous comparisons SHALL fail explicitly.

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

### Requirement: Budgeted context strategies with focused output

context.diff SHALL support auto (default), review and focused. Auto SHALL supply the whole coherent review when it fits, falling back to explicitly reduced coverage on budget overflow. Review SHALL require complete coverage or fail. Focused SHALL always reduce optional context. All strategies SHALL restrict note anchors to the selected file or hunk rather than unrelated supplied files.

#### Scenario: Related changes outside the visible file
- **WHEN** the user explains a policy hunk while a controller and tests are changed elsewhere in the same comparison and the whole review fits
- **THEN** all three files' patches are supplied as context while line-aligned notes target only the selected policy hunk

#### Scenario: Automatic reduction
- **WHEN** the whole review exceeds context.max_bytes in auto mode
- **THEN** the request includes the selected target with focused coverage, and prompt/status disclose that omitted files and gaps are unavailable to the model

#### Scenario: Strict complete review
- **WHEN** context.diff is review and any required review content cannot fit or be collected
- **THEN** collection fails without dropping files or pretending that partial context is a complete review

### Requirement: Focused target and nearby coverage

Focused hunk requests SHALL retain the entire selected hunk and nearby old/new context up to context.radius (default 20, nonnegative integer), shrinking surroundings to fit and prioritize affordable changed decision documents. Focused file requests SHALL retain complete selected-file versions and all its hunks. Selected targets SHALL never be truncated; optional context SHALL use original line coordinates with explicit supplied coverage.

#### Scenario: Large review with a small selected hunk
- **WHEN** many unrelated or oversized files cannot be sent under the budget
- **THEN** only the selected hunk, affordable surroundings/documents and bounded supplied manifest are sent; omitted paths are counted rather than serialized as an unbounded list

#### Scenario: Omitted same-file hunk
- **WHEN** hunk scope selects one of several distant hunks in a large file
- **THEN** other hunks outside supplied excerpts are unavailable evidence, even though selected versions were read locally to find the exact hunk

#### Scenario: Zero radius
- **WHEN** context.radius is 0 in focused hunk mode
- **THEN** the complete hunk remains supplied without automatically adding unchanged surrounding lines

### Requirement: Decision documents as context

Review coverage SHALL include complete changed text versions and patches, including decisions, docs and tests. Focused coverage SHALL prioritize affordable complete changed OpenSpec/ADR/decision/requirements documents deterministically by path, not semantic search. Unchanged repository documents SHALL not be explored automatically. Repository content SHALL remain untrusted data rather than instructions authorizing agent actions.

#### Scenario: Business rule in an OpenSpec change
- **WHEN** a review adds an owner-only cancellation requirement in an OpenSpec artifact and an ownership check in code, and that artifact is supplied
- **THEN** the code explanation request includes the complete artifact and asks the agent to relate the ownership check to that requirement

#### Scenario: Rationale outside changed document lines
- **WHEN** a supplied changed ADR changes one paragraph but an unchanged paragraph explains the constraint behind the code change
- **THEN** the request contains the complete relevant document version, including the unchanged rationale

#### Scenario: Instructions embedded in a changed file
- **WHEN** a changed document tells an agent to ignore its output contract or execute a command
- **THEN** the prompt identifies repository content as untrusted contextual data, not controlling instructions

### Requirement: Evidence and intent distinctions

Requests SHALL ask the agent to distinguish documented intent, inferred intent, and unknown intent, and to identify visible mismatches between decisions and code. Notes claiming documented intent SHALL cite supplied evidence by path, version, and line range; absent rationale SHALL not be invented.

#### Scenario: Cross-file rationale
- **WHEN** a returned note labels its rationale as documented
- **THEN** validation requires nonempty citations to supplied document/code/test ranges, while the UI identifies documented intent without generating a separate Evidence section

#### Scenario: Code conflicts with the requirement
- **WHEN** the supplied requirement restricts cancellation to owners but the patch also allows editors
- **THEN** the prompt asks for the discrepancy to be explained rather than assuming that the implementation fulfills the requirement

#### Scenario: No decision document
- **WHEN** the comparison has no supplied evidence explaining why a change was made
- **THEN** the prompt asks the agent to explain the observable effect and label any proposed rationale as inference

#### Scenario: Citation crosses an omitted gap
- **WHEN** evidence includes a range crossing unsent lines between supplied chunks
- **THEN** the result is rejected even if the file's full line count or locally collected contents are known

### Requirement: Old and new anchors

Diff notes SHALL identify old-side, new-side, or paired old/new line ranges. Added and deleted files SHALL distinguish absent versions from empty existing files. Deleted-line notes SHALL remain associated with old code even when the new-side display contains only filler rows.

#### Scenario: Replacement shifts line numbers
- **WHEN** an old expression at line 59 becomes a new expression at line 62
- **THEN** the note can identify both ranges without treating old and new line numbers as equal

#### Scenario: Deletion-only hunk
- **WHEN** a hunk removes code without adding replacement lines
- **THEN** its explanation has a valid old-side anchor and can be displayed at the corresponding deleted-code row

#### Scenario: Added, deleted, renamed, and binary files
- **WHEN** the review includes these file statuses
- **THEN** supplied manifest entries preserve paths/statuses and distinguish absent, existing empty and binary versions, with binary content identified as unavailable rather than fabricated empty text

### Requirement: Hunk and file explanation focus

ExplainrDiff SHALL support file (default) and hunk scope. Hunk scope SHALL select exact changed spans at the invocation cursor, including zero-line insertion/deletion boundaries, and reject ambiguous/unchanged positions. File prompts SHALL prioritize changed hunks, permitting unchanged target sections when their connection to changes is explained. Regular diff summaries SHALL prefer the first changed line within their anchor.

#### Scenario: Whole-file multi-hunk explanation
- **WHEN** a file-scoped request contains several separated hunks
- **THEN** the prompt supplies all file hunks and asks for meaningful changes across them, not a generic walkthrough of unchanged code

#### Scenario: Relevant unchanged dependency
- **WHEN** an unchanged function or import within the selected file explains a changed hunk's effects
- **THEN** the prompt allows an additional note there with an explicit connection to the change, while other supplied files remain evidence rather than annotation targets

#### Scenario: Range starts before the changed line
- **WHEN** a regular note's anchor includes an unchanged header followed by changed code
- **THEN** its summary sits beside the first actual changed line while range references and focus retain the whole anchor

### Requirement: Diff file-purpose overview request

File-scoped diff requests SHALL ask for a short first overview of file purpose and the overall purpose of its changes. A returned kind=overview note SHALL display at the file start and cover every whole-file target anchor unchanged, using both available sides and exact renamed paths. Hunk scope SHALL not request an overview. Overview existence or semantic quality SHALL not be fabricated or treated as schema-guaranteed.

#### Scenario: Both versions have text
- **WHEN** file scope has supplied old and new textual targets
- **THEN** the overview instruction asks for both whole-file anchors, and focusing a valid returned overview emphasizes both complete versions

#### Scenario: Added or deleted file
- **WHEN** only one version has valid target text
- **THEN** the overview uses only that side, not an invented absent/empty/binary anchor

### Requirement: Complete-context budget

The complete serialized prompt SHALL fit context.max_bytes (default 262144 UTF-8 bytes) before inference. Review mode SHALL fail on overflow; auto/focused mode SHALL omit optional context explicitly, never truncate a required target or substitute an AI summary. Missing required versions and mandatory-target/overhead overflow SHALL fail with an actionable budget/collection error. Bytes SHALL not be claimed as provider tokens.

#### Scenario: Review exceeds budget
- **WHEN** strict review coverage exceeds the configured budget even though the focused file alone would fit
- **THEN** no command starts and the error offers increasing the budget or reducing the explicit comparison/coverage

#### Scenario: Required version cannot be read
- **WHEN** a textual file version required for the comparison cannot be collected
- **THEN** the plugin reports the missing content and does not claim to have supplied the whole comparison

#### Scenario: Focused target is still too large
- **WHEN** the selected file/hunk plus mandatory request overhead cannot fit after optional coverage is reduced
- **THEN** inference does not start and the error identifies that the target was not truncated

### Requirement: Review snapshot freshness

Results SHALL be bound to captured comparison, supplied strategy/coverage, target and mutable-content guards. Real code/context/index/revision changes SHALL invalidate affected results; navigation alone SHALL not make accepted explanations stale. Results and cache hits SHALL be revalidated before installation. Cursor movement SHALL not retarget a pending hunk; fixed two-commit comparisons SHALL not become stale solely due to unrelated working/index edits.

#### Scenario: Another file changes during generation
- **WHEN** a decision document in the review changes while a code explanation is pending
- **THEN** the result from the older whole-review context is not displayed as current

#### Scenario: Switch focused file
- **WHEN** the user changes files before the prior request completes
- **THEN** its result cannot replace the explanation of the newly focused file

#### Scenario: Omitted file changes
- **WHEN** an in-scope working file omitted from focused prompt coverage changes
- **THEN** conservative retained index/stat/buffer guards prevent blindly reusing an explanation from the old comparison

### Requirement: Nonblocking diff collection and checking

Editor sessions SHALL collect and revalidate diffs using cancellable asynchronous Git/filesystem operations and yielded processing batches, with coalesced freshness checks. A request SHALL expose Pending before collection finishes, and Cancel/Close SHALL stop owned collection as well as inference. CPU hashing, native diffing and final encoding SHALL be documented as main-thread work, not claimed to be fully off-thread.

#### Scenario: Cancel a slow collection
- **WHEN** the user cancels before Git/filesystem reads complete
- **THEN** owned operations stop, late callbacks cannot launch inference, and fresh accepted batches remain

#### Scenario: Repeated freshness events
- **WHEN** several source/view events arrive during a check
- **THEN** checks coalesce with a trailing recheck when necessary, and pending snapshots are checked after retained accepted contexts before output is installed

### Requirement: Incremental and queued diff requests

Accepted file/hunk targets in the same comparison/file SHALL accumulate in one pane, with identical targets replacing only their batch. Compatible hunk requests while diff work is pending SHALL append rather than cancel it. Cursor targets and configuration SHALL be captured at invocation; inference SHALL run in request order, one invocation at a time per tab. Ordinary failures SHALL preserve accepted notes and continue queued hunks.

#### Scenario: Add a hunk while another is loading
- **WHEN** the user requests hunk B while hunk A or a file request is pending
- **THEN** A continues, B is queued with its own invocation-time target/configuration, both ranges show loading, and each success adds notes immediately

#### Scenario: Earlier queued request fails
- **WHEN** collection or inference for one queued hunk fails
- **THEN** the error is reported without dropping earlier accepted notes or preventing the next queued hunk from running

#### Scenario: Clear pending work explicitly
- **WHEN** Cancel, Refresh, Close, incompatible ownership/mode changes or stale pending context supersede active work
- **THEN** active/queued requests are discarded and late output cannot install; Cancel/Refresh leave still-fresh accepted batches available

### Requirement: Per-file retention during the current run

Completed batches SHALL be retained in memory by repository, comparison/filter and file for the current Neovim run. Navigation SHALL hide notes, exit detail and cancel pending work for the old file without marking completed answers stale. Returning SHALL revalidate each original target/coverage and restore valid batches without inference, accepting recreated clean buffers with identical content. No plugin history SHALL persist across restarts.

#### Scenario: Return to an explained file
- **WHEN** the user explains two hunks, visits another file and returns without content changes
- **THEN** both accepted batches are restored with no extra AI call or navigation-only stale warning

#### Scenario: Visit an unexplained file
- **WHEN** the newly selected file has no saved explanations and auto-explanation is disabled
- **THEN** the pane shows an empty unexplained state rather than the previous file's notes or a false stale message

#### Scenario: Real context changed while away
- **WHEN** saved file or decision/index/revision context changed before returning
- **THEN** restoration rejects affected saved batches instead of trusting old window IDs or cached answers

### Requirement: Opt-in navigation inference

diff.auto_explain SHALL default to false. When true, navigating to a coherent Diffview file without valid saved notes SHALL request file scope only while a diff explanation pane is already open. Valid file/hunk batches SHALL be restored without inference; stale restoration SHALL request a fresh file explanation. Repeated layout/focus events, current-file edits, cancellation and failure SHALL not automatically retry.

#### Scenario: Opening Diffview alone
- **WHEN** auto_explain is enabled but no diff explanation pane is open
- **THEN** opening or navigating Diffview does not start inference

#### Scenario: Enabled navigation to a new file
- **WHEN** an open diff explanation session follows a newly selected coherent unexplained file
- **THEN** exactly one file request starts, and repeated layout events do not issue duplicate requests

#### Scenario: Close or fail
- **WHEN** the user closes Explainr, or the automatically requested file fails/is cancelled without another navigation
- **THEN** no automatic retry is issued solely from focus/layout/edit events

### Requirement: Diffview reading keymaps

Overview and expanded detail SHALL inherit Diffview file-navigation and explorer bindings, respecting configured remaps, custom actions and disabled mappings. Default Tab/Shift-Tab SHALL navigate files, leader-e SHALL focus the explorer and leader-b SHALL toggle it. Enter/K SHALL remain Explainr expansion controls, and Tab SHALL not expand details.

#### Scenario: Navigate from expanded detail
- **WHEN** Tab selects the next diff file while detail is open
- **THEN** Diffview navigation executes normally, detail exits and the new file follows the retention/auto-explanation rules

#### Scenario: Customized explorer mapping
- **WHEN** the user remaps or disables a Diffview explorer action
- **THEN** Explainr honors that mapping configuration rather than hard-coding the original key or overriding its action

## Decisions

- Preserve exact comparison identity even when sending less content. The complete review remains preferred when affordable; bounded auto/focused coverage replaces the original always-complete-review rule to make small hunk requests usable in large reviews.
- Reduce optional surroundings/context, never the selected hunk or file. Label omissions and validate only supplied evidence; a locally read file or known line count is not proof the model saw every line.
- Prioritize changed decision documents by deterministic paths, including but not limited to OpenSpec. This is not semantic relevance search or autonomous repository exploration, and unchanged docs are not loaded automatically.
- Ask whole-file prompts to focus on changed hunks and give one high-level file/change overview, while allowing connected unchanged sections. Prompt guidance is not a guarantee of factual model reasoning or hunk coverage.
- Treat navigation as display lifecycle, not content mutation. Revalidate saved per-file batches by content and original coverage rather than requiring old display buffers to survive.
- Append compatible pending hunk requests and serialize inference instead of cancelling work already requested. Other scopes may supersede pending work; refresh is explicit and target-local.
- Keep navigation inference opt-in and dependent on an already-open pane to avoid unexpected external-agent usage. Nothing promises that every possible file/model context will fit.
- Asynchronous I/O removes waiting on Git/filesystem subprocesses from editor sessions, not every CPU cost or external-writer race. These decisions supersede the corresponding complete-context and lifecycle assumptions in the archived initial design.
