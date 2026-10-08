# Spec Delta

## ADDED Requirements

### Requirement: Review screen-row scrolling

Review Ctrl-e/Ctrl-y SHALL scroll by one visible screen row per press, with counts using the same unit, including wrapped continuations and paragraph boundaries, bounded by native buffer limits. Review SHALL preserve source and global scrolling settings and restore the pane's prior scrolling setting on return to File. Reopening an unchanged narrative SHALL retain its wrapped reading position.

#### Scenario: Scroll within a wrapped paragraph
- **WHEN** a Review paragraph occupies at least four screen rows and the user presses Ctrl-e without a count away from a buffer limit
- **THEN** the text moves upward by exactly one screen row rather than skipping the whole paragraph
- **AND** Ctrl-y moves the text downward by exactly one screen row
- **AND** source cursors and viewports remain unchanged

#### Scenario: Counted scrolling crosses a paragraph boundary
- **WHEN** the top visible row is the penultimate displayed row of a wrapped paragraph followed by a blank line and another paragraph, and the user presses 3Ctrl-e with sufficient content below
- **THEN** the viewport advances by three screen rows to the next paragraph's first displayed row
- **AND** 3Ctrl-y returns to the original displayed row when sufficient content exists above

#### Scenario: Native limits remain authoritative
- **WHEN** Ctrl-y is pressed at the beginning of Review, or a scrolling count exceeds the remaining native scroll range
- **THEN** scrolling stops at the native limit without moving a source window, wrapping around, or adding narrative text

#### Scenario: Review does not leak its scrolling setting
- **WHEN** Review is entered from a File pane with its scrolling setting disabled or already enabled, then the user returns to File
- **THEN** Review provides screen-row scrolling in either case and File regains its prior setting
- **AND** global, source, and explorer scrolling settings are unchanged

#### Scenario: Reopen a clipped wrapped paragraph
- **WHEN** the user scrolls until the first visible Review row is a wrapped continuation, switches to File, and reopens the unchanged narrative
- **THEN** Review returns to the same wrapped continuation and cursor position rather than the paragraph's first row
- **AND** subsequent Ctrl-e/Ctrl-y presses still use screen rows

#### Scenario: Retained narrative is busy
- **WHEN** a retained Review narrative is loading or checking and the user scrolls through wrapped prose
- **THEN** Ctrl-e/Ctrl-y use the same screen-row unit as in idle Review
- **AND** loading and header updates do not reset the reading position or rewrite narrative text
