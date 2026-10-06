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

Requests SHALL require one version=1 JSON object with a notes array, single-line nonempty summaries, nonempty detail, target-contained anchors, intent_basis and an evidence array. Code notes SHALL have one buffer anchor; diff notes SHALL have one old/new anchor or a paired old/new range without duplicate sides. Empty note/evidence arrays SHALL be allowed, except documented intent SHALL require nonempty evidence.

#### Scenario: Valid empty answer
- **WHEN** a successful command returns version 1 with an empty notes array
- **THEN** validation accepts that result rather than inventing explanations

#### Scenario: Incompatible contract
- **WHEN** output has an unsupported version, invalid anchor side/count, duplicate sides, multiline summary or missing required text
- **THEN** the result is rejected with an actionable validation error before any notes are rendered

### Requirement: Grounded Markdown prompting

Prompts SHALL distinguish controlling instructions, untrusted supplied snapshot and focused target. They SHALL ask for sparse plain-text summaries and complete Markdown detail using backtick inline code and short language-tagged fenced snippets, with proper JSON escaping. They SHALL prohibit tool use, edits, repository exploration and interactive questions, while documenting that prompt instructions do not sandbox arbitrary agents.

#### Scenario: Multi-line snippet in detail
- **WHEN** supplied code is best explained with a short code example
- **THEN** instructions ask for Markdown inside the JSON detail string, with escaped newlines/quotes/backslashes, not a response wrapped in Markdown fences

#### Scenario: Hostile repository content
- **WHEN** supplied code or documents include instructions to run tools or change the output contract
- **THEN** the prompt classifies them as untrusted data, leaving the user's external permissions as the enforcement boundary

### Requirement: Structured explanation validation

Before rendering, the plugin SHALL validate the explanation's version, note summaries/details, target anchors, and supplied evidence ranges against the request snapshot. Invalid JSON, out-of-target anchors, unsupported sides, or citations to absent context SHALL reject the result rather than invent or relocate notes.

#### Scenario: Invalid line reference
- **WHEN** a note refers to a line outside the focused file or hunk
- **THEN** the result is rejected with an actionable output-validation error

#### Scenario: Unsupported evidence
- **WHEN** a note claims documented intent but cites a file or range absent from the supplied context
- **THEN** the result is rejected instead of displaying that citation as grounded evidence

#### Scenario: Optional overview has partial anchors
- **WHEN** a returned kind=overview omits a whole-file side/range, duplicates another overview, or appears in a narrower scope
- **THEN** validation rejects it; absence of an overview is not itself rejected, and semantic file-purpose accuracy is not guaranteed by validation

#### Scenario: Correct citation does not prove a claim
- **WHEN** a citation fits supplied context
- **THEN** validation establishes only supplied-range grounding, not that the interpretation is true or that cited tests were executed

### Requirement: Completion and cancellation

Requests SHALL have a configurable timeout (default 300000 ms) and explicit cancellation. Nonzero exit, agent-reported failure, interruption or incomplete output SHALL not count as success. Cancelling or superseding pending work SHALL prevent late pane updates while retaining fresh accepted notes. Cancelling the owned local client SHALL not be claimed to cancel arbitrary descendants, attached remote generation, external history or billing.

#### Scenario: Error after partial text
- **WHEN** the command streams explanation text and then reports failure or exits nonzero
- **THEN** the partial response is not installed as a successful explanation

#### Scenario: Timeout or cancellation
- **WHEN** a request times out or is cancelled
- **THEN** the plugin stops its owned invocation, reports the state, and ignores late output

#### Scenario: Result delivered after cancellation
- **WHEN** success was queued for delivery before a cancellation/supersession takes effect
- **THEN** generation/ownership checks prevent that late success from updating a newer or closed reader

### Requirement: Explicit context budget

The plugin SHALL budget the complete assembled UTF-8 prompt before launching inference, including instructions, output contract, supplied context and target. context.max_bytes SHALL default to 262144 and accept positive finite integers. Exact serialized byte counts or conservative early collection bounds SHALL not be presented as exact provider token usage or a guarantee that a provider will accept the request.

#### Scenario: Instructions push a request over budget
- **WHEN** source text alone fits but the assembled prompt and output contract exceed the budget
- **THEN** the command is not started and the failure identifies the assembled request size

#### Scenario: Provider rejects a locally accepted request
- **WHEN** the command reports a provider context limit below the configured byte budget
- **THEN** the error is surfaced without hidden provider fallback, and documentation advises lowering max_bytes or using focused diff coverage rather than claiming the byte check guarantees provider acceptance

### Requirement: In-memory request reuse

Validated answers and serialized context SHALL be reusable only for matching content/target/coverage and captured agent/context configuration, including custom decoder identity. Cache hits SHALL pass freshness/output validation before installation. Explicit Refresh SHALL bypass answer reuse and request inference for the current target. The plugin SHALL not add disk history or assume independent requests receive provider prompt-cache discounts.

#### Scenario: Repeat an unchanged target
- **WHEN** an already-validated matching request is repeated without refresh
- **THEN** a fresh matching cache hit can be installed through the normal batch replacement path without another invocation

#### Scenario: Change decoder or context settings
- **WHEN** the executable/output decoder or context configuration changes
- **THEN** old cached output is not treated as a matching answer merely because source text is unchanged, and unrelated fresh accepted batches remain available

## Decisions

- Delegate inference to configured tools and wrappers rather than owning provider authentication, model billing or subscription access. The user is responsible for compatible noninteractive commands and effective permissions.
- Send prompts as stdin data to argv, not shell interpolation. Treat arbitrary configured commands as trusted executable configuration, not as sandboxed explanation engines.
- Request all short and detailed content at once; validate completed output before display rather than rendering token-by-token unvalidated notes or issuing follow-up calls on expansion.
- Use a structured JSON envelope for reliable anchoring and grounding, with Markdown only inside detail. Valid ranges do not prove semantic correctness, and overview presence is prompt guidance rather than mandatory output.
- Use explicit UTF-8 byte budgets because universal provider token accounting is unavailable. Coverage reduction belongs to diff-context selection, not blind truncation by transport.
- Keep caches process-local and external invocations independent. Local cancellation guards the reader against late output but cannot undo external retention, tool side effects or remote billing.
