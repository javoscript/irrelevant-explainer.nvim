# Spec Delta

## MODIFIED Requirements

### Requirement: Runtime automatic-explanation toggle

Irrelevant Explainer SHALL expose `:IrrelevantExplainerToggleAutoExplain` and `require("irrelevant_explainer").toggle_auto_explain()` to invert `diff.auto_explain` for the current Neovim process. The Lua API SHALL return the new boolean, and either entrypoint SHALL notify whether automation is enabled or disabled. Setup SHALL initialize the setting, defaulting to false, without installing global mappings or persisting toggle state across restarts.

#### Scenario: Toggle without reinitializing
- **WHEN** the user invokes the Lua toggle after setup with automatic explanations disabled and a custom agent/context configuration
- **THEN** it returns true, enables navigation automation across tabs, reports that automation is enabled, and preserves all other configuration
- **AND** a second invocation returns false and reports that automation is disabled

#### Scenario: Keybind-friendly command
- **WHEN** the user invokes `:IrrelevantExplainerToggleAutoExplain` directly or through a user-defined keymap
- **THEN** it performs the same toggle and notification as the Lua API, regardless of whether an explanation pane is open
- **AND** toggling alone does not open a pane or load Diffview to start inference

#### Scenario: Setup and process lifetime
- **WHEN** setup is called with `diff.auto_explain=true` after a runtime toggle disabled automation
- **THEN** the setting becomes true according to setup's existing initialization semantics
- **AND** a new Neovim process uses its setup value or default false, not the previous process's toggle state

### Requirement: Whole-comparison explanation scope

Irrelevant Explainer SHALL support explicit review scope through the command and explain() Lua API. One uncached review action SHALL own a bounded sequence of external invocations obtaining a whole-change narrative and file explanations for every eligible text entry in the exact comparison. An outside-review action SHALL enter the same job/cache pipeline after the existing owned comparison opening reaches readiness, preserving invocation-time configuration and capture-time content. File SHALL remain the default scope. Review generation SHALL not start automatically on navigation, and reading completed file details SHALL require no further inference. IrrelevantExplainerReview SHALL remain display-only and SHALL NOT open a comparison or launch a job.

#### Scenario: Explain the selected comparison once
- **WHEN** the user runs `:IrrelevantExplainer review` or `require("irrelevant_explainer").explain("review")` in a supported comparison with three eligible files and no matching completed answer
- **THEN** one job captures all three targets and obtains their notes plus a cross-file narrative through bounded requests
- **AND** reading any of those returned files or expanding its detail requires no additional inference

#### Scenario: Trigger Review from the file tree
- **WHEN** the user invokes IrrelevantExplainer review or display-only IrrelevantExplainerReview from the live DiffviewFiles panel
- **THEN** the action uses the currently displayed comparison's source panes without requiring a source cursor or changing tree focus/selection
- **AND** file/hunk requests retain their source-pane requirement

#### Scenario: Outside review hands off to batching
- **WHEN** IrrelevantExplainer review from ordinary code opens its intended HEAD-to-working-tree comparison and no completed cache entry matches the freshly captured inputs
- **THEN** exactly one job enters the normal pipeline using invocation-time AI/context/review/cache configuration, even if readiness events or equivalent opening requests repeat
- **AND** it captures the net staged-plus-unstaged contents at readiness, preserving the resolved worktree, effective untracked policy and manifest-only unsaved overlays without saving or staging
- **AND** Auto remains suppressed through handoff and between job phases

#### Scenario: Opening is retired before handoff
- **WHEN** cancellation, source/view closure, timeout or incompatible replacement retires an outside-review opening
- **THEN** its late callbacks cannot start collection, install a cached answer, or launch annotation or synthesis
- **AND** accepted unrelated explanations and any already-open Diffview tab remain governed by the existing opening contract

#### Scenario: Filtered or staged comparison
- **WHEN** Diffview has path filters or a selected staged rather than working set
- **THEN** review scope uses that exact comparison throughout all phases, not unrelated repository changes or a merged staged/working set

#### Scenario: Metadata-only files
- **WHEN** a supported review contains text files together with binary or both-empty entries
- **THEN** the complete manifest retains those entries and exposes why they have no text annotations
- **AND** no notes or source lines are fabricated for them; a comparison with no eligible text targets fails before inference

### Requirement: Mode-aware explicit refresh

IrrelevantExplainerRefresh SHALL clear active and queued work for the owning comparison and bypass answer reuse for the visible reader target. Review mode SHALL regenerate the narrative and all file results. File mode SHALL refresh its file or hunk target; a file result obtained from a review SHALL refresh as file scope. Still-fresh accepted results SHALL remain available while waiting.

#### Scenario: Refresh the narrative
- **WHEN** the user invokes Refresh while reading Review
- **THEN** a new complete-review request starts even if the comparison has a matching cached review

#### Scenario: Refresh a distributed file result
- **WHEN** the user navigates from Review to file A and invokes Refresh
- **THEN** only A is requested as file scope, not the whole review
- **AND** other valid completed files remain retained
