# Spec Delta

## ADDED Requirements

### Requirement: Default external agent

Without AI overrides, setup SHALL select `ai.command={"opencode","run","--agent","explain","--format","json"}`, `ai.output="opencode"`, and `ai.timeout_ms=300000`. Setup/loading SHALL NOT launch, install, or authenticate a tool. OpenCode, its user-created restricted explain agent, provider/model, and effective permissions SHALL remain user prerequisites, not plugin-managed resources.

#### Scenario: Default setup without inference
- **WHEN** the user calls setup() without AI overrides
- **THEN** the complete OpenCode argv, OpenCode decoder, and 300000 ms timeout are selected without starting an external process
- **AND** inference begins only through the existing explicit-request or opt-in navigation contracts

#### Scenario: Default tool is unavailable
- **WHEN** inference is requested with the default command but OpenCode cannot be launched
- **THEN** the plugin reports the launch failure without installing a tool, approving permissions, or falling back to another provider
- **AND** setup and source collection remain usable without an installed OpenCode executable

### Requirement: Storage continuity across the package rename

The renamed plugin SHALL retain `stdpath("cache")/explainr/results/v1` as its documented compatibility storage path. Branding alone SHALL NOT change completed-result format or semantic identity, migrate or delete existing records, or broaden cache clearing beyond plugin-owned entries. Eligible existing records SHALL remain subject to normal identity, schema, evidence, freshness, and permission validation.

#### Scenario: Existing completed answer after rename
- **WHEN** an existing valid completed record matches a freshly captured request after the package rename
- **THEN** the renamed plugin can reuse it without external inference after normal validation
- **AND** no record is rewritten or considered invalid merely because the command or Lua package name changed

#### Scenario: Renamed cache clear reaches existing storage
- **WHEN** the user invokes IrrelevantExplainerCacheClear or require("irrelevant_explainer").clear_cache()
- **THEN** eligible plugin-owned records in the retained storage path are cleared under the existing ownership and concurrency rules
- **AND** unrelated cache files are not removed and no second renamed storage tree is created

## MODIFIED Requirements

### Requirement: Configurable command transport

Users SHALL be able to configure an executable and argument list for noninteractive prompting through `ai.command`. An explicitly supplied command list SHALL replace the entire default argv, never merge or append default arguments. The plugin SHALL send the complete prompt through stdin by default, close stdin after sending, and run asynchronously without interpolating prompt content into a shell command.

#### Scenario: Prompt includes shell syntax
- **WHEN** code contains quotes, newlines, dollar expansions, or shell metacharacters
- **THEN** those bytes are delivered as prompt data rather than shell instructions or split arguments

#### Scenario: Custom command
- **WHEN** a user configures a compatible script instead of a built-in agent
- **THEN** the same request contract works without plugin-owned provider credentials

#### Scenario: No configured executable
- **WHEN** setup explicitly uses ai.command={} and inference is requested
- **THEN** setup/loading remain valid but the request reports that a compatible command must be configured before generation
- **AND** the explicitly empty list is not replaced with the default OpenCode command

#### Scenario: Project execution environment
- **WHEN** a configured command is launched
- **THEN** it inherits the user's tool environment and runs in the captured source/project directory, without adding conversation-continuation, server-attachment or automatic-approval flags

#### Scenario: Shorter override replaces all default arguments
- **WHEN** the user configures ai.command={"my-wrapper"} with ai.output="plain"
- **THEN** the effective argv contains exactly my-wrapper with none of run, --agent, explain, --format, or json appended
- **AND** paths and arguments with spaces or shell syntax remain individual literal argv elements

#### Scenario: Setup reset and caller-owned options
- **WHEN** a custom argv has been supplied and setup() is later called without overrides
- **THEN** defaults are restored rather than retaining the previous custom command
- **AND** setup does not modify the caller's options table or command list

### Requirement: Output decoding

The plugin SHALL support OpenCode event output, Codex event output, and plain final structured output, plus a user-supplied decoder for other command formats through `ai.output`, defaulting to opencode. Custom command configuration SHALL NOT imply decoder detection or fallback; users SHALL select a compatible decoder. The plugin SHALL separate stdout from stderr and distinguish completed answers from progress, reasoning, tool events, and errors.

#### Scenario: Progress looks like a valid explanation
- **WHEN** an event stream contains a schema-shaped progress message before the final answer
- **THEN** the decoder waits for successful completion and selects the final answer rather than the first parseable object

#### Scenario: Chunked events
- **WHEN** a JSON event spans several process-output chunks or several events arrive in one chunk
- **THEN** decoding preserves complete event boundaries and assistant message ordering

#### Scenario: Plain structured-output command
- **WHEN** a compatible command successfully returns one final explanation object on stdout and ai.output="plain" is selected
- **THEN** the object is accepted without interpreting it as agent transport events

#### Scenario: Custom decoder fails
- **WHEN** a user decoder throws, returns an error, or the process exits nonzero
- **THEN** the invocation fails rather than promoting malformed output or allowing a custom decoder to override failed process completion

#### Scenario: Codex override
- **WHEN** the user configures ai.command={"codex","exec","-","--json","--sandbox","read-only"} and ai.output="codex"
- **THEN** the configured argv and Codex decoder are used without OpenCode flags, tool invocation, or decoder fallback

#### Scenario: Command override without decoder override
- **WHEN** the user overrides ai.command but leaves ai.output unset
- **THEN** the decoder remains opencode and incompatible output fails the normal decoder/validation checks
- **AND** documentation explains explicitly choosing plain, codex, or a custom function when required

### Requirement: Persistent cache controls

Persistent caching SHALL default to enabled and support opt-out, a size limit and an explicit namespace. IrrelevantExplainerCacheClear and `require("irrelevant_explainer").clear_cache()` SHALL clear plugin-owned completed disk entries and reusable memory answers while preserving displayed notes. Refresh SHALL bypass both answer caches and replace a prior persistent answer only after successful validation. Invalid cache configuration SHALL be rejected during setup.

#### Scenario: Disable persistence
- **WHEN** cache.enabled is false
- **THEN** no persistent reads or writes occur, while current-session accepted-note retention still works

#### Scenario: Refresh fails
- **WHEN** Refresh starts a new invocation but that invocation fails
- **THEN** the earlier valid persistent answer is not overwritten or deleted by the failed attempt

#### Scenario: Explicit clear during generation
- **WHEN** the user runs IrrelevantExplainerCacheClear while a request is pending
- **THEN** completed entries and reusable memory answers are cleared without closing the reader or deleting unrelated files
- **AND** this process's pre-clear requests cannot repopulate the disk cache; other running processes may later create new entries
- **AND** unfinished review checkpoints remain governed by Cancel/Refresh, not completed-result cache clear

#### Scenario: Invalid cache options
- **WHEN** enabled is not boolean, max_bytes is not a positive finite integer, or namespace or an explicitly supplied decoder_key is empty or not a string
- **THEN** setup reports the invalid option rather than silently accepting an ambiguous cache identity or unbounded store
