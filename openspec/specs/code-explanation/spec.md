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

### Requirement: Target and context separation

The request SHALL distinguish the code to annotate from contextual code. In code mode the current file SHALL provide context for a visual-selection target, while notes SHALL anchor only to lines intersecting that target.

#### Scenario: Function depends on an import
- **WHEN** a function explicitly selected with Visual mode calls a helper imported outside its range
- **THEN** the request includes the current file as context, identifies the selection as the target, and permits notes only inside that selection

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

The plugin SHALL expose `IrrelevantExplainer [file|selection|hunk|review]` with file as the default and `require("irrelevant_explainer").explain(scope, selection)`, plus Refresh/Cancel/Close controls under the IrrelevantExplainer prefix. Commands invoked from notes/detail SHALL target the followed source, not Markdown. Refresh SHALL bypass result caching for the current scope and retain visual selection boundaries. Completion SHALL list only supported scopes. Setup SHALL not install global editing mappings. Explainr commands, the explainr Lua package, and public code()/diff() aliases SHALL not be provided.

#### Scenario: Explain from the reading pane
- **WHEN** an explanation action is invoked while the explanation pane has focus
- **THEN** routing and collection use the associated source window and never explain the explanation text

#### Scenario: Refresh a selection
- **WHEN** a selection explanation is refreshed after focus or cursor movement
- **THEN** the retained selection descriptor remains the target instead of a newly guessed visual region

#### Scenario: Optional integrations absent
- **WHEN** the plugin is loaded on Neovim 0.11+ without Diffview or an external AI executable installed
- **THEN** code-mode loading and setup still work, file/selection collection needs no parser, and attempting inference without an available executable reports an actionable failure
- **AND** ordinary code routing does not load Diffview

#### Scenario: Default and completion
- **WHEN** the user invokes IrrelevantExplainer without an argument, calls explain() without a scope, or requests command completion
- **THEN** the default is file, and completion offers file, selection, hunk, and review without function or class

#### Scenario: Retired scope from a command or Lua call
- **WHEN** the user requests function or class through IrrelevantExplainer or explain()
- **THEN** the plugin rejects the scope before cache lookup or inference and recommends file or explicit visual selection
- **AND** it does not resolve a syntax node, reuse a retired-scope answer, silently broaden the target or remove fresh accepted notes

#### Scenario: Removed public entrypoints
- **WHEN** the plugin initializes in a fresh Neovim session
- **THEN** it registers no Explainr-prefixed commands, provides no explainr Lua import aliases, and exposes neither public code() nor diff() aliases
- **AND** migration examples use IrrelevantExplainer or explain(), while IrrelevantExplainerReview and review() remain display-only

#### Scenario: Exact visual descriptor
- **WHEN** selection is requested through an Ex Visual command or a Lua mapping supplying captured selection endpoints
- **THEN** the request preserves characterwise, linewise, or blockwise boundaries through the existing selection contract rather than treating an Ex line range as complete selection geometry
- **AND** selection explains selected source text, not a guessed diff hunk or a structural scope

### Requirement: Source-aware file routing

File requests SHALL explain changes when the originating source window belongs to a Diffview source pane and code otherwise. Notes/detail SHALL resolve their followed source before classification. Filetype, path, shared buffer identity, or the diff option alone SHALL NOT imply Diffview ownership. Loading or unsupported Diffview sources SHALL fail explicitly rather than fall back to code. Non-source utility buffers SHALL NOT become code targets.

#### Scenario: Ordinary file with local changes
- **WHEN** IrrelevantExplainer file is requested in an ordinary source window whose file also has Git changes
- **THEN** the whole current buffer is explained as code, including unsaved text, without opening Diffview

#### Scenario: Same buffer in different windows
- **WHEN** an ordinary window and a Diffview source window show the same working-file buffer
- **THEN** invoking IrrelevantExplainer in the ordinary window requests code, while invoking it in the Diffview window requests that comparison's diff file

#### Scenario: Unsupported or loading view
- **WHEN** file scope is requested from a Diffview-owned source that is loading, conflicting, or otherwise unsupported
- **THEN** the plugin reports the comparison limitation without invoking the agent or substituting a code explanation

#### Scenario: File panel or unrelated utility buffer
- **WHEN** file scope is requested from the Diffview file panel, a terminal, or another non-source utility buffer
- **THEN** the plugin reports that a source window is required without treating the utility content as code
- **AND** review remains available from a live Diffview file panel

### Requirement: Cross-session code result reuse

Completed code-file and visual-selection explanations SHALL support cross-session reuse for exact source, resolved mode, normalized target, supplied context and generation matches, including unsaved/unnamed inputs. Code-file and diff-file identities SHALL remain distinct; selection SHALL remain code. Keys SHALL preserve selection text and byte/virtual spans, excluding transient editor IDs. Restored notes SHALL bind only after validation and freshness checks.

#### Scenario: Same named file in another process
- **WHEN** a completed code-file request is repeated after restarting Neovim with identical content and generation settings
- **THEN** a valid retained result is installed without invoking the external agent, even if buffer numbers differ

#### Scenario: Shared buffer in code and diff windows
- **WHEN** an ordinary source window and a Diffview source window show the same working buffer and the user invokes IrrelevantExplainer file in each
- **THEN** source-window ownership resolves code-file and diff-file requests before cache lookup, and their entries remain distinct
- **AND** invocation from an associated reader uses its followed source rather than the reader's Markdown or the other window's cached mode

#### Scenario: Selection from a Diffview source
- **WHEN** IrrelevantExplainer selection or explain("selection", descriptor) is invoked from a Diffview source
- **THEN** lookup uses the exact selected-code target and supplied code context, not diff-file or hunk identity
- **AND** an equivalent ordinary-source selection can reuse that result only when source namespace, normalized target, supplied context and generation settings all match

#### Scenario: Unnamed or unsaved input
- **WHEN** an unnamed or unsaved buffer recreates the same normalized source, text and target in the same source namespace
- **THEN** matching retained notes can be reused without requiring a disk save or matching runtime buffer number
- **AND** structured source references bind to the current buffer without rewriting arbitrary explanation prose

#### Scenario: Same lines with different columns
- **WHEN** two selections span the same line numbers but select different text, byte columns or virtual spans
- **THEN** they do not share a cached answer merely because their line anchors match

#### Scenario: Equivalent reversed selection
- **WHEN** opposite endpoint directions select exactly the same text and normalized per-line spans
- **THEN** endpoint direction alone does not prevent reuse
- **AND** blockwise, exclusive, tab and multibyte boundaries retain their actual selected-region semantics

#### Scenario: Surrounding context changes
- **WHEN** selected text is unchanged but another supplied part of the current buffer changes
- **THEN** the old selection answer is not reused because its supplied context differs

#### Scenario: Source changes during cache lookup
- **WHEN** a matching entry is read but the source changes or the request is cancelled before installation
- **THEN** the late hit cannot install notes against the changed or superseded target

## Decisions

- Read current buffers, including unsaved/unnamed text, rather than substituting disk versions. Keep the whole current file as context for narrow code targets; code mode does not use the diff-specific focused-context fallback.
- Use explicit Visual descriptors for narrower code targets, preserving exact user selection semantics without parser-based structural scopes or automatic scope broadening.
- Request file-purpose overviews only for whole-file scope. Overview presence and semantic quality are agent outcomes, not fabricated by the plugin; supplied overview kinds/ranges are validated.
- Accumulate independent scopes instead of replacing the reader on every request. Refresh updates the current target, not every displayed explanation; selecting another code scope supersedes pending work but not fresh accepted notes.
