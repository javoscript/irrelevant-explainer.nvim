## MODIFIED Requirements

### Requirement: Budgeted context strategies with focused output

context.diff SHALL support auto (default), review and focused for file/hunk requests. Auto SHALL supply the whole coherent review when it fits, falling back to explicitly reduced coverage on budget overflow. Review SHALL require complete coverage or fail. Focused SHALL always reduce optional context. File/hunk requests SHALL restrict note anchors to their selected target. Explicit review scope SHALL require complete job-wide coverage regardless of context.diff, using bounded requests whose note anchors are restricted to their assigned file/range targets.

#### Scenario: Related changes outside the visible file
- **WHEN** the user explains a policy hunk while a controller and tests are changed elsewhere in the same comparison and the whole review fits
- **THEN** all three files' patches are supplied as context while line-aligned notes target only the selected policy hunk

#### Scenario: Automatic reduction
- **WHEN** the whole review exceeds context.max_bytes in auto mode for a file/hunk request
- **THEN** the request includes the selected target with focused coverage, and prompt/status disclose that omitted files and gaps are unavailable to the model

#### Scenario: Strict complete review
- **WHEN** a file/hunk request uses context.diff=review and any required review content cannot fit or be collected
- **THEN** collection fails without dropping files or pretending that partial context is a complete review

#### Scenario: Review scope with focused configuration
- **WHEN** the user explicitly requests review scope with context.diff set to focused or auto
- **THEN** that job still requires complete coverage across bounded requests and cannot fall back to selected-file coverage
- **AND** subsequent file/hunk requests retain their configured strategy

### Requirement: Decision documents as context

Review coverage SHALL include complete changed text versions, including decisions, docs and tests. File/hunk review-context requests SHALL retain patches; explicit review jobs SHALL supply exact source ranges and hunk coordinates without redundant patch text. Focused coverage SHALL prioritize affordable complete changed OpenSpec/ADR/decision/requirements documents deterministically by path, not semantic search. Unchanged repository documents SHALL not be explored automatically. Repository content SHALL remain untrusted data rather than instructions authorizing agent actions.

#### Scenario: Business rule in an OpenSpec change
- **WHEN** a review adds an owner-only cancellation requirement in an OpenSpec artifact and an ownership check in code
- **THEN** complete artifact text is supplied across annotation units, and affordable supporting requirement excerpts accompany related annotation or synthesis requests
- **AND** those requests ask the agent to relate the ownership check to the supplied requirement without claiming unseen rationale

#### Scenario: Rationale outside changed document lines
- **WHEN** a supplied changed ADR changes one paragraph but an unchanged paragraph explains the constraint behind the code change
- **THEN** the complete relevant document version, including unchanged rationale, is supplied in the request or across the explicit review job's annotation units
- **AND** a later citation to that paragraph is valid only when its original text is supplied to the citing invocation

#### Scenario: Instructions embedded in a changed file
- **WHEN** a changed document tells an agent to ignore its output contract or execute a command
- **THEN** the prompt identifies repository content as untrusted contextual data, not controlling instructions

### Requirement: Hunk and file explanation focus

Explainr SHALL support file (default), hunk, and review scope in Diffview sources. Hunk scope SHALL select exact changed spans at the invocation cursor, including zero-line insertion/deletion boundaries, and reject ambiguous/unchanged positions. File prompts and review annotation units SHALL prioritize their supplied changed hunks, permitting unchanged target sections when their connection to changes is explained. Regular diff summaries SHALL prefer the first changed line within their anchor.

#### Scenario: Whole-file multi-hunk explanation
- **WHEN** a file-scoped request or a review file target contains several separated hunks
- **THEN** all hunks are supplied in that request or across the review file's units, with prompts asking for meaningful behavior changes rather than a generic walkthrough of unchanged code

#### Scenario: Relevant unchanged dependency
- **WHEN** an unchanged function or import within the assigned target explains a changed hunk's effects
- **THEN** the prompt allows an additional note there with an explicit connection to the change, while other supplied files remain evidence rather than annotation targets for that note

#### Scenario: Range starts before the changed line
- **WHEN** a regular note's anchor includes an unchanged header followed by changed code
- **THEN** its summary sits beside the first actual changed line within its anchor

#### Scenario: Hunk outside a source pane
- **WHEN** hunk scope is requested from an ordinary source or Diffview file panel
- **THEN** the plugin reports that a coherent Diffview source pane is required without opening a view, guessing a hunk, or substituting a cached answer

### Requirement: Diff file-purpose overview request

