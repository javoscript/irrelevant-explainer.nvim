# Spec Delta

## ADDED Requirements

### Requirement: Whole-comparison explanation scope

ExplainrDiff SHALL support explicit review scope through the command and Lua API. One uncached successful review request SHALL use one external invocation to obtain a whole-change narrative and file explanations for every eligible text entry in the exact comparison. File SHALL remain the default scope. Review generation SHALL not start automatically on navigation.

#### Scenario: Explain the selected comparison once
- **WHEN** the user runs `:ExplainrDiff review` or `require("explainr").diff("review")` in a supported comparison with three eligible files
- **THEN** one request supplies all three file targets and requests the narrative plus their notes
- **AND** reading any of those returned files or expanding its detail requires no additional inference

#### Scenario: Trigger Review from the file tree
- **WHEN** the user invokes ExplainrDiff review or display-only ExplainrReview from the live DiffviewFiles panel
- **THEN** the action uses the currently displayed comparison's source panes without requiring a source cursor or changing tree focus/selection
- **AND** file/hunk requests retain their source-pane requirement

#### Scenario: Filtered or staged comparison
- **WHEN** Diffview has path filters or a selected staged rather than working set
- **THEN** review scope uses that exact comparison, not unrelated repository changes or a merged staged/working set

#### Scenario: Metadata-only files
- **WHEN** a supported review contains text files together with binary or both-empty entries
- **THEN** the complete manifest retains those entries and exposes why they have no text annotations
- **AND** no notes or source lines are fabricated for them; a comparison with no eligible text targets fails before inference

### Requirement: Whole-change narrative content

Review prompts SHALL request an overall change explanation, cross-file relationships, and intent or caveats grounded in supplied context. The narrative SHALL distinguish documented, inferred, and unknown intent, require supplied evidence for documented claims, and reference only supplied comparison files. It SHALL remain separate from source-anchored file notes.

#### Scenario: Requirement implemented across files
- **WHEN** supplied changes include a requirement, policy implementation, caller, and tests
- **THEN** the prompt asks how their changes relate, identifies visible mismatches, and distinguishes test expectations from evidence of tests having run

#### Scenario: Rationale is absent
- **WHEN** supplied code reveals an effect but not its motivation
- **THEN** the narrative request permits unknown intent and requires proposed rationale to be labeled inferred rather than documented

### Requirement: Navigation-independent request capture

File, hunk, and review requests SHALL preserve their invocation-time comparison, target, and configuration through collection and generation. File navigation within the same comparison SHALL neither cancel nor retarget them. Off-screen validation SHALL not navigate Diffview or depend on the old display windows remaining attached to the requested file.

#### Scenario: Navigate before collection completes
- **WHEN** file A is requested and the user selects B while asynchronous collection is pending
- **THEN** collection continues for A and cannot collect B as A's target or fail solely because source buffers were replaced
- **AND** a real content/comparison race still prevents inference on an inconsistent snapshot

#### Scenario: Return before completion
- **WHEN** the user returns to A while its original request remains pending
- **THEN** the reader reconnects to that work without starting a duplicate invocation

### Requirement: Coalesced automatic navigation work

While another request runs, navigation automation SHALL retain at most one unstarted file candidate for the latest eligible selected file. Explicit requests SHALL remain queued independently and take priority over that candidate. A queued or active review SHALL suppress automatic file requests for its comparison. Failed or cancelled reviews SHALL not fan out into automatic retries.

#### Scenario: Rapid navigation with Auto enabled
- **WHEN** A is generating and navigation visits unexplained B then C before A finishes
- **THEN** A continues and only C remains as the unstarted automatic candidate
- **AND** B remains queued if the user explicitly requested it

#### Scenario: Explicitly request an automatic candidate
- **WHEN** B has an unstarted automatic request and the user explicitly requests the same target and configuration
- **THEN** the request becomes explicit without duplication and later navigation does not discard it

#### Scenario: Review is pending
- **WHEN** a review is queued or running and the user navigates with Auto enabled
- **THEN** no automatic file invocation is added for that comparison
- **AND** review failure or cancellation leaves an actionable state without automatically requesting each file

### Requirement: Mode-aware explicit refresh

ExplainrRefresh SHALL clear active and queued work for the owning comparison and bypass answer reuse for the visible reader target. Review mode SHALL regenerate the narrative and all file results. File mode SHALL refresh its file or hunk target; a file result obtained from a review SHALL refresh as file scope. Still-fresh accepted results SHALL remain available while waiting.

