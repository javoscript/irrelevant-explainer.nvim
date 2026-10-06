# code-explanation Specification

## Purpose

Let users understand source code at a chosen scope using explanations grounded in the actual buffer contents, including unsaved changes.

## Requirements

### Requirement: File and visual scopes

The plugin SHALL offer whole-file and visual-selection explanation in ordinary text buffers without requiring a syntax parser. It SHALL preserve the selected text boundaries and reject an empty selection without invoking AI.

#### Scenario: Explain an unsaved file
- **WHEN** the user requests a file explanation after editing the buffer without saving
- **THEN** the explanation target contains all current buffer text rather than the on-disk version

#### Scenario: Unnamed buffer
- **WHEN** file or selection scope is requested in an unnamed ordinary text buffer
- **THEN** the snapshot uses a stable buffer identity rather than requiring a saved filename

#### Scenario: Explain a characterwise selection
- **WHEN** the user selects a portion of a line through a portion of another line
- **THEN** the target preserves those character boundaries and records their original source line positions

#### Scenario: Explain linewise or blockwise selections
- **WHEN** the user requests explanation of a linewise selection or a rectangular blockwise selection
- **THEN** the target contains the selected complete lines or selected per-line column spans, respectively, with their original source positions

#### Scenario: Empty selection
- **WHEN** the requested selection contains no text
- **THEN** the plugin reports that there is no selected code and does not start the external command

#### Scenario: Reversed or virtual selection
- **WHEN** a Visual region is reversed, exclusive, or crosses tabs, multibyte characters or virtual columns
- **THEN** collection preserves Neovim's selected text and per-line column spans without editing source text or leaving virtual-edit options changed

### Requirement: Structural scopes

The plugin SHALL resolve the smallest enclosing function or class at the cursor using Tree-sitter and supported language queries. Missing parsers, queries, or enclosing structures SHALL produce an actionable message instead of silently explaining a different scope.

#### Scenario: Nested function
- **WHEN** the cursor is inside a function nested within another function and function scope is requested
- **THEN** the inner function is the explanation target

#### Scenario: Class scope
- **WHEN** the cursor is inside a method of a class in a supported language and class scope is requested
- **THEN** the enclosing class, not only the method, is the explanation target

#### Scenario: Structural scope unavailable
- **WHEN** function or class scope cannot be resolved because the parser, query, or enclosing structure is unavailable
- **THEN** the plugin explains the limitation and offers file or visual scope without automatically sending a broader target

#### Scenario: Supported grammars
- **WHEN** compatible Lua, Python, JavaScript or TypeScript parsers are installed
- **THEN** function scope supports the shipped grammar queries, class scope supports Python/JavaScript/TypeScript classes, and unsupported constructs or languages do not silently widen the target

### Requirement: Target and context separation

The request SHALL distinguish the code to annotate from contextual code. In code mode the current file SHALL provide context for a narrower target, while notes SHALL anchor only to lines intersecting that target.

#### Scenario: Function depends on an import
- **WHEN** a selected function calls a helper imported outside its range
- **THEN** the request includes the current file as context, identifies the function as the target, and permits notes only inside that function

### Requirement: Behavior-focused notes

Code explanation requests SHALL ask for concise behavior-focused notes and full detail, including visible assumptions and limitations. They SHALL prohibit presenting inferred behavior of unavailable dependencies as an established fact.

#### Scenario: External API behavior unavailable
- **WHEN** the target calls an API whose implementation is absent from the supplied context
- **THEN** the prompt asks the agent to distinguish visible call behavior from unknown error handling or side effects

### Requirement: File-purpose overview request

Only file-scoped code requests SHALL ask for a short first overview, marked kind=overview and using the whole-file target anchor unchanged. Instructions SHALL ask for file purpose and responsibilities rather than just line 1. The UI SHALL place a returned overview at the file start and emphasize the full file when focused. The plugin SHALL not fabricate an overview omitted by the agent or claim validation guarantees semantic accuracy.

#### Scenario: Nonempty whole file
- **WHEN** file scope targets a nonempty current buffer
- **THEN** the prompt asks for a concise overview before ordinary behavior notes, and a returned overview refers to all target lines rather than only the first line

