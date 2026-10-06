# Spec Delta

## MODIFIED Requirements

### Requirement: In-pane detail

Enter or K SHALL toggle already-returned detail inside the explanation pane, without a detail popup or another AI call. Expansion SHALL retain the summary position when space permits and preserve dimmed neighboring notes above and below, including when triggered elsewhere in its anchors. Detail SHALL show prose, intent basis, source path and range controls, but no generated context warning or separate Evidence/Anchors sections. Expansion alone SHALL not move code. An ambiguity chooser SHALL select a note without replacing in-pane detail.

#### Scenario: Expand and close detail
- **WHEN** the user opens a truncated note's detail and then closes it without moving or scrolling
- **THEN** the full explanation is readable and the source position and paired alignment are preserved
- **AND** collapse resolves the current source-aligned position rather than restoring a saved summary or invocation row

#### Scenario: Several notes share a display row
- **WHEN** separate valid notes project to one folded or shared diff row
- **THEN** the row indicates combined detail and expansion exposes each note with its original source anchors

#### Scenario: Long detail beside neighboring notes
- **WHEN** expanded prose would cover a following summary
- **THEN** that summary remains visible after the card instead of disappearing, and surrounding summaries are display-only context rather than Markdown paragraphs

#### Scenario: Expansion near the viewport bottom
- **WHEN** the selected summary is too low to expose its first detail line
- **THEN** leading explanation context is trimmed enough to show the first body line without moving source code

#### Scenario: Stable horizontal position
- **WHEN** a note expands or collapses
- **THEN** both modes retain the same gutter and one-space left padding, and no neighboring summary shifts sideways

#### Scenario: Compact detail metadata
- **WHEN** a note expands
- **THEN** its intent-basis metadata follows the summary header without an intervening empty row

#### Scenario: Tab is not expansion
- **WHEN** the user presses Tab in either code or diff explanation mode
- **THEN** Explainr does not use it as an expand/collapse mapping; diff mode can pass it to configured Diffview navigation

#### Scenario: Expansion from a continuation row
- **WHEN** a note's summary is at line 20 and the user presses Enter or K at a summary-free row corresponding to line 31 within its 20–40 anchors
- **THEN** its detail opens beneath its existing summary when visible space permits, using the existing off-screen fallback otherwise
- **AND** opening does not move the source cursor from line 31 or reposition the source viewport

### Requirement: Explanation entry navigation

n SHALL select the next explanation and p/N the previous one in displayed order, with counts clamped at either edge and no wrapping. Destinations SHALL be centered with native zz within viewport limits. Navigation while expanded SHALL retain detail mode and synchronize the selected source anchor and both diff sides. Subsequent explicit collapse SHALL retain the current source-aligned position, not restore either the selected entry's summary or the original expansion entry point.

#### Scenario: Count reaches the end
- **WHEN** a counted next action exceeds the remaining entries
- **THEN** navigation stops on the last entry, and another next action does not change detail or restart inference

#### Scenario: Navigate and collapse
- **WHEN** the user expands the first note, navigates to the second, moves to another source-aligned line inside the second note, and presses Enter, K, q or Esc
- **THEN** the overview and source cursors remain at that current line rather than returning to either summary
- **AND** the current source viewport is preserved within native display limits

#### Scenario: Statusline stability during expanded navigation
- **WHEN** n/p/N selects another expanded entry
- **THEN** detail updates in the same reading buffer without switching through the overview or reattaching it as a new buffer

### Requirement: Focus and range styling

Focused collapsed and expanded notes SHALL emphasize their full anchor ranges and dim surrounding explanation/source text. Expanded tint and rails SHALL cover at least the visible anchored extent and all prose, not merely its text height. Source styling SHALL use muted gutter markers and outside-anchor foreground dimming, preserving anchored syntax, Git backgrounds and existing signs without underlining code. Explicit collapse SHALL derive collapsed focus from the destination row without moving to a summary to retain focus.

#### Scenario: Short detail covers a long range
- **WHEN** an explanation is shorter than its visible anchor span
- **THEN** navigable highlighted continuation extends through the range, including anchored context before a changed-line summary and after neighboring notes

#### Scenario: Focus in a two-sided diff
- **WHEN** a note has old/new anchors, or only an old anchor
- **THEN** both sources dim outside their respective anchors; a side without an anchor dims entirely, while native diff foregrounds and higher-priority Git/diagnostic signs retain precedence

#### Scenario: Theme-derived neutral tint
- **WHEN** focused detail is displayed in a dark or light colorscheme
- **THEN** its subtle neutral surface derives from the theme's CursorLine background, with NormalFloat/normal-text fallbacks and user highlight overrides, while the gutter and left padding remain untinted

#### Scenario: Focus leaves an explanation
- **WHEN** collapsed focus moves to a blank row or another window, or notes become stale or close
- **THEN** temporary focus styling is cleared

#### Scenario: Collapse onto a blank overview row
- **WHEN** explicit collapse lands on a row without a summary even though an explanation's anchors cover that row
- **THEN** expanded styling is removed and collapsed summary focus is cleared without relocating either cursor

#### Scenario: Collapse onto another summary
- **WHEN** explicit collapse lands on a row displaying another explanation's summary
- **THEN** collapsed focus and its ordinal reflect that row's summary rather than the previously expanded explanation
- **AND** the other explanation is not automatically expanded

## ADDED Requirements

### Requirement: Anchor-range expansion selection

