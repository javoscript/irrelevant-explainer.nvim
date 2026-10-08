## MODIFIED Requirements

### Requirement: Structured payload contract

Code/file/hunk requests SHALL require one version=1 JSON object with notes, single-line nonempty summaries, nonempty detail, target-contained anchors, intent_basis and evidence. Code notes SHALL have one buffer anchor; diff notes SHALL have one old/new anchor or a paired range without duplicate sides. Empty note/evidence arrays SHALL be allowed except documented intent requires evidence. Review invocations SHALL use version-3 phase-specific envelopes with the same note rules for assigned units, not a monolithic version-2 wire response.

#### Scenario: Valid empty answer
- **WHEN** a successful code/file/hunk command returns version 1 with an empty notes array
- **THEN** validation accepts that result rather than inventing explanations

#### Scenario: Incompatible contract
- **WHEN** output has a version unsupported for the requested scope/phase, invalid anchor side/count, duplicate sides, multiline summary or missing required text
- **THEN** the result is rejected with an actionable validation error before any notes are rendered

#### Scenario: Legacy command compatibility
- **WHEN** existing plain, OpenCode, Codex, or custom-decoder commands serve code/file/hunk requests
- **THEN** their version-1 payload contract remains unchanged
- **AND** review requests explicitly advertise version 3 and their phase rather than interpreting a legacy flat or version-2 answer as complete review coverage

### Requirement: Structured review response

Each review invocation SHALL return one version=3 JSON object identifying its phase, request, and snapshot. Annotation SHALL return assigned unit notes and cited findings; reduction SHALL return cited findings and acknowledge assigned child results; synthesis SHALL return the narrative and acknowledge its assigned inputs. The final narrative SHALL retain nonempty single-line title/headings, nonempty Markdown sections, intent_basis, evidence, and unique valid file_ids. Documented sections SHALL require supplied source evidence; narrative sections SHALL have no anchors.

#### Scenario: Narrative relates several files
- **WHEN** a synthesis section cites supplied requirements and references two changed file identities
- **THEN** validation accepts valid cross-file evidence and references without inventing a whole-comparison anchor

#### Scenario: Unsupported narrative claim or reference
- **WHEN** a documented section has no evidence, cites lines not transmitted in that synthesis request, or references a file identity outside its supplied manifest
- **THEN** synthesis fails and the complete review is not installed

#### Scenario: Empty or malformed narrative
- **WHEN** synthesis title or sections are absent, sections is empty, or a section has invalid text, intent, or array fields
- **THEN** the response is rejected rather than synthesizing a narrative locally from file summaries

#### Scenario: Wrong request or phase
- **WHEN** a completed response carries another snapshot/request ID or returns a synthesis envelope to an annotation request
- **THEN** that response is rejected without advancing coverage or storing a checkpoint

#### Scenario: Findings are derived data
- **WHEN** reduction or synthesis receives earlier model findings
- **THEN** the prompt labels them as untrusted interpretations, supplies original source text for their citations, and prohibits tools or repository exploration just as annotation prompts do
- **AND** unavailable source is not authorized by a citation string or a summary alone

### Requirement: Complete per-file review coverage

Each annotation response SHALL acknowledge exactly every assigned unit ID with its notes array. Missing, duplicate, unknown, or metadata-only annotation targets SHALL reject that invocation. The assembled review SHALL contain exactly one entry per eligible file, with every required unit validated before completion. Explicit empty notes SHALL count as processed coverage, not semantic quality. Notes SHALL anchor only within their unit's assigned ranges and cite only source supplied to that invocation.

#### Scenario: Missing and explicitly empty files differ
- **WHEN** three eligible file units were supplied but the response acknowledges only two
- **THEN** validation rejects the response for missing unit coverage
- **AND** including the third unit with an empty notes array instead is structurally valid and does not fabricate notes

#### Scenario: Cross-file anchors are not cross-file evidence
- **WHEN** A's unit result anchors a note to B despite both files being supplied
- **THEN** the invocation is rejected
- **AND** citing B as supplied evidence for a note anchored within A remains valid

#### Scenario: Multiple independent file overviews
- **WHEN** two whole-file units each return one overview matching their complete available old/new anchors
- **THEN** both overviews validate independently
- **AND** duplicate overviews within one file, partial whole-file anchors, fragment-unit overviews, or mismatched rename paths reject the invocation

#### Scenario: Metadata-only entries
- **WHEN** binary or both-empty entries occur in the manifest but have no textual target
- **THEN** they can be referenced by narrative file_ids but cannot receive invented annotation units, notes entries, or anchors

