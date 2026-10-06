# Spec Delta

## ADDED Requirements

### Requirement: Automatic-mode header indicator

Diff explanation panes SHALL show `Auto` in their existing winbar when automatic explanations are enabled, in both overview and expanded detail, independent of request state. Disabled mode and code panes SHALL omit it. The indicator SHALL use the existing muted header styling and appear alongside counts before lower-priority descriptions and hints; width clipping SHALL preserve counts and `Auto` whenever both fit.

#### Scenario: Enabled overview and detail
- **WHEN** automatic explanations are enabled and a diff pane is opened or expanded
- **THEN** its header displays `Auto` alongside its count and existing request or detail state
- **AND** the indicator remains present for pending, ready, unexplained, failed, stale, and cancelled states, not only during automatic requests

#### Scenario: Disabled or code pane
- **WHEN** automatic explanations are disabled, or the pane explains ordinary code regardless of the global setting
- **THEN** its header has no `Auto` indicator

#### Scenario: Narrow header
- **WHEN** an enabled diff pane is too narrow for its full header but wide enough for its count and `Auto`
- **THEN** both count and `Auto` remain visible while lower-priority descriptions, legend text, or navigation hints are abbreviated or omitted
- **AND** no header text is inserted into explanation content rows

### Requirement: Nondisruptive live mode indication

Toggling automation SHALL immediately update all open diff-pane headers, including background tabs and expanded detail. Header updates SHALL preserve request state, accepted notes, active jobs, selected explanation, detail buffer, cursors, viewports, and focus. The editor's local/global statusline and the existing request-state meaning of `vim.b.explainr_status` SHALL remain unchanged.

#### Scenario: Toggle while reading expanded detail
- **WHEN** the user toggles automation with a diff explanation expanded and its prose scrolled
- **THEN** `Auto` appears or disappears immediately without collapsing detail, replacing its buffer, moving the cursor or viewport, changing the selected note, or starting inference

#### Scenario: Multiple open tabs
- **WHEN** the user toggles automation while multiple tabs contain open diff explanation panes
- **THEN** every owned diff-pane header reflects the new setting without switching tabs or windows
- **AND** any code-pane header remains without an automatic-mode indicator

#### Scenario: Existing status integrations
- **WHEN** automation is toggled with a user statusline or lualine active
- **THEN** the editor statusline remains unchanged and `vim.b.explainr_status` continues to expose the existing request-state string rather than an indicator-decorated replacement