Enter/K in the collapsed pane SHALL prioritize summaries at the cursor, including folded groups and overflow entries. Otherwise it SHALL select notes whose original anchors cover the source display position. One candidate SHALL open directly; one local candidate SHALL take precedence over covering overviews. Other multi-candidate cases SHALL prompt selection with summaries and original ranges, local candidates first and overviews last.

#### Scenario: Summary takes precedence over overlapping anchors
- **WHEN** a visible summary row also lies within a file overview and another local explanation's anchors
- **THEN** Enter/K expands the displayed summary directly without offering a chooser

#### Scenario: Relocated summary remains directly selectable
- **WHEN** a summary spills outside its anchors, including into an additional annotation row at EOF
- **THEN** Enter/K on that summary still expands its own explanation rather than selecting by the unrelated presentation line

#### Scenario: Only one covering explanation
- **WHEN** the cursor is on a summary-free row at the first, an interior, or the last line of an explanation's anchors and no other candidate covers it
- **THEN** Enter/K expands that explanation directly

#### Scenario: Whole-file overview with one local explanation
- **WHEN** a summary-free row is covered by a whole-file overview and exactly one local explanation
- **THEN** Enter/K expands the local explanation without prompting
- **AND** the overview remains directly accessible from its summary row

#### Scenario: Overview only
- **WHEN** a summary-free row is covered only by a whole-file overview
- **THEN** Enter/K expands the overview directly

#### Scenario: Multiple local explanations
- **WHEN** a summary-free row is covered by a function note for lines 20–40, a validation note for lines 28–32, and an overview for lines 1–100
- **THEN** Enter/K offers both local explanations and the overview with their summaries and original range labels
- **AND** the overview appears after the local explanations, and selecting any candidate expands only that candidate
- **AND** the narrower validation range is not selected automatically

#### Scenario: Chooser cancellation
- **WHEN** the user cancels ambiguity selection
- **THEN** no detail opens and the pane's cursor and source positions remain unchanged by the expansion action

#### Scenario: Selection becomes obsolete
- **WHEN** the pane closes, its result is replaced, or the diff file changes before a pending chooser selection completes
- **THEN** the obsolete selection does not expand a note in the closed or replacement view

#### Scenario: Actual diff anchors precede summary placement
- **WHEN** a local explanation references anchored context before its relocated changed-line summary, or an old-side deletion shown as filler in the followed new side
- **THEN** Enter/K on a summary-free covered display position includes that explanation among the candidates regardless of the summary's placement or followed side

#### Scenario: Wraps folds and disjoint anchors
- **WHEN** selection originates from a wrapped source line, a folded display stop intersecting an anchor, or a row between disjoint anchor ranges
- **THEN** source display geometry determines candidate coverage, folded summary groups retain their combined expansion, and unanchored gaps do not count as coverage

#### Scenario: No covering explanation
- **WHEN** a row has neither a directly selectable summary nor any covering anchor
- **THEN** Enter/K leaves the pane collapsed without a chooser or an additional inference request

### Requirement: Explicit collapse at current position

Enter/K and Esc/q in detail SHALL collapse at the current source-aligned position, not a saved summary or invocation row. Mapped context SHALL retain its position. After cursor movement, prose SHALL use visual-row geometry bounded to visible anchors, with nearest-target and earlier-row tie rules. With untouched initialization or no visible anchor, collapse SHALL retain the native source position. Focus and source views SHALL be preserved within native geometry limits.

#### Scenario: Collapse without moving after initialization
- **WHEN** detail opens from source line 31 beneath a summary at line 20, or n/p initializes a new detail entry, and the user explicitly collapses without moving or scrolling
- **THEN** the current source position is retained rather than remapped from the newly placed detail header
- **AND** initialization events do not cause a source cursor or viewport jump

#### Scenario: Collapse after moving through continuation
- **WHEN** a note covering lines 20–40 is opened at line 25, the expanded cursor moves to source-aligned continuation at line 31, and Enter/K or Esc/q is pressed
- **THEN** overview and source cursors remain at line 31, not line 20 or line 25

#### Scenario: Collapse from prose
- **WHEN** the current prose cursor is visually aligned with anchored source line 31 although its Markdown buffer line number differs
- **THEN** explicit collapse selects overview/source line 31 rather than the Markdown row number, stale source cursor, summary, or invocation row

#### Scenario: Prose outside visible anchored positions
- **WHEN** the prose cursor is beside unrelated code, an unanchored gap, or empty EOF space and visible anchored targets remain
- **THEN** collapse selects the nearest visible anchored position, choosing the earlier position for equal distances, without snapping to an off-screen summary

#### Scenario: Anchors have scrolled off-screen
- **WHEN** all anchors have left the source viewport while the user reads long prose
- **THEN** explicit collapse preserves the current native source position and viewport instead of returning to an off-screen anchor

#### Scenario: Collapse on folded or deleted content
- **WHEN** the current source-aligned position is a closed fold or an old-side deleted line represented as new-side filler
- **THEN** collapse retains the corresponding fold start or real old-side line and synchronized native diff position without unfolding code or treating filler as a new-side line

#### Scenario: Collapse preserves current view and focus
- **WHEN** explicit collapse follows cursor movement or paired scrolling
- **THEN** source viewports are not restored to their expansion-time values, the explanation pane retains focus, and repeated synchronization events do not replay a jump
- **AND** removing prose can change the explanation layout, but does not force the overview cursor onto a summary

#### Scenario: Expanded controls do not reselect overlaps
- **WHEN** Enter/K is pressed in detail at a position covered by multiple explanations
- **THEN** it collapses at the current source-aligned position without opening an ambiguity chooser or expanding another explanation