#### Scenario: Metadata acknowledgement cannot hide a missing fragment
- **WHEN** a response names a valid file but omits one of its required range units
- **THEN** the host does not promote the file or review to complete coverage

### Requirement: Atomic review acceptance

The plugin SHALL install the assembled narrative and all file results together only after every required invocation completes successfully, coverage/schema validation passes, and the snapshot remains fresh. Valid earlier invocations SHALL be retained as internal checkpoints, not partially displayed new answers. Failed invocation output SHALL not be salvaged. Failure SHALL preserve previous fresh results, start no repair or provider fallback, and allow independently queued explicit requests to continue.

#### Scenario: Truncated provider output
- **WHEN** a provider returns truncated JSON, omits later units, reports failure after partial output, or times out
- **THEN** that invocation and the review fail explicitly without accepting an apparently complete narrative or partial items from that invocation
- **AND** the error identifies the phase and explicit resume option without starting additional review requests automatically

#### Scenario: One bad sibling
- **WHEN** two invocations validate but a third invocation contains one invalid range among otherwise valid items
- **THEN** none of the third invocation is checkpointed and none of the new review replaces visible retained data
- **AND** the first two invocations remain eligible for explicit resume under matching freshness/configuration checks

#### Scenario: Content changes before installation
- **WHEN** all output validates structurally but relevant comparison content changed during generation
- **THEN** the narrative, every file result, and unfinished checkpoints from that stale review are withheld from current display or reuse

#### Scenario: Annotation completion is not review completion
- **WHEN** every annotation unit validates but final synthesis is pending or failed
- **THEN** older fresh visible results remain available and no new complete-review state or distributed file result is installed

### Requirement: In-memory request reuse

Validated answers and serialized context SHALL be reusable only for matching content/target/coverage and captured agent/context configuration, including custom decoder identity. Cache hits SHALL pass freshness/output validation before installation. Explicit Refresh SHALL bypass answer reuse for the visible mode's target. Review file results SHALL retain shared comparison provenance. Completed answers SHALL also support persistent reuse; unfinished checkpoints SHALL remain memory-only. Provider prompt-cache discounts SHALL not be assumed.

#### Scenario: Repeat an unchanged target
- **WHEN** an already-validated matching request is repeated without refresh
- **THEN** a fresh matching cache hit can be installed through the normal batch replacement path without another invocation

#### Scenario: Change decoder or context settings
- **WHEN** the executable/output decoder or context configuration changes
- **THEN** old cached output is not treated as a matching answer merely because source text is unchanged, and unrelated fresh accepted batches remain available

#### Scenario: Repeat or reopen a review
- **WHEN** an identical review request is repeated with matching content and configuration
- **THEN** its narrative and file results can be reused after validation without another invocation
- **AND** display-only Review/File switching never starts inference, including when no reusable review exists

#### Scenario: Shared evidence changes
- **WHEN** a supplied decision document changes after review results have been distributed among files
- **THEN** those files' reuse checks retain the original shared coverage dependency rather than checking only their own source text

#### Scenario: Similar targets with different coverage
- **WHEN** a focused file or hunk request is pending after a whole review finishes
- **THEN** review notes do not satisfy that request merely because they mention the same file; reuse requires matching target, effective coverage, content, and captured configuration

## ADDED Requirements

### Requirement: Review resource limits

Review SHALL expose positive finite integer limits: request_max_bytes=65536, response_max_bytes=32768, max_snapshot_bytes=16777216, and max_requests=128 under review configuration. Each prompt SHALL fit both context.max_bytes and review.request_max_bytes. Responses SHALL fit the decoded JSON byte cap. The snapshot cap SHALL apply to canonical serialized review data; max_requests SHALL bound new external calls in each explicit run or resume, across every phase.

#### Scenario: Raising the old input limit
- **WHEN** context.max_bytes is increased above review.request_max_bytes
- **THEN** review invocations retain the smaller review-specific cap rather than growing into one oversized request

#### Scenario: Exact UTF-8 boundary
- **WHEN** a complete prompt or decoded response including multibyte text equals its effective byte cap
- **THEN** the size check accepts it, while a value one byte above is rejected without truncation
- **AND** prompt instructions, schemas, targets and evidence count toward the input cap

#### Scenario: Exhausted invocation allowance
- **WHEN** a run has already launched max_requests external calls and still has work remaining
- **THEN** it stops before another dispatch, keeps valid checkpoints, and requires a new explicit resume to authorize another bounded run
- **AND** resumed cache hits do not consume external-call allowance

