# Spec Delta

## MODIFIED Requirements

### Requirement: Explanation status and legend

The pane SHALL show request state, explanation count, current/total ordinal when focused, and the D documented / ~ inferred / ? unknown legend in a separate matched header, without taking ownership of the editor's statusline. Focused-context status SHALL identify effective radius and omitted-file count only in the overview. Expanded detail SHALL retain its compact count and navigation header.

#### Scenario: Navigation updates the ordinal
- **WHEN** the second of five explanations is focused or expanded
- **THEN** status identifies 2 / 5; folded groups identify their ordinal range, and appending notes updates the total

#### Scenario: Narrow status area
- **WHEN** the pane cannot fit full state/context/legend text
- **THEN** explanation counts remain prioritized and other text is shortened or abbreviated within the header
- **AND** status never falls back to a content row, including virtual filler, and visible segments retain their semantic colors

#### Scenario: External lualine remains active
- **WHEN** focus, loading, expansion or entry navigation updates Explainr
- **THEN** the user's local/global statusline remains unchanged, with pane state available through vim.b.explainr_status for optional user integration

## ADDED Requirements

### Requirement: Persistent matched explanation header

The pane SHALL reserve its header above content from opening until closure, independent of results, request state, or detail mode. Paired sources lacking winbars SHALL receive temporary blank matching headers. Existing source headers and user edits SHALL be preserved. Owned placeholders SHALL be restored when sources leave pane ownership or the pane closes. No header SHALL be inserted into buffer content.

#### Scenario: Initial loading without source headers
- **WHEN** a code or diff explanation pane opens before explanations are available and paired sources have no winbars
- **THEN** a separate explanation header and matching blank source headers are present immediately
- **AND** the first visible explanation content row aligns with the followed source row, including wrapping, folds, and diff filler

#### Scenario: Results and terminal states do not move the header
- **WHEN** initial loading completes with or without a file-overview note, or the pane enters refresh, failed, stale, or cancelled state
- **THEN** the header remains above content without adding or removing header rows because of that transition
- **AND** clearing results does not remove the matching source placeholders

#### Scenario: Expand and collapse retain the reserved row
- **WHEN** an explanation is expanded, navigated in detail, and collapsed
- **THEN** the header uses the same reserved screen row throughout
- **AND** expansion alone does not move source code and collapse restores the aligned overview

#### Scenario: Preserve existing headers and restore placeholders
- **WHEN** a pane pairs one source with an existing winbar and another without one, then closes or stops owning a source
- **THEN** existing source header text remains unchanged and owned blank placeholders are restored to their original values
- **AND** a user replacement of a temporary blank header is not overwritten during cleanup

### Requirement: State-independent header colors

Header text SHALL use stable semantic colors across request states and detail modes. Visible `Explainr` text SHALL use the theme's information accent by default; counts, spinner, state, separators, descriptions, and navigation hints SHALL be muted. Legend symbols D, ~, and ? SHALL use the same documented, inferred, and unknown highlight groups as explanation items. User highlight overrides SHALL be respected.

#### Scenario: Loading and ready share the same palette
- **WHEN** a header transitions from pending to ready, failed, stale, or cancelled
- **THEN** the title remains accent-colored and other non-marker text remains muted
- **AND** state is distinguished by its text rather than by recoloring the header

#### Scenario: Legend matches explanation markers
- **WHEN** the overview header shows its full or abbreviated intent legend
- **THEN** D uses the documented-item highlight, ~ uses the inferred-item highlight, and ? uses the unknown-item highlight
- **AND** adjacent descriptions and separators remain muted rather than inheriting marker colors

#### Scenario: Expanded header and custom theme
- **WHEN** detail is shown under a theme with customized Explainr semantic highlights
- **THEN** visible title and muted header text use those overrides without changing color when focus or the selected entry changes

#### Scenario: Literal status text
- **WHEN** request state or focused-context text contains a percent sign or multibyte characters
- **THEN** it appears as literal, width-bounded text without introducing header formatting or breaking semantic highlighting