#### Scenario: Narrower request
- **WHEN** function, class or selection scope is requested
- **THEN** no overview instruction is included and an overview result is rejected for that scope

#### Scenario: No valid file anchor
- **WHEN** the current file contains no line-explainable target text
- **THEN** the prompt asks the agent to omit the overview instead of inventing a file purpose or line anchor

### Requirement: Incremental code explanations

Requests for different scopes in the same source-buffer session SHALL accumulate accepted notes in the existing pane. An identical target SHALL update only its batch; distinct overlapping targets SHALL coexist. A new code request SHALL supersede pending work, not previously accepted fresh batches. Failed collection, budget validation, generation or explicit cancellation SHALL preserve fresh accepted notes.

#### Scenario: Add a selection after a function
- **WHEN** a function has valid notes and the user explains a different visual selection in the same buffer
- **THEN** both batches remain visible and the pane is reused rather than replaced with only the latest answer

#### Scenario: Repeat one target
- **WHEN** an already-explained target is requested again or explicitly refreshed
- **THEN** that target's batch is replaced without duplicating it or removing other fresh target batches

#### Scenario: New request while loading
- **WHEN** another code scope is requested before the previous generation completes
- **THEN** pending work is cancelled/superseded and its late output cannot replace the new request, while accepted notes remain

### Requirement: Snapshot-bound results

An explanation SHALL remain bound to the source snapshot used to request it. Source edits before completion SHALL invalidate pending output; edits after display SHALL discard stale accepted batches and active focus. Ordinary cursor movement SHALL not invalidate captured targets. Fresh new requests SHALL be allowed after invalidation without being rejected solely because older accepted batches were stale.

#### Scenario: Edit while waiting
- **WHEN** the source changes after a request starts and before it completes
- **THEN** the old result is not displayed against the edited code

#### Scenario: Edit after display
- **WHEN** the user changes code with an explanation already open
- **THEN** the pane identifies the explanation as stale, stops displaying it as current line-aligned guidance, and does not automatically start a new AI request

#### Scenario: New snapshot after stale notes
- **WHEN** a new explicit request captures edited code while older accepted batches are being checked
- **THEN** stale batches are discarded without cancelling the new request before it has captured its own snapshot

### Requirement: Code commands and refresh

The plugin SHALL expose ExplainrCode with file/function/class/selection scopes and file as the default, plus Lua equivalents and Refresh/Cancel/Close controls. Commands invoked from notes/detail SHALL target the followed source, not Markdown. Refresh SHALL bypass result caching for the current scope, retaining visual selection boundaries and recapturing structural scopes at the source cursor. Setup SHALL not install global editing mappings.

#### Scenario: Explain from the reading pane
- **WHEN** a code action is invoked while the explanation pane has focus
- **THEN** collection uses the associated source buffer and never explains the explanation text

#### Scenario: Refresh a selection
- **WHEN** a selection explanation is refreshed after focus or cursor movement
- **THEN** the retained selection descriptor remains the target instead of a newly guessed visual region

#### Scenario: Optional integrations absent
- **WHEN** the plugin is loaded on Neovim 0.11+ without Diffview or an external AI executable installed
- **THEN** code-mode loading and setup still work, file/selection collection needs no parser, and attempting inference without a configured executable reports an actionable failure

## Decisions

- Read current buffers, including unsaved/unnamed text, rather than substituting disk versions. Keep the whole current file as context for narrow code targets; code mode does not use the diff-specific focused-context fallback.
- Use the smallest enclosing supported Tree-sitter capture for structure, with explicit failure rather than automatic parser installation or scope broadening. A Visual descriptor preserves exact user selection semantics.
- Request file-purpose overviews only for whole-file scope. Overview presence and semantic quality are agent outcomes, not fabricated by the plugin; supplied overview kinds/ranges are validated.
- Accumulate independent scopes instead of replacing the reader on every request. Refresh updates the current target, not every displayed explanation; selecting another code scope supersedes pending work but not fresh accepted notes.
