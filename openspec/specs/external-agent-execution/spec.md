# external-agent-execution Specification

## Purpose

Delegate AI inference to user-configured local commands while providing a reliable input, output, cancellation, and validation contract for explanations.

## Requirements

### Requirement: Configurable command transport

Users SHALL be able to configure an executable and argument list for noninteractive prompting. The plugin SHALL send the complete prompt through stdin by default, close stdin after sending, and run asynchronously without interpolating prompt content into a shell command.

#### Scenario: Prompt includes shell syntax
- **WHEN** code contains quotes, newlines, dollar expansions, or shell metacharacters
- **THEN** those bytes are delivered as prompt data rather than shell instructions or split arguments

#### Scenario: Custom command
- **WHEN** a user configures a compatible script instead of a built-in agent
- **THEN** the same request contract works without plugin-owned provider credentials

#### Scenario: No configured executable
- **WHEN** setup uses the default empty command list and inference is requested
- **THEN** setup/loading remain valid but the request reports that a compatible command must be configured before generation

#### Scenario: Project execution environment
- **WHEN** a configured command is launched
- **THEN** it inherits the user's tool environment and runs in the captured source/project directory, without adding conversation-continuation, server-attachment or automatic-approval flags

### Requirement: Agent-owned authentication and permissions

Authentication, model selection, billing, and external-agent permissions SHALL remain owned by the configured command. The plugin SHALL document read-only/noninteractive configuration and SHALL NOT promise arbitrary commands are sandboxed, obtain provider credentials, or silently fall back to another provider.

#### Scenario: Missing login or exhausted subscription
- **WHEN** the configured command reports an authentication or usage-limit failure
- **THEN** the plugin reports that failure without attempting a different or separately billed provider

#### Scenario: Agent requests permissions
- **WHEN** an agent requires unavailable interactive approval
- **THEN** the invocation is treated as failed or pending until its timeout, not automatically approved by the plugin

#### Scenario: Subscription-configured command
- **WHEN** the user's tool is authenticated with a subscription rather than an API credential
- **THEN** Explainr delegates to that tool without managing login or promising a particular provider's subscription billing behavior

### Requirement: Output decoding

The plugin SHALL support OpenCode event output, Codex event output, and plain final structured output, plus a user-supplied decoder for other command formats. It SHALL separate stdout from stderr and distinguish completed answers from progress, reasoning, tool events, and errors.

#### Scenario: Progress looks like a valid explanation
- **WHEN** an event stream contains a schema-shaped progress message before the final answer
- **THEN** the decoder waits for successful completion and selects the final answer rather than the first parseable object

#### Scenario: Chunked events
- **WHEN** a JSON event spans several process-output chunks or several events arrive in one chunk
- **THEN** decoding preserves complete event boundaries and assistant message ordering

#### Scenario: Plain structured-output command
- **WHEN** a compatible command successfully returns one final explanation object on stdout
- **THEN** the object is accepted without interpreting it as agent transport events

#### Scenario: Custom decoder fails
- **WHEN** a user decoder throws, returns an error, or the process exits nonzero
- **THEN** the invocation fails rather than promoting malformed output or allowing a custom decoder to override failed process completion

### Requirement: Structured payload contract

Code/file/hunk requests SHALL require one version=1 JSON object with notes, single-line nonempty summaries, nonempty detail, target-contained anchors, intent_basis and evidence. Code notes SHALL have one buffer anchor; diff notes SHALL have one old/new anchor or a paired range without duplicate sides. Empty note/evidence arrays SHALL be allowed except documented intent requires evidence. Review SHALL use its version-2 envelope with the same note rules applied per file.

#### Scenario: Valid empty answer
- **WHEN** a successful code/file/hunk command returns version 1 with an empty notes array
- **THEN** validation accepts that result rather than inventing explanations

#### Scenario: Incompatible contract
- **WHEN** output has a version unsupported for the requested scope, invalid anchor side/count, duplicate sides, multiline summary or missing required text
- **THEN** the result is rejected with an actionable validation error before any notes are rendered

#### Scenario: Legacy command compatibility
- **WHEN** existing plain, OpenCode, Codex, or custom-decoder commands serve code/file/hunk requests
- **THEN** their version-1 payload contract remains unchanged
- **AND** review requests explicitly advertise version 2 rather than interpreting a legacy flat answer as complete review coverage

### Requirement: Grounded Markdown prompting

