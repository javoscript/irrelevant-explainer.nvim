# Spec Delta

## MODIFIED Requirements

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
