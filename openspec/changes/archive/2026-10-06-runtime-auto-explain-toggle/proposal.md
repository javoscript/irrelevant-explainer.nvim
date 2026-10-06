# Proposal

## Why

Users can configure automatic Diffview explanations at setup but have no supported runtime control to pause or resume them while reading. A keybind-friendly toggle and visible mode indicator let users control external-agent usage without reinitializing Explainr.

## What Changes

- Add `:ExplainrToggleAutoExplain` and `require("explainr").toggle_auto_explain()`, returning the new boolean and notifying whether automatic explanations are enabled or disabled.
- Keep `diff.auto_explain` as the setup value and process-wide runtime setting, defaulting to false. Do not install a global keymap; document a user-defined mapping.
- Enabling applies to subsequent Diffview navigation only; it does not immediately explain the current file or open a pane. Disabling prevents future automatic requests without cancelling started work, discarding notes, or changing manual requests and saved-note restoration.
- Display a compact `Auto` indicator in existing diff-pane winbars whenever automatic explanations are enabled, in overview and expanded detail. Update open panes immediately across tabs without disturbing the reader or editor statusline.
- Document the command, Lua API, indicator, and lifecycle semantics; cover them with offline tests and rendered-header checks.

## Capabilities

### New Capabilities

None; this extends existing diff inference and explanation UI capabilities.

### Modified Capabilities

- `diff-explanation`: Add runtime control of opt-in navigation inference while preserving its existing navigation, restoration, and no-retry rules.
- `aligned-explanation-ui`: Add a live automatic-mode indicator to overview and detail status headers without replacing request state or taking ownership of the editor statusline.

## Impact

- Public API and commands in `lua/explainr/init.lua`; diff navigation and session-wide header updates in `lua/explainr/session.lua`; overview/detail winbar rendering in `lua/explainr/ui.lua`.
- Existing setup, Diffview navigation, session, and UI tests, plus the actual-screen fixtures in `tests/visual.lua` and `tests/render.py` as needed.
- README and help documentation for configuration, commands, mappings, and reader status.
- No new dependencies, persisted preferences, code-mode automation, per-tab settings, default keybindings, or breaking changes.