#### Scenario: Invalid limit
- **WHEN** a review limit is zero, negative, fractional, infinite, or not numeric
- **THEN** setup rejects it rather than silently disabling the bound

### Requirement: Output-aware review planning

Review planning SHALL account for bounded note/finding/detail output as well as exact input bytes, publishing finite output allowances in each prompt and validating them in responses. Small inputs with many targets SHALL not imply unlimited combined output. Limits SHALL be described as host guardrails, not provider token counts, output-token controls, billing guarantees, or proof that external compaction cannot occur.

#### Scenario: Many tiny files
- **WHEN** many small file targets fit the input cap but their allocated notes/findings exceed the response allowance
- **THEN** the planner creates multiple annotation requests rather than requesting unbounded detail in one answer

#### Scenario: Model exceeds its allowance
- **WHEN** a successfully completed JSON response exceeds declared note/finding/detail or decoded-byte limits
- **THEN** the invocation fails without clipping notes, accepting partial JSON, or automatically retrying it with another provider

#### Scenario: Provider rejects a bounded request
- **WHEN** the external agent reports context overflow, compaction failure, or output truncation despite the local bounds
- **THEN** the error remains visible with phase/request size context and advice to reduce review limits or scope
- **AND** Explainr does not change external agent configuration or claim a model-capacity guarantee

### Requirement: Review checkpoint provenance

Internal checkpoints SHALL require successful process completion, phase/schema/size validation, exact transmitted-range validation, and snapshot ownership checks. Reuse SHALL match the whole comparison fingerprint, protocol/planning identity, request coverage, and captured AI/context/review configuration including decoder identity. Checkpoints SHALL remain process-local, bounded to the latest unfinished job per owner, and distinct from accepted visible answers.

#### Scenario: Failure overrides apparently valid items
- **WHEN** stdout contains valid unit JSON but the process exits nonzero or reports an error event
- **THEN** no part of that invocation becomes a checkpoint, regardless of decoder type

#### Scenario: Late completion after cancellation
- **WHEN** a callback from a cancelled invocation arrives after a resume or replacement begins
- **THEN** it cannot advance coverage, add a checkpoint, install notes, or launch the next phase

#### Scenario: Successful intermediate reduction
- **WHEN** a reduction validates and later synthesis fails
- **THEN** the reduction can be reused only with matching child results, source evidence and job configuration, without losing the transitive unit coverage it represents

#### Scenario: Close or restart
- **WHEN** the owning reader closes, its comparison is replaced, or Neovim exits
- **THEN** unfinished review checkpoints are discarded and no unfinished-job disk history or automatic background continuation is created
- **AND** independently persisted completed answers remain eligible for validated reuse

### Requirement: Persistent completed-result identity

Persistent reuse SHALL cover selection, code file, diff file, diff hunk and review. Keys SHALL identify exact source namespace, resolved mode/scope, normalized target, supplied content/coverage, comparison and generation identity. Modes/scopes SHALL NOT alias. Transient editor IDs, public entrypoint and comparison-opening method SHALL NOT affect identity. Hidden external configuration changes SHALL require explicit namespace invalidation or Refresh.

#### Scenario: Identical request after restart
- **WHEN** any supported scope is requested in a new process with identical semantic inputs and a valid completed entry
- **THEN** the plugin reuses the result without external inference after recapturing and validating current inputs

#### Scenario: Unified entrypoints share semantic identity
- **WHEN** Explainr review and explain("review") resolve identical source namespace, comparison, supplied content and generation settings, including through manual versus automatic Diffview opening
- **THEN** they resolve the same completed-result key after coherent capture and target resolution
- **AND** an equal file scope in code and diff modes does not resolve the same key merely because the source buffer or public command matches

#### Scenario: Same patch is insufficient
- **WHEN** patch text matches but supplied surrounding source, comparison metadata, or decision evidence differs
- **THEN** the old result is a miss

#### Scenario: Separate source namespaces
- **WHEN** equal content is requested from different repository worktrees or unrelated non-Git source roots
- **THEN** entries remain isolated rather than sharing by patch hash alone

#### Scenario: Generation identity changes
- **WHEN** command configuration, prompt/protocol/planner version, decoder key, user namespace or output-affecting settings change
- **THEN** earlier entries do not match the new request
- **AND** changing only a window ID, timestamp, timeout or cache size does not change semantic request identity