#### Scenario: Refresh the narrative
- **WHEN** the user invokes Refresh while reading Review
- **THEN** a new complete-review request starts even if the comparison has a matching cached review

#### Scenario: Refresh a distributed file result
- **WHEN** the user navigates from Review to file A and invokes Refresh
- **THEN** only A is requested as file scope, not the whole review
- **AND** other valid completed files remain retained

## MODIFIED Requirements

### Requirement: Budgeted context strategies with focused output

context.diff SHALL support auto (default), review and focused for file/hunk requests. Auto SHALL supply the whole coherent review when it fits, falling back to explicitly reduced coverage on budget overflow. Review SHALL require complete coverage or fail. Focused SHALL always reduce optional context. File/hunk requests SHALL restrict note anchors to their selected target. Explicit review scope SHALL require complete coverage regardless of context.diff, with notes restricted to each declared file target.

#### Scenario: Related changes outside the visible file
- **WHEN** the user explains a policy hunk while a controller and tests are changed elsewhere in the same comparison and the whole review fits
- **THEN** all three files' patches are supplied as context while line-aligned notes target only the selected policy hunk

#### Scenario: Automatic reduction
- **WHEN** the whole review exceeds context.max_bytes in auto mode for a file/hunk request
- **THEN** the request includes the selected target with focused coverage, and prompt/status disclose that omitted files and gaps are unavailable to the model

#### Scenario: Strict complete review
- **WHEN** context.diff is review and any required review content cannot fit or be collected
- **THEN** collection fails without dropping files or pretending that partial context is a complete review

#### Scenario: Review scope with focused configuration
- **WHEN** the user explicitly requests review scope with context.diff set to focused or auto
- **THEN** that request still requires complete coverage and cannot fall back to selected-file coverage
- **AND** subsequent file/hunk requests retain their configured strategy

### Requirement: Hunk and file explanation focus

ExplainrDiff SHALL support file (default), hunk, and review scope. Hunk scope SHALL select exact changed spans at the invocation cursor, including zero-line insertion/deletion boundaries, and reject ambiguous/unchanged positions. File prompts and each review file target SHALL prioritize changed hunks, permitting unchanged target sections when their connection to changes is explained. Regular diff summaries SHALL prefer the first changed line within their anchor.

#### Scenario: Whole-file multi-hunk explanation
- **WHEN** a file-scoped request or a review file target contains several separated hunks
- **THEN** the prompt supplies all file hunks and asks for meaningful changes across them, not a generic walkthrough of unchanged code

#### Scenario: Relevant unchanged dependency
- **WHEN** an unchanged function or import within the selected file explains a changed hunk's effects
- **THEN** the prompt allows an additional note there with an explicit connection to the change, while other supplied files remain evidence rather than annotation targets for that file's result

#### Scenario: Range starts before the changed line
- **WHEN** a regular note's anchor includes an unchanged header followed by changed code
- **THEN** its summary sits beside the first actual changed line while range references and focus retain the whole anchor

### Requirement: Diff file-purpose overview request

File-scoped requests and each eligible review file target SHALL ask for a short first overview of file purpose and the overall purpose of its changes. A returned kind=overview note SHALL display at the file start and cover that file's whole-file target anchors unchanged, using available sides and exact renamed paths. Hunk scope SHALL not request an overview. Overview existence or semantic quality SHALL not be fabricated or treated as schema-guaranteed.

#### Scenario: Both versions have text
- **WHEN** file scope or a review file target has supplied old and new textual targets
- **THEN** the overview instruction asks for both whole-file anchors, and focusing a valid returned overview emphasizes both complete versions

#### Scenario: Added or deleted file
- **WHEN** only one version has valid target text
- **THEN** the overview uses only that side, not an invented absent/empty/binary anchor

#### Scenario: Multiple file overviews in a review
- **WHEN** a review response includes one valid overview in each of two different file results
- **THEN** both are accepted and displayed only with their respective files, independently of the whole-change narrative

### Requirement: Complete-context budget

The complete serialized prompt SHALL fit context.max_bytes (default 262144 UTF-8 bytes) before inference. Review coverage and explicit review scope SHALL fail on overflow; auto/focused file/hunk requests SHALL omit optional context explicitly, never truncate a required target or substitute an AI summary. Missing required versions and mandatory-target/overhead overflow SHALL fail with an actionable budget/collection error. Bytes SHALL not be claimed as provider tokens.