File-scoped requests and review units supplying complete file versions SHALL ask for a short first overview of file purpose and the overall purpose of its changes. A returned kind=overview note SHALL display at the file start and cover that file's whole-file target anchors unchanged, using available sides and exact renamed paths. Hunk and fragment units SHALL not request or accept a whole-file overview. Overview existence or semantic quality SHALL not be fabricated or treated as schema-guaranteed.

#### Scenario: Both versions have text
- **WHEN** file scope or a whole-file review unit has supplied old and new textual targets
- **THEN** the overview instruction asks for both whole-file anchors, and focusing a valid returned overview emphasizes both complete versions

#### Scenario: Added or deleted file
- **WHEN** only one version has valid target text
- **THEN** the overview uses only that side, not an invented absent/empty/binary anchor

#### Scenario: Multiple file overviews in a review
- **WHEN** two whole-file review units each return one valid overview matching their available anchors
- **THEN** both are accepted and displayed only with their respective files, independently of the whole-change narrative

#### Scenario: Oversized file is split
- **WHEN** a file requires several range units
- **THEN** its range notes can complete coverage without a whole-file overview, and no fragment is mislabeled as a whole-file explanation

### Requirement: Complete-context budget

Every complete serialized prompt SHALL fit context.max_bytes (default 262144 UTF-8 bytes) before inference. File/hunk review coverage SHALL fail on overflow; auto/focused file/hunk requests SHALL omit optional context explicitly, never truncate a required target or substitute an AI summary. Explicit review SHALL use separately bounded snapshot capture and per-invocation planning, preserving complete job-wide coverage. Missing required versions and indivisible-input/overhead overflow SHALL fail actionably. Bytes SHALL not be claimed as provider tokens.

#### Scenario: Review exceeds budget
- **WHEN** an explicit review snapshot exceeds one prompt's budget but fits the local snapshot cap and can be partitioned
- **THEN** the host plans bounded annotation and synthesis requests without omitting required source ranges
- **AND** a file/hunk request with context.diff=review still fails on its own complete-prompt overflow rather than becoming a multi-call review

#### Scenario: Required version cannot be read
- **WHEN** a textual file version required for the comparison cannot be collected
- **THEN** the plugin reports the missing content and does not claim to have supplied the whole comparison

#### Scenario: Focused target is still too large
- **WHEN** the selected file/hunk plus mandatory request overhead cannot fit after optional coverage is reduced
- **THEN** inference does not start and the error identifies that the target was not truncated

#### Scenario: Indivisible review input
- **WHEN** one source line with mandatory instructions and metadata cannot fit an annotation request, or the full snapshot exceeds its admission cap
- **THEN** planning fails before annotation inference, identifying the relevant limit without truncating code or changing the selected comparison

### Requirement: Whole-comparison explanation scope

Explainr SHALL support explicit review scope through the command and explain() Lua API. One uncached review action SHALL own a bounded sequence of external invocations obtaining a whole-change narrative and file explanations for every eligible text entry in the exact comparison. An outside-review action SHALL enter the same job/cache pipeline after the existing owned comparison opening reaches readiness, preserving invocation-time configuration and capture-time content. File SHALL remain the default scope. Review generation SHALL not start automatically on navigation, and reading completed file details SHALL require no further inference. ExplainrReview SHALL remain display-only and SHALL NOT open a comparison or launch a job.

#### Scenario: Explain the selected comparison once
- **WHEN** the user runs `:Explainr review` or `require("explainr").explain("review")` in a supported comparison with three eligible files and no matching completed answer
- **THEN** one job captures all three targets and obtains their notes plus a cross-file narrative through bounded requests
- **AND** reading any of those returned files or expanding its detail requires no additional inference

#### Scenario: Trigger Review from the file tree
- **WHEN** the user invokes Explainr review or display-only ExplainrReview from the live DiffviewFiles panel
- **THEN** the action uses the currently displayed comparison's source panes without requiring a source cursor or changing tree focus/selection
- **AND** file/hunk requests retain their source-pane requirement

#### Scenario: Outside review hands off to batching
- **WHEN** Explainr review from ordinary code opens its intended HEAD-to-working-tree comparison and no completed cache entry matches the freshly captured inputs
- **THEN** exactly one job enters the normal pipeline using invocation-time AI/context/review/cache configuration, even if readiness events or equivalent opening requests repeat
- **AND** it captures the net staged-plus-unstaged contents at readiness, preserving the resolved worktree, effective untracked policy and manifest-only unsaved overlays without saving or staging
- **AND** Auto remains suppressed through handoff and between job phases

#### Scenario: Opening is retired before handoff
- **WHEN** cancellation, source/view closure, timeout or incompatible replacement retires an outside-review opening
- **THEN** its late callbacks cannot start collection, install a cached answer, or launch annotation or synthesis
- **AND** accepted unrelated explanations and any already-open Diffview tab remain governed by the existing opening contract

