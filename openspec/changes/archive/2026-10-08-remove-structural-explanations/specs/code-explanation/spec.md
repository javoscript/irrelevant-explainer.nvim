## REMOVED Requirements

### Requirement: Structural scopes

**Reason**: Function/class targeting is removed from the supported scope model; visual selection supplies explicit boundaries without parser or grammar support.

**Migration**: Replace `ExplainrCode function`, `ExplainrCode class` and equivalent Lua calls with an explicit visual selection followed by `ExplainrCode selection`, or request `file` when the whole file is intended. No automatic alias or scope widening is provided.

## MODIFIED Requirements

### Requirement: Target and context separation

The request SHALL distinguish the code to annotate from contextual code. In code mode the current file SHALL provide context for a visual-selection target, while notes SHALL anchor only to lines intersecting that target.

#### Scenario: Function depends on an import
- **WHEN** a function explicitly selected with Visual mode calls a helper imported outside its range
- **THEN** the request includes the current file as context, identifies the selection as the target, and permits notes only inside that selection

### Requirement: File-purpose overview request

Only file-scoped code requests SHALL ask for a short first overview, marked kind=overview and using the whole-file target anchor unchanged. Instructions SHALL ask for file purpose and responsibilities rather than just line 1. The UI SHALL place a returned overview at the file start and emphasize the full file when focused. The plugin SHALL not fabricate an overview omitted by the agent or claim validation guarantees semantic accuracy.

#### Scenario: Nonempty whole file
- **WHEN** file scope targets a nonempty current buffer
- **THEN** the prompt asks for a concise overview before ordinary behavior notes, and a returned overview refers to all target lines rather than only the first line

#### Scenario: Narrower request
- **WHEN** selection scope is requested
- **THEN** no overview instruction is included and an overview result is rejected for that scope

#### Scenario: No valid file anchor
- **WHEN** the current file contains no line-explainable target text
- **THEN** the prompt asks the agent to omit the overview instead of inventing a file purpose or line anchor

### Requirement: Incremental code explanations

Requests for different scopes in the same source-buffer session SHALL accumulate accepted notes in the existing pane. An identical target SHALL update only its batch; distinct overlapping targets SHALL coexist. A new code request SHALL supersede pending work, not previously accepted fresh batches. Failed collection, budget validation, generation or explicit cancellation SHALL preserve fresh accepted notes.

#### Scenario: Add a selection after a function
- **WHEN** a function explained through an explicit visual selection has valid notes and the user explains a different visual selection in the same buffer
- **THEN** both batches remain visible and the pane is reused rather than replaced with only the latest answer

#### Scenario: Repeat one target
- **WHEN** an already-explained target is requested again or explicitly refreshed
- **THEN** that target's batch is replaced without duplicating it or removing other fresh target batches

#### Scenario: New request while loading
- **WHEN** another code scope is requested before the previous generation completes
- **THEN** pending work is cancelled/superseded and its late output cannot replace the new request, while accepted notes remain

### Requirement: Code commands and refresh

The plugin SHALL expose ExplainrCode with only file/selection scopes and file as the default, plus Lua equivalents and Refresh/Cancel/Close controls. Commands invoked from notes/detail SHALL target the followed source, not Markdown. Refresh SHALL bypass result caching for the current scope and retain visual selection boundaries. Completion SHALL list only supported code scopes. Setup SHALL not install global editing mappings.

#### Scenario: Explain from the reading pane
- **WHEN** a code action is invoked while the explanation pane has focus
- **THEN** collection uses the associated source buffer and never explains the explanation text

#### Scenario: Refresh a selection
- **WHEN** a selection explanation is refreshed after focus or cursor movement
- **THEN** the retained selection descriptor remains the target instead of a newly guessed visual region

#### Scenario: Optional integrations absent
- **WHEN** the plugin is loaded on Neovim 0.11+ without Diffview or an external AI executable installed
- **THEN** code-mode loading and setup still work, file/selection collection needs no parser, and attempting inference without a configured executable reports an actionable failure

#### Scenario: Default and completion
- **WHEN** the user invokes ExplainrCode without an argument or requests scope completion
- **THEN** the default is file, and completion offers file and selection without function or class

#### Scenario: Retired scope from a command or Lua call
- **WHEN** the user requests function or class through ExplainrCode or its Lua API
- **THEN** the plugin rejects the scope before cache lookup or inference and recommends file or explicit visual selection
- **AND** it does not resolve a syntax node, reuse a retired-scope answer, silently broaden the target or remove fresh accepted notes