#### Scenario: Review exceeds budget
- **WHEN** strict review coverage or explicit review scope exceeds the configured budget even though one focused file would fit
- **THEN** no command starts and the error offers increasing the budget, reducing the explicit comparison, or requesting file/hunk scope
- **AND** the plugin does not silently split the review into multiple invocations

#### Scenario: Required version cannot be read
- **WHEN** a textual file version required for the comparison cannot be collected
- **THEN** the plugin reports the missing content and does not claim to have supplied the whole comparison

#### Scenario: Focused target is still too large
- **WHEN** the selected file/hunk plus mandatory request overhead cannot fit after optional coverage is reduced
- **THEN** inference does not start and the error identifies that the target was not truncated

### Requirement: Review snapshot freshness

Results SHALL be bound to captured comparison, supplied strategy/coverage, target and mutable-content guards, including off-screen completions and distributed review file results. Real code/context/index/revision changes SHALL invalidate affected results; navigation alone SHALL not make pending or accepted explanations stale. Results and cache hits SHALL be revalidated before installation. Cursor movement SHALL not retarget a pending hunk; fixed two-commit comparisons SHALL not become stale solely due to unrelated working/index edits.

#### Scenario: Another file changes during generation
- **WHEN** a decision document in the review changes while a code explanation or review is pending
- **THEN** results from the older whole-review context are not displayed as current, including per-file results distributed from that review

#### Scenario: Switch focused file
- **WHEN** the user changes files before the prior request completes
- **THEN** its result cannot replace the explanation of the newly focused file
- **AND** a valid result is retained for its original target without changing the selected file or focus

#### Scenario: Omitted file changes
- **WHEN** an in-scope working file omitted from focused prompt coverage changes
- **THEN** conservative retained index/stat/buffer guards prevent blindly reusing an explanation from the old comparison

#### Scenario: Recreated buffers and discarded unsaved text
- **WHEN** a requested file's display buffers are recreated during navigation
- **THEN** identical clean content does not invalidate its pending request solely because buffer identities changed
- **AND** changed or discarded relevant unsaved content prevents the old answer from being accepted as current

### Requirement: Incremental and queued diff requests

Accepted file/hunk targets SHALL accumulate per comparison/file; identical targets SHALL replace only their batch. Explicit file, hunk, and review requests in the same comparison SHALL queue without cancelling active work, deduplicating equivalent pending targets/configurations. Targets and configuration SHALL be captured at invocation. Explicit requests SHALL run in order with one invocation at a time per tab. Ordinary failures SHALL preserve accepted notes and continue queued work.

#### Scenario: Add a hunk while another is loading
- **WHEN** the user requests hunk B while hunk A or a file request is pending
- **THEN** A continues, B is queued with its own invocation-time target/configuration, both visible matching ranges show loading, and each success adds notes for its original target

#### Scenario: Earlier queued request fails
- **WHEN** collection or inference for a queued request fails
- **THEN** the error identifies that target without dropping earlier accepted notes or preventing the next queued request from running

#### Scenario: Clear pending work explicitly
- **WHEN** Cancel, Refresh, Close, incompatible comparison/code-mode ownership changes, or stale pending context supersede work
- **THEN** affected active/queued requests are discarded and late output cannot install; Cancel/Refresh leave still-fresh accepted batches available
- **AND** ordinary file navigation or Review/File switching does not constitute incompatible ownership

#### Scenario: Request another file explicitly
- **WHEN** A is running, the user navigates to B and requests B, then navigates to C
- **THEN** A continues and B remains explicitly queued; completion of either cannot overwrite C's notes

#### Scenario: Review results merge with previous work
- **WHEN** a validated review completes for files with existing full-file and distinct hunk batches
- **THEN** its file results replace identical full-file targets and preserve distinct still-valid hunk batches
- **AND** explicitly empty file results count as completed rather than unexplained

### Requirement: Per-file retention during the current run

Completed batches SHALL be retained in memory by repository, comparison/filter and file for the current Neovim run, including off-screen completions and review-generated file results. Navigation SHALL hide old notes and exit file detail without cancelling old-file requests or marking answers stale. Returning SHALL revalidate original target/coverage and restore valid batches without inference, accepting recreated clean buffers with identical content. No plugin history SHALL persist across restarts.

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

