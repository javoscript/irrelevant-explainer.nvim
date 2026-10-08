## MODIFIED Requirements

### Requirement: Code commands and refresh

The plugin SHALL expose `Explainr [file|selection|hunk|review]` with file as the default and `require("explainr").explain(scope, selection)`, plus Refresh/Cancel/Close controls. Commands invoked from notes/detail SHALL target the followed source, not Markdown. Refresh SHALL bypass result caching for the current scope and retain visual selection boundaries. Completion SHALL list only supported scopes. Setup SHALL not install global editing mappings. ExplainrCode/ExplainrDiff and public code()/diff() aliases SHALL be removed.

#### Scenario: Explain from the reading pane
- **WHEN** an explanation action is invoked while the explanation pane has focus
- **THEN** routing and collection use the associated source window and never explain the explanation text

#### Scenario: Refresh a selection
- **WHEN** a selection explanation is refreshed after focus or cursor movement
- **THEN** the retained selection descriptor remains the target instead of a newly guessed visual region

#### Scenario: Optional integrations absent
- **WHEN** the plugin is loaded on Neovim 0.11+ without Diffview or an external AI executable installed
- **THEN** code-mode loading and setup still work, file/selection collection needs no parser, and attempting inference without a configured executable reports an actionable failure
- **AND** ordinary code routing does not load Diffview

#### Scenario: Default and completion
- **WHEN** the user invokes Explainr without an argument, calls explain() without a scope, or requests command completion
- **THEN** the default is file, and completion offers file, selection, hunk, and review without function or class

#### Scenario: Retired scope from a command or Lua call
- **WHEN** the user requests function or class through Explainr or explain()
- **THEN** the plugin rejects the scope before cache lookup or inference and recommends file or explicit visual selection
- **AND** it does not resolve a syntax node, reuse a retired-scope answer, silently broaden the target or remove fresh accepted notes

#### Scenario: Removed public entrypoints
- **WHEN** the plugin initializes in a fresh Neovim session
- **THEN** it registers neither ExplainrCode nor ExplainrDiff and exposes neither public code() nor diff() aliases
- **AND** migration examples use Explainr or explain(), while ExplainrReview and review() remain display-only

#### Scenario: Exact visual descriptor
- **WHEN** selection is requested through an Ex Visual command or a Lua mapping supplying captured selection endpoints
- **THEN** the request preserves characterwise, linewise, or blockwise boundaries through the existing selection contract rather than treating an Ex line range as complete selection geometry
- **AND** selection explains selected source text, not a guessed diff hunk or a structural scope

## ADDED Requirements

### Requirement: Source-aware file routing

File requests SHALL explain changes when the originating source window belongs to a Diffview source pane and code otherwise. Notes/detail SHALL resolve their followed source before classification. Filetype, path, shared buffer identity, or the diff option alone SHALL NOT imply Diffview ownership. Loading or unsupported Diffview sources SHALL fail explicitly rather than fall back to code. Non-source utility buffers SHALL NOT become code targets.

#### Scenario: Ordinary file with local changes
- **WHEN** Explainr file is requested in an ordinary source window whose file also has Git changes
- **THEN** the whole current buffer is explained as code, including unsaved text, without opening Diffview

#### Scenario: Same buffer in different windows
- **WHEN** an ordinary window and a Diffview source window show the same working-file buffer
- **THEN** invoking Explainr in the ordinary window requests code, while invoking it in the Diffview window requests that comparison's diff file

#### Scenario: Unsupported or loading view
- **WHEN** file scope is requested from a Diffview-owned source that is loading, conflicting, or otherwise unsupported
- **THEN** the plugin reports the comparison limitation without invoking the agent or substituting a code explanation

#### Scenario: File panel or unrelated utility buffer
- **WHEN** file scope is requested from the Diffview file panel, a terminal, or another non-source utility buffer
- **THEN** the plugin reports that a source window is required without treating the utility content as code
- **AND** review remains available from a live Diffview file panel