Prompts SHALL distinguish controlling instructions, untrusted supplied snapshot and focused target. They SHALL ask for sparse plain-text summaries and complete Markdown detail using backtick inline code and short language-tagged fenced snippets, with proper JSON escaping. They SHALL prohibit tool use, edits, repository exploration and interactive questions, while documenting that prompt instructions do not sandbox arbitrary agents.

#### Scenario: Multi-line snippet in detail
- **WHEN** supplied code is best explained with a short code example
- **THEN** instructions ask for Markdown inside the JSON detail string, with escaped newlines/quotes/backslashes, not a response wrapped in Markdown fences

#### Scenario: Hostile repository content
- **WHEN** supplied code or documents include instructions to run tools or change the output contract
- **THEN** the prompt classifies them as untrusted data, leaving the user's external permissions as the enforcement boundary

### Requirement: Structured explanation validation

Before rendering, the plugin SHALL validate the explanation's scope-appropriate version, note summaries/details, target anchors, and supplied evidence ranges against the request snapshot. Review SHALL additionally validate its narrative and complete per-file coverage. Invalid JSON, out-of-target anchors, unsupported sides, or citations to absent context SHALL reject the result rather than invent or relocate notes.

#### Scenario: Invalid line reference
- **WHEN** a note refers to a line outside its focused file/hunk target or its assigned review file target
- **THEN** the result is rejected with an actionable output-validation error

#### Scenario: Unsupported evidence
- **WHEN** a note claims documented intent but cites a file or range absent from the supplied context
- **THEN** the result is rejected instead of displaying that citation as grounded evidence

#### Scenario: Optional overview has partial anchors
- **WHEN** a returned kind=overview omits a whole-file side/range, duplicates another overview in the same file result, or appears in a narrower scope
- **THEN** validation rejects it; absence of an overview is not itself rejected, and semantic file-purpose accuracy is not guaranteed by validation

#### Scenario: Correct citation does not prove a claim
- **WHEN** a citation fits supplied context
- **THEN** validation establishes only supplied-range grounding, not that the interpretation is true or that cited tests were executed

### Requirement: Completion and cancellation

Requests SHALL have a configurable timeout (default 300000 ms) and explicit cancellation. Nonzero exit, agent-reported failure, interruption or incomplete output SHALL not count as success. Cancellation or supersession SHALL prevent late display or retention of that request while preserving fresh accepted results. File navigation alone SHALL not cancel comparison-owned work. Stopping the local client SHALL not be claimed to cancel arbitrary descendants, remote generation, external history or billing.

#### Scenario: Error after partial text
- **WHEN** the command streams explanation text and then reports failure or exits nonzero
- **THEN** the partial response is not installed as a successful explanation

#### Scenario: Timeout or cancellation
- **WHEN** a request times out or is cancelled
- **THEN** the plugin stops its owned invocation, reports the state, and ignores late output

#### Scenario: Result delivered after cancellation
- **WHEN** success was queued for delivery before a cancellation/supersession takes effect
- **THEN** ownership checks prevent that late success from updating a newer or closed reader or entering retained results

#### Scenario: Off-screen success is still owned
- **WHEN** a file request finishes after navigation within its still-open comparison
- **THEN** valid output can be retained for its original target without requiring that target to remain displayed

### Requirement: Explicit context budget

The plugin SHALL budget the complete assembled UTF-8 prompt before launching inference, including instructions, output contract, supplied context and target. context.max_bytes SHALL default to 262144 and accept positive finite integers. Exact serialized byte counts or conservative early collection bounds SHALL not be presented as exact provider token usage or a guarantee that a provider will accept the request.

#### Scenario: Instructions push a request over budget
- **WHEN** source text alone fits but the assembled prompt and output contract exceed the budget
- **THEN** the command is not started and the failure identifies the assembled request size

#### Scenario: Provider rejects a locally accepted request
- **WHEN** the command reports a provider context limit below the configured byte budget
- **THEN** the error is surfaced without hidden provider fallback, and documentation advises lowering max_bytes or using focused diff coverage rather than claiming the byte check guarantees provider acceptance

### Requirement: In-memory request reuse

Validated answers and serialized context SHALL be reusable only for matching content/target/coverage and captured agent/context configuration, including custom decoder identity. Cache hits SHALL pass freshness/output validation before installation. Explicit Refresh SHALL bypass answer reuse for the visible mode's target. Review file results SHALL retain shared comparison provenance. The plugin SHALL not add disk history or assume provider prompt-cache discounts for independent requests.

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

