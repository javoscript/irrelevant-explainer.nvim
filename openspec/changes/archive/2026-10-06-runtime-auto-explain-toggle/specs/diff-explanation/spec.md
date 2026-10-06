# Spec Delta

## ADDED Requirements

### Requirement: Runtime automatic-explanation toggle

Explainr SHALL expose `:ExplainrToggleAutoExplain` and `require("explainr").toggle_auto_explain()` to invert `diff.auto_explain` for the current Neovim process. The Lua API SHALL return the new boolean, and either entrypoint SHALL notify whether automation is enabled or disabled. Setup SHALL initialize the setting, defaulting to false, without installing global mappings or persisting toggle state across restarts.

#### Scenario: Toggle without reinitializing
- **WHEN** the user invokes the Lua toggle after setup with automatic explanations disabled and a custom agent/context configuration
- **THEN** it returns true, enables navigation automation across tabs, reports that automation is enabled, and preserves all other configuration
- **AND** a second invocation returns false and reports that automation is disabled

#### Scenario: Keybind-friendly command
- **WHEN** the user invokes `:ExplainrToggleAutoExplain` directly or through a user-defined keymap
- **THEN** it performs the same toggle and notification as the Lua API, regardless of whether an explanation pane is open
- **AND** toggling alone does not open a pane or load Diffview to start inference

#### Scenario: Setup and process lifetime
- **WHEN** setup is called with `diff.auto_explain=true` after a runtime toggle disabled automation
- **THEN** the setting becomes true according to setup's existing initialization semantics
- **AND** a new Neovim process uses its setup value or default false, not the previous process's toggle state

### Requirement: Navigation-only runtime mode changes

Enabling automation SHALL apply only to navigation after the toggle, not immediately request the current file or retry an earlier navigation. Disabling SHALL prevent future automatic requests without cancelling started work, clearing accepted notes, or disabling manual requests and saved-note restoration. Existing pane-open, coherent-buffer, background-tab, freshness, and no-retry rules SHALL remain in effect.

#### Scenario: Enable on an unexplained current file
- **WHEN** an open diff pane shows an unexplained file and the user enables automation without navigating
- **THEN** no automatic request starts, including on subsequent polling, layout, focus, or edit events
- **AND** navigating afterward to a coherent unexplained file starts exactly one file-scoped request

#### Scenario: Earlier navigation is still resolving
- **WHEN** a navigation that occurred while automation was disabled is still loading buffers or validating saved notes when the user enables automation
- **THEN** completing that earlier navigation does not issue an automatic request, even if saved notes are invalid
- **AND** a background-tab navigation from before enabling does not issue a request solely when the tab becomes active

#### Scenario: Disable before automatic work starts
- **WHEN** an enabled navigation is waiting for coherent buffers, stale-note validation, or tab activation and the user disables automation before a request starts
- **THEN** the deferred automatic request does not start
- **AND** the pane still follows the file and restores valid saved notes when available

#### Scenario: Disable during an active request
- **WHEN** an automatic explanation request has started and the user disables automation
- **THEN** that request is not cancelled by the toggle and may complete under the existing freshness checks
- **AND** navigating afterward to another unexplained file does not start an automatic request

#### Scenario: Manual requests and restoration remain available
- **WHEN** automation is disabled and the user explicitly requests or refreshes an explanation, or returns to a file with valid saved notes
- **THEN** manual requests work normally and saved notes are restored without inference
- **AND** toggling does not discard accepted notes or alter queued manual requests

#### Scenario: Code mode remains manual
- **WHEN** automation is enabled while a code explanation pane is open
- **THEN** ordinary buffer navigation and edits do not trigger automatic code explanation requests