### Requirement: Opt-in navigation inference

diff.auto_explain SHALL default to false. When true, eligible navigation to a coherent unexplained Diffview file SHALL request or queue file scope only while a diff reader is open. Valid saved file/hunk results SHALL restore without inference; stale restoration SHALL request fresh file scope. Existing equivalent work or pending review coverage SHALL prevent duplication. Repeated layout/focus events, current-file edits, cancellation and failure SHALL not automatically retry.

#### Scenario: Opening Diffview alone
- **WHEN** auto_explain is enabled but no diff explanation pane is open
- **THEN** opening or navigating Diffview does not start inference

#### Scenario: Enabled navigation to a new file
- **WHEN** an open diff explanation session follows a newly selected coherent unexplained file without matching pending work or a pending review
- **THEN** exactly one automatic file request starts or becomes the coalesced candidate, and repeated layout events do not issue duplicates

#### Scenario: Close or fail
- **WHEN** the user closes Explainr, or the automatically requested file fails/is cancelled without another navigation
- **THEN** no automatic retry is issued solely from focus/layout/edit events

### Requirement: Diffview reading keymaps

File overview, expanded detail, and Review SHALL inherit Diffview file-navigation and explorer bindings, respecting configured remaps, custom actions and disabled mappings. Default Tab/Shift-Tab SHALL navigate files, leader-e SHALL focus the explorer and leader-b SHALL toggle it. Enter/K SHALL remain File expansion controls; Review Enter SHALL follow a validated file reference. Tab SHALL not expand details or switch modes without file navigation.

#### Scenario: Navigate from expanded detail
- **WHEN** Tab selects the next diff file while detail is open
- **THEN** Diffview navigation executes normally, detail exits and the new file follows the retention/auto-explanation rules

#### Scenario: Customized explorer mapping
- **WHEN** the user remaps or disables a Diffview explorer action
- **THEN** Explainr honors that mapping configuration rather than hard-coding the original key or overriding its action

#### Scenario: Navigate from Review
- **WHEN** a Diffview action or explorer selection changes the file while Review is displayed
- **THEN** the pane switches to that file's File mode while retaining the narrative reading position and any pending generation

### Requirement: Navigation-only runtime mode changes

Enabling automation SHALL apply only to navigation after the toggle, not immediately request the current file or retry earlier navigation. Disabling SHALL prevent future automatic requests and discard unstarted automatic candidates without cancelling started work, clearing accepted notes, or disabling manual requests and saved-note restoration. Existing pane-open, coherent-buffer, background-tab, freshness, and no-retry rules SHALL remain in effect.

#### Scenario: Enable on an unexplained current file
- **WHEN** an open diff pane shows an unexplained file and the user enables automation without navigating
- **THEN** no automatic request starts, including on subsequent polling, layout, focus, or edit events
- **AND** navigating afterward to a coherent unexplained file becomes eligible for one automatic file request subject to queue and review deduplication

#### Scenario: Earlier navigation is still resolving
- **WHEN** a navigation that occurred while automation was disabled is still loading buffers or validating saved notes when the user enables automation
- **THEN** completing that earlier navigation does not issue an automatic request, even if saved notes are invalid
- **AND** a background-tab navigation from before enabling does not issue a request solely when the tab becomes active

#### Scenario: Disable before automatic work starts
- **WHEN** an enabled navigation is waiting for coherent buffers, stale-note validation, tab activation, or an inference slot and the user disables automation before a request starts
- **THEN** the unstarted automatic candidate is discarded and the deferred automatic request does not start
- **AND** the pane still follows the file and restores valid saved notes when available

#### Scenario: Disable during an active request
- **WHEN** an automatic explanation request has started and the user disables automation
- **THEN** that request is not cancelled by the toggle and may complete under the existing freshness checks
- **AND** navigating afterward to another unexplained file does not start an automatic request

#### Scenario: Manual requests and restoration remain available
- **WHEN** automation is disabled and the user explicitly requests or refreshes an explanation, or returns to a file with valid saved notes
- **THEN** manual requests work normally and saved notes are restored without inference
- **AND** toggling does not discard accepted notes or alter queued manual requests

#### Scenario: Code mode remains manual
- **WHEN** automation is enabled while a code explanation pane is open
- **THEN** ordinary buffer navigation and edits do not trigger automatic code explanation requests