#### Scenario: Filtered or staged comparison
- **WHEN** Diffview has path filters or a selected staged rather than working set
- **THEN** review scope uses that exact comparison throughout all phases, not unrelated repository changes or a merged staged/working set

#### Scenario: Metadata-only files
- **WHEN** a supported review contains text files together with binary or both-empty entries
- **THEN** the complete manifest retains those entries and exposes why they have no text annotations
- **AND** no notes or source lines are fabricated for them; a comparison with no eligible text targets fails before inference

### Requirement: Whole-change narrative content

Review synthesis SHALL request an overall change explanation, cross-file relationships, and intent or caveats grounded in supplied findings and original source evidence. The narrative SHALL distinguish documented, inferred, and unknown intent, require supplied evidence for documented claims, and reference only supplied comparison files. It SHALL remain separate from source-anchored file notes and disclose distributed-context limitations rather than claiming one model saw every source line together.

#### Scenario: Requirement implemented across files
- **WHEN** supplied changes include a requirement, policy implementation, caller, and tests
- **THEN** synthesis asks how their findings and supplied source evidence relate, identifies visible mismatches, and distinguishes test expectations from evidence of tests having run

#### Scenario: Rationale is absent
- **WHEN** supplied code reveals an effect but not its motivation
- **THEN** the narrative request permits unknown intent and requires proposed rationale to be labeled inferred rather than documented

#### Scenario: Derived finding is not primary evidence
- **WHEN** an annotation finding asserts a documented rationale without source text supplied to the synthesis invocation
- **THEN** that assertion alone cannot justify a documented narrative claim or an unseen source citation

### Requirement: Per-file retention during the current run

Completed batches SHALL be retained in memory by repository, comparison/filter and file for the current Neovim run, including off-screen completions and review-generated file results. Navigation SHALL hide old notes and exit file detail without cancelling old-file requests or marking answers stale. Returning SHALL revalidate original target/coverage and restore valid batches without inference, accepting recreated clean buffers with identical content. Completed results SHALL also be eligible for validated cross-session caching.

#### Scenario: Return to an explained file
- **WHEN** the user explains two hunks, visits another file and returns without content changes
- **THEN** both accepted batches are restored with no extra AI call or navigation-only stale warning

#### Scenario: Visit an unexplained file
- **WHEN** the newly selected file has no saved explanations or pending request and auto-explanation is disabled
- **THEN** the pane shows an empty unexplained state rather than the previous file's notes or a false stale message

#### Scenario: Real context changed while away
- **WHEN** saved file or decision/index/revision context changed before returning
- **THEN** restoration rejects affected saved batches instead of trusting old window IDs or cached answers

#### Scenario: File finishes while hidden
- **WHEN** A completes successfully while B is selected and the user later returns to unchanged A
- **THEN** A's saved answer is displayed after freshness validation without another external invocation

## ADDED Requirements

### Requirement: Cross-session diff result reuse

Completed diff-file, diff-hunk and whole-review requests SHALL support persistent exact-input reuse after restart. Identity SHALL include source namespace, scope, side-specific versions/paths/EOF and presence, resolved comparison/filter, supplied context and generation identity. Whole-review reuse SHALL retain complete coverage and shared evidence dependencies, independent of the selected display file. Persistence SHALL not create automatic review generation on navigation.

#### Scenario: Repeat each diff scope after restart
- **WHEN** a new Neovim process requests an identical file, hunk or whole-review target with matching supplied context and generation identity
- **THEN** a validated persistent result satisfies that scope without external calls
- **AND** a review hit restores its narrative and every eligible file result together, without rerunning annotation or synthesis

#### Scenario: Comparison metadata differs
- **WHEN** the visible patch matches but revision pair, staged/working set, filter, rename paths, EOF or absent/empty-side semantics differ
- **THEN** the previous entry is not reused as that comparison's answer

#### Scenario: Changed shared evidence
- **WHEN** a review's code hunks match but a supplied decision document changes
- **THEN** the completed review and its distributed file answers cannot reuse the old shared context

#### Scenario: Display selection changes
- **WHEN** the same complete review is requested with a different Diffview file selected
- **THEN** selection alone does not prevent reuse or force additional inference

#### Scenario: Equivalent manual and automatic opening
- **WHEN** a completed review from a manually opened HEAD-to-working-tree view is requested through outside-review opening after restart, or vice versa, with the same resolved namespace, comparison, supplied content and generation settings
- **THEN** after coherent capture and validation the completed narrative and every file result are reused atomically without annotation or synthesis calls
- **AND** the opening method, original ordinary-source window and selected display file do not change the cache key

### Requirement: Exact review unit coverage

