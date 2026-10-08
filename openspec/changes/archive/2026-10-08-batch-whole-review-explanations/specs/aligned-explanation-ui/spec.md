## MODIFIED Requirements

### Requirement: Review and background status

The diff-pane header SHALL identify active Review/File mode and distinguish selected-target pending work from background and queued work. Review SHALL show its job phase and validated annotation-unit count instead of file-note ordinals, retaining Auto when enabled. Counts SHALL reflect completed validated units, not estimated tokens, elapsed-time percentages, or claimed semantic coverage. Synthesis SHALL remain pending until atomic installation. Status updates SHALL not alter the editor statusline or reset reading state.

#### Scenario: Other file is still generating
- **WHEN** B is selected while A runs and B is queued
- **THEN** the header distinguishes B's queued state from background generation rather than displaying A's notes or indicating that B is already generating

#### Scenario: Whole-review request pending
- **WHEN** a review job is collecting, planning, annotating, reducing findings, or synthesizing its narrative
- **THEN** Review identifies the actual phase and shows validated annotation progress once its unit total is known
- **AND** one split file's completed fragment is counted as a unit, not presented as a fully explained file

#### Scenario: Opening precedes generation
- **WHEN** Explainr review from ordinary code is waiting for coherent Diffview sources
- **THEN** the existing pending-opening notification remains distinct from job progress, without a new source-bound reader or annotation count
- **AND** opening failure is reported as preflight failure, not a failed annotation unit

#### Scenario: Narrow Review header
- **WHEN** the Review pane cannot fit its full header
- **THEN** it prioritizes active mode and request state, plus Auto when those fit, over hints and descriptions
- **AND** File retains its existing count/Auto priorities and neither mode inserts a header into buffer content

#### Scenario: All annotations are complete
- **WHEN** every annotation unit has validated but synthesis remains pending
- **THEN** the header shows synthesis rather than Ready or 100% complete
- **AND** existing Review loading decorations remain active without rewriting accepted narrative text

#### Scenario: Resume validated work
- **WHEN** an explicit resumed review revalidates three checkpoints out of twelve annotation units
- **THEN** status starts with three validated units and advances only when additional complete responses validate
- **AND** progress transitions preserve mode, focus, source positions, expanded detail, and narrative scroll

## ADDED Requirements

### Requirement: Completed cache-hit status

Validated completed-result reuse SHALL use the existing cached-ready status in code and diff readers, including whole Review. Disk lookup SHALL not fabricate annotation or synthesis progress. Restoration SHALL preserve normal target ownership, note accumulation, focus and navigation behavior; a miss or invalid entry SHALL not display stale content as ready.

#### Scenario: Persistent answer restored
- **WHEN** a completed answer passes all validation after restart
- **THEN** the reader shows Ready with the cached marker and the appropriate notes or review narrative without a generation phase

#### Scenario: Opening resolves to a completed cache hit
- **WHEN** an outside review reaches readiness, captures the current comparison and validates a matching completed answer
- **THEN** opening transitions to cached-ready Review with the complete result, without fabricated annotation or synthesis progress
- **AND** late restoration follows normal ownership and focus rules rather than jumping back from another tab

#### Scenario: Entry fails validation
- **WHEN** a candidate entry is corrupt, stale or incompatible
- **THEN** no cached-ready state is shown for that entry, and normal generation status is used if a request proceeds

### Requirement: Actionable review job failures

Review failures SHALL identify the phase and failed unit/request, retain honest completed-unit status, and distinguish explicit resume from full Refresh. Limit failures SHALL identify the relevant limit and measured size/count when available. Diagnostics SHALL avoid dumping source or prompts. Failed or cancelled jobs SHALL not display checkpointed answers as a new complete review or automatically start replacement work.

#### Scenario: Annotation failure with retained checkpoints
- **WHEN** an annotation invocation fails after earlier invocations validate
- **THEN** the reader shows failure with completed-unit progress, and diagnostics direct the user to Explainr review in the owning comparison or reader to resume, or ExplainrRefresh in Review to regenerate
- **AND** earlier fresh accepted visible explanations remain available without implying that the new review succeeded

#### Scenario: Synthesis budget failure
- **WHEN** annotations complete but synthesis cannot fit an evidence packet or exhausts its call allowance
- **THEN** diagnostics identify synthesis and the exhausted bound rather than suggesting only an increase to context.max_bytes
- **AND** no partially assembled narrative replaces accepted content

#### Scenario: Background failure during file detail
- **WHEN** a review fails while the user reads accepted expanded File detail
- **THEN** the error and background status identify the review job without marking the accepted file notes failed, collapsing detail, stealing focus, or switching to Review