### Requirement: Structured review response

Review requests SHALL require one version=2 JSON object containing review and files. Review SHALL contain a nonempty single-line title and a nonempty sections array. Each section SHALL contain a nonempty single-line heading, Markdown detail, intent_basis, evidence array, and unique file_ids referencing supplied manifest entries. Documented sections SHALL require nonempty supplied-range evidence. Narrative sections SHALL not require source anchors.

#### Scenario: Narrative relates several files
- **WHEN** a section cites supplied requirements and references two changed file identities
- **THEN** validation accepts valid cross-file evidence and references without inventing a whole-comparison anchor

#### Scenario: Unsupported narrative claim or reference
- **WHEN** a documented section has no evidence, cites unavailable lines, or references a file identity outside the supplied manifest
- **THEN** the entire review response is rejected with an actionable validation error

#### Scenario: Empty or malformed narrative
- **WHEN** review title or sections are absent, sections is empty, or a section has invalid text, intent, or array fields
- **THEN** the response is rejected rather than synthesizing a narrative from file summaries

### Requirement: Complete per-file review coverage

The review files array SHALL contain exactly one entry per eligible textual target, identified by its supplied file_id and containing a notes array. Each entry SHALL satisfy the existing file-note contract against that file's target and shared supplied context. Missing, duplicate, unknown, or ineligible file entries SHALL reject the response. An explicit empty notes array SHALL be valid and count as completed coverage, not proof of semantic explanation quality.

#### Scenario: Missing and explicitly empty files differ
- **WHEN** three eligible file targets were supplied but the response includes only two file entries
- **THEN** validation rejects the response for missing coverage
- **AND** including the third file with an empty notes array instead is structurally valid and does not fabricate notes

#### Scenario: Cross-file anchors are not cross-file evidence
- **WHEN** A's file result anchors a note to B despite both files being supplied
- **THEN** the response is rejected
- **AND** citing B as supplied evidence for a note anchored within A remains valid

#### Scenario: Multiple independent file overviews
- **WHEN** two file entries each return one overview matching their complete available old/new anchors
- **THEN** both overviews validate independently
- **AND** duplicate overviews within one file, partial whole-file anchors, or mismatched rename paths reject the review

#### Scenario: Metadata-only entries
- **WHEN** binary or both-empty entries occur in the manifest but have no textual target
- **THEN** they can be referenced by narrative file_ids but cannot receive invented notes entries or anchors

### Requirement: Atomic review acceptance

The plugin SHALL install a review narrative and its file results together only after successful process completion, complete schema validation, and snapshot freshness checks. Invalid or incomplete review output SHALL install none of that response and preserve previous still-fresh results. A failed review SHALL not trigger automatic repair or fallback invocations; independently queued explicit requests SHALL continue normally.

#### Scenario: Truncated provider output
- **WHEN** a provider returns truncated JSON, omits later files, reports failure after partial output, or times out
- **THEN** the review fails explicitly without accepting an apparently complete narrative or partial file results
- **AND** the error offers reducing the explicit comparison or using file/hunk scope without starting those requests automatically

#### Scenario: One bad sibling
- **WHEN** the narrative and two files validate but a third file contains an invalid range
- **THEN** none of the new response replaces retained data

#### Scenario: Content changes before installation
- **WHEN** all output validates structurally but relevant comparison content changed during generation
- **THEN** the narrative and every file result from that stale review are withheld from current display

## Decisions

- Delegate inference to configured tools and wrappers rather than owning provider authentication, model billing or subscription access. The user is responsible for compatible noninteractive commands and effective permissions.
- Send prompts as stdin data to argv, not shell interpolation. Treat arbitrary configured commands as trusted executable configuration, not as sandboxed explanation engines.
- Request all short and detailed content at once; validate completed output before display rather than rendering token-by-token unvalidated notes or issuing follow-up calls on expansion.
- Use a structured JSON envelope for reliable anchoring and grounding, with Markdown only inside detail. Valid ranges do not prove semantic correctness, and overview presence is prompt guidance rather than mandatory output.
- Use explicit UTF-8 byte budgets because universal provider token accounting is unavailable. Coverage reduction belongs to diff-context selection, not blind truncation by transport.
- Keep caches process-local and external invocations independent. Local cancellation guards the reader against late output but cannot undo external retention, tool side effects or remote billing.
