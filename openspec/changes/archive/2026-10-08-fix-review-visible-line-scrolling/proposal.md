# Proposal

## Why

Scrolling the Review general-summary pane with Ctrl-e/Ctrl-y can jump an entire wrapped paragraph instead of one visible line. Exploration reproduced eight-screen-row jumps with Neovim's default smoothscroll setting disabled, while enabling it made the same inputs move exactly one screen row.

## What Changes

- Make Review Ctrl-e/Ctrl-y scrolling use visible screen rows, including wrapped continuations and counted inputs, within native buffer limits.
- Scope the scrolling setting to Review and restore the pane's previous setting when returning to File mode; leave source and global settings unchanged.
- Preserve the exact wrapped reading position when leaving and reopening an unchanged narrative.
- Add focused regression coverage and document Review's scrolling unit.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `aligned-explanation-ui`: Define screen-row Ctrl-e/Ctrl-y scrolling in Review and preserve its isolation and wrapped reading position across mode switches.

## Impact

- `lua/explainr/ui.lua`: Review window-option save, apply, and restore lifecycle.
- `tests/ui_test.lua`: Review scrolling and mode-switch regression coverage.
- `README.md` and `doc/explainr.txt`: Review scrolling documentation.
- No new dependencies, mappings, configuration fields, or public API changes. File overview, expanded detail, source scrolling, and generation behavior remain outside scope.