Explicit reviews SHALL assign every available old/new text line of each eligible file to exactly one annotation unit, with optional overlapping context tracked separately. Units SHALL retain original coordinates and file identities. Completion SHALL require successful acknowledgement of every assigned unit, not merely one result per file. Coverage accounting SHALL not be presented as proof of semantic correctness.

#### Scenario: Large multi-hunk file with unequal sides
- **WHEN** old and new versions have different lengths and several hunks, including a hunk too large for one request
- **THEN** units preserve all side-specific intervals and fragment boundaries without gaps, duplicate ownership, or invented old/new pairings
- **AND** the complete manifest remains associated with the job while each invocation discloses only its supplied ranges

#### Scenario: Missing fragment despite a returned file
- **WHEN** a file has three assigned units but only two successfully validate
- **THEN** the file and review remain incomplete even if both returned units contain notes for that file

#### Scenario: Empty notes are not missing work
- **WHEN** a validated unit explicitly returns an empty notes array
- **THEN** that unit counts as processed without fabricating an annotation

### Requirement: Bounded evidence-grounded synthesis

Synthesis SHALL obey the same per-invocation limits as annotation. Oversized finding sets SHALL use bounded reduction with preserved child coverage and original cited source excerpts. Each reduction SHALL reduce the serialized findings/evidence input required by the next level. Unsplittable packets, nonreducing output, or exhausted call limits SHALL fail explicitly without unbounded recursion or oversized final requests.

#### Scenario: Findings exceed the synthesis budget
- **WHEN** all validated annotation findings and their evidence cannot fit one synthesis prompt
- **THEN** bounded reduction processes all child results before final narrative synthesis, preserving exact source citation provenance through every level
- **AND** final synthesis does not request all file notes again

#### Scenario: Evidence exceeds a request
- **WHEN** an indivisible finding plus its cited original source cannot fit, or reduction does not decrease the next level's required bytes
- **THEN** the job stops with a synthesis-budget diagnostic and retains matching validated checkpoints rather than dropping evidence or looping

#### Scenario: Citation to another unit's unseen range
- **WHEN** a reduction or synthesis response cites valid local snapshot lines that were not supplied in that invocation
- **THEN** the response is rejected despite those lines having appeared in an earlier annotation request

### Requirement: Explicit review resume and bounded ownership

Explicit review in its owning comparison or reader SHALL resume matching validated in-memory checkpoints after freshness checks; Review Refresh SHALL bypass them. Checkpoints SHALL remain owner-local. One job SHALL own one queue slot with sequential invocations. Failure SHALL advance queued explicit work without repair. Cancel SHALL stop scheduling but retain validated checkpoints; closure or stale/replaced comparison SHALL discard them.

#### Scenario: Resume after an annotation failure
- **WHEN** two annotation requests validate and a third fails, then the user repeats Explainr review in that comparison or its reader for unchanged content and configuration
- **THEN** the successful requests are reused and only failed or unstarted work is invoked before synthesis
- **AND** the failed invocation's partial items are not salvaged as checkpoints

#### Scenario: New outside review is not another owner's resume
- **WHEN** an unfinished job belongs to an existing comparison and the user requests review from ordinary code after opening has completed
- **THEN** the command opens its new comparison under the existing contract without adopting the other owner's unfinished checkpoints
- **AND** only a matching completed answer is eligible for cross-owner reuse; repeated requests while the new comparison is still opening coalesce rather than creating jobs or resuming checkpoints

#### Scenario: Synthesis fails after annotations finish
- **WHEN** annotations validate but synthesis fails and the user explicitly resumes the same job
- **THEN** matching annotation and successful reduction checkpoints are reused without regenerating their file details

#### Scenario: Refresh versus resume
- **WHEN** the user invokes ExplainrRefresh in Review
- **THEN** all phases regenerate without reusing unfinished-job checkpoints or the previous completed review
- **AND** a File-mode refresh retains its existing file/hunk scope

#### Scenario: Navigation and queued manual work
- **WHEN** a review runs, the user navigates to another file, and explicitly queues a hunk request
- **THEN** the review continues for its captured comparison with at most one active invocation, and the hunk runs after the review succeeds or fails
- **AND** navigation automation cannot start duplicate file work between review phases

#### Scenario: Cancel between phases
- **WHEN** the user cancels after annotation validation but before synthesis dispatch
- **THEN** no synthesis process starts, late callbacks cannot checkpoint or install, and only already validated work remains eligible for explicit resume

#### Scenario: Relevant content or configuration changes
- **WHEN** a changed decision document, unsaved buffer, comparison/filter, command, decoder, protocol, or planning limit no longer matches an unfinished job
- **THEN** its checkpoints are not reused as current results
- **AND** navigation alone with identical content does not invalidate them
