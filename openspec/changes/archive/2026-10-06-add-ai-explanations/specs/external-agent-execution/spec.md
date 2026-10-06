# Spec Delta

## Purpose

Delegate AI inference to user-configured local commands while providing a reliable input, output, cancellation, and validation contract for explanations.

## ADDED Requirements

### Requirement: Configurable command transport

Users SHALL be able to configure an executable and argument list for noninteractive prompting. The plugin SHALL send the complete prompt through stdin by default, close stdin after sending, and run asynchronously without interpolating prompt content into a shell command.

#### Scenario: Prompt includes shell syntax
- **WHEN** code contains quotes, newlines, dollar expansions, or shell metacharacters
- **THEN** those bytes are delivered as prompt data rather than shell instructions or split arguments

#### Scenario: Custom command
- **WHEN** a user configures a compatible script instead of a built-in agent
- **THEN** the same request contract works without plugin-owned provider credentials

### Requirement: Agent-owned authentication and permissions

Authentication, model selection, billing, and external-agent permissions SHALL remain owned by the configured command. The plugin SHALL document read-only/noninteractive configuration and SHALL NOT promise arbitrary commands are sandboxed, obtain provider credentials, or silently fall back to another provider.

#### Scenario: Missing login or exhausted subscription
- **WHEN** the configured command reports an authentication or usage-limit failure
- **THEN** the plugin reports that failure without attempting a different or separately billed provider

#### Scenario: Agent requests permissions
- **WHEN** an agent requires unavailable interactive approval
- **THEN** the invocation is treated as failed or pending until its timeout, not automatically approved by the plugin

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

### Requirement: Structured explanation validation

Before rendering, the plugin SHALL validate the explanation's version, note summaries/details, target anchors, and supplied evidence ranges against the request snapshot. Invalid JSON, out-of-target anchors, unsupported sides, or citations to absent context SHALL reject the result rather than invent or relocate notes.

#### Scenario: Invalid line reference
- **WHEN** a note refers to a line outside the focused file or hunk
- **THEN** the result is rejected with an actionable output-validation error

#### Scenario: Unsupported evidence
- **WHEN** a note claims documented intent but cites a file or range absent from the supplied context
- **THEN** the result is rejected instead of displaying that citation as grounded evidence

### Requirement: Completion and cancellation

Requests SHALL have a configurable timeout and explicit cancellation. Nonzero exit, agent-reported failure, interruption, or incomplete output SHALL not count as successful generation. Cancelling or replacing a request SHALL prevent its later output from updating any pane.

#### Scenario: Error after partial text
- **WHEN** the command streams explanation text and then reports failure or exits nonzero
- **THEN** the partial response is not installed as a successful explanation

#### Scenario: Timeout or cancellation
- **WHEN** a request times out or is cancelled
- **THEN** the plugin stops its owned invocation, reports the state, and ignores late output

### Requirement: Explicit context budget

The plugin SHALL expose an explicit request-size budget and check it before process execution. Budget checks SHALL apply to instructions, target, review context, and output contract together; they SHALL report estimates as estimates rather than exact provider token counts.

#### Scenario: Instructions push a request over budget
- **WHEN** source text alone fits but the assembled prompt and output contract exceed the budget
- **THEN** the command is not started and the failure identifies the assembled request size