#### Scenario: Custom decoder lacks a stable key
- **WHEN** a custom decoder function is configured without an explicit stable cache decoder key
- **THEN** persistent reuse is disabled for it while existing in-memory identity checks continue
- **AND** documentation explains how to supply and invalidate the key when the decoder changes

### Requirement: Completed-result validation before reuse

Only successfully completed, validated results SHALL be persisted. Disk hits SHALL pass envelope/version, exact identity, output schema, anchor/evidence provenance and coverage validation against freshly captured inputs, then normal freshness/ownership checks. Review hits SHALL restore the complete narrative and all file results atomically. Missing, corrupt, incompatible, incomplete or oversized entries SHALL be misses, not partially accepted answers.

#### Scenario: Structurally plausible but invalid entry
- **WHEN** valid JSON contains wrong identity, unsupported schema, an out-of-range anchor, an unsupplied evidence citation or missing review coverage
- **THEN** it cannot install output and normal generation remains available

#### Scenario: Interrupted write or oversized input
- **WHEN** an entry is truncated or exceeds the permitted cache read size
- **THEN** it is rejected without unbounded decoding or a failed explanation request

#### Scenario: Cancel or edit during lookup
- **WHEN** disk lookup finishes after cancellation, source modification or ownership replacement
- **THEN** its result cannot install or dispatch superseded work

#### Scenario: Failure after valid partial review work
- **WHEN** annotations succeed but synthesis fails, or the command exits nonzero after producing JSON
- **THEN** no new completed persistent answer is created from that work

### Requirement: Private bounded local result storage

Completed answers SHALL use private local storage under Neovim's cache directory, bounded by a configurable total size with least-recently-used eviction. Persistence SHALL exclude full source snapshots, raw prompts, process streams and credentials; result prose can contain snippets and SHALL be documented as plaintext. Writes SHALL be atomic and safe across processes. Cache failures SHALL not fail valid explanations or block generation indefinitely.

#### Scenario: Concurrent readers and writers
- **WHEN** two Neovim processes read or replace the same entry
- **THEN** readers see a complete validated old or new record or a miss, never an installed partial record
- **AND** simultaneous misses may invoke the agent independently; inference deduplication across processes is not promised

#### Scenario: Retention bound
- **WHEN** storing a result would exceed cache.max_bytes, default 104857600
- **THEN** least-recently-used completed entries are pruned, and an individually oversized entry is skipped without losing the displayed answer
- **AND** temporary writes are bounded and cleaned up; eviction produces an ordinary miss on future requests

#### Scenario: Unsafe or unavailable cache path
- **WHEN** an owned entry path is symlinked/nonregular, permissions prohibit access, or maintenance contention exceeds its bounded wait
- **THEN** the cache operation is skipped without following the entry to an external location or blocking explanation generation
- **AND** operational failures produce bounded diagnostics without revealing source or credentials

#### Scenario: Local privacy
- **WHEN** Explainr creates cache directories and files on a system supporting Unix permissions
- **THEN** it uses owner-only access and never presents that protection as encryption

### Requirement: Persistent cache controls

Persistent caching SHALL default to enabled and support opt-out, a size limit and an explicit namespace. ExplainrCacheClear and the Lua equivalent SHALL clear plugin-owned completed disk entries and reusable memory answers while preserving displayed notes. Refresh SHALL bypass both answer caches and replace a prior persistent answer only after successful validation. Invalid cache configuration SHALL be rejected during setup.

#### Scenario: Disable persistence
- **WHEN** cache.enabled is false
- **THEN** no persistent reads or writes occur, while current-session accepted-note retention still works

#### Scenario: Refresh fails
- **WHEN** Refresh starts a new invocation but that invocation fails
- **THEN** the earlier valid persistent answer is not overwritten or deleted by the failed attempt

#### Scenario: Explicit clear during generation
- **WHEN** the user runs ExplainrCacheClear while a request is pending
- **THEN** completed entries and reusable memory answers are cleared without closing the reader or deleting unrelated files
- **AND** this process's pre-clear requests cannot repopulate the disk cache; other running processes may later create new entries
- **AND** unfinished review checkpoints remain governed by Cancel/Refresh, not completed-result cache clear

#### Scenario: Invalid cache options
- **WHEN** enabled is not boolean, max_bytes is not a positive finite integer, or namespace or an explicitly supplied decoder_key is empty or not a string
- **THEN** setup reports the invalid option rather than silently accepting an ambiguous cache identity or unbounded store
