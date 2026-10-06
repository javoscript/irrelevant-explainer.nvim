# Spec Delta

## MODIFIED Requirements

### Requirement: Free expanded cursor and scrolling

Expanded detail SHALL allow ordinary cursor movement through prose, blank anchored continuation and surrounding context. Leaving the active anchored context SHALL collapse at the destination; ordinary movement SHALL not auto-expand another note. Prose line numbers SHALL not become code line numbers. Explanation-driven viewport scrolling SHALL move paired sources by displayed-row distance, bounded by native buffer limits. Source-driven scrolling SHALL preserve sticky detail visibility rather than require equal explanation viewport movement. Completed explanation-driven scrolls SHALL synchronize the source cursor to the reader's final source-aligned target without adding viewport movement; anchored context SHALL retain its exact source target and prose SHALL use visible-anchor visual-row selection.

#### Scenario: Leave the expanded range
- **WHEN** the cursor moves into surrounding context outside the current anchors
- **THEN** detail collapses and the overview/source cursor maps to that destination rather than jumping back to the summary

#### Scenario: Read a long paragraph
- **WHEN** the cursor moves within prose taller than its source anchor
- **THEN** all prose remains reachable without collapsing or auto-expanding another note
- **AND** prose-driven source cursor synchronization uses anchored display positions rather than paragraph buffer line numbers

#### Scenario: Scroll one line with detail open
- **WHEN** Ctrl-e/Ctrl-y, with or without a count, scrolls the expanded explanation
- **THEN** paired sources follow its actual viewport movement by the corresponding display-row distance, accounting for folds, wraps and filler within native limits
- **AND** this behavior remains available while the card is pinned
- **AND** the source cursor selects the reader's final source-aligned target after scrolling, even when the reader cursor's buffer line and column remain unchanged

#### Scenario: Scroll upward at the expanded reader's upper limit
- **WHEN** Ctrl-y is pressed with no earlier explanation buffer rows, or k is pressed on the expanded summary at the top content-screen edge
- **THEN** paired sources scroll upward by the requested count of native display rows while detail remains selected and available
- **AND** stale leading context does not collapse detail or add a source jump, and source beginning-of-buffer limits are respected
- **AND** source cursor selection uses the final pinned or released reader placement rather than the position before scrolling

#### Scenario: Native expanded viewport action
- **WHEN** zz/zt/zb or another motion changes the expanded viewport
- **THEN** source viewports follow the displayed-row movement without treating Markdown rows as source lines or collapsing solely because a source scrolled
- **AND** sticky placement does not undo user-driven prose scrolling
- **AND** source cursor selection resolves against the final viewport geometry without adding another scroll

#### Scenario: Source scrolloff margins
- **WHEN** expanded scrolling occurs with inherited or window-local source scrolloff, including different margins on the two diff sides
- **THEN** synchronization uses the actual displayed-row movement without adding or losing distance to a pending cursor-margin correction
- **AND** the original global and local scrolloff values are retained, source-driven motion stays native, and repeated redraw or synchronization events do not introduce drift
- **AND** with an eligible reader target, the final source cursor selects that target rather than retaining a temporary margin-normalization position

#### Scenario: Source-driven scroll with detail open
- **WHEN** a keyboard viewport action, cursor motion that scrolls, or mouse wheel moves either source while detail is expanded
- **THEN** the paired sources retain native synchronization and the selected explanation follows its natural position only within sticky viewport bounds
- **AND** pinning does not scroll sources again, steal focus, or apply prose cursor mapping to an inactive explanation cursor

#### Scenario: Counted scrolling relocates the reader cursor into anchored continuation
- **WHEN** a counted Ctrl-e/Ctrl-y scroll forces the reader cursor onto a different real context row inside the active anchors
- **THEN** source cursor selection retains that row's exact source position, including folded or deleted code, after the scroll completes
- **AND** detail remains selected, explanation focus is retained, and source viewports receive no extra movement from selection

#### Scenario: Scroll reaches a native limit without movement
- **WHEN** Ctrl-e/Ctrl-y cannot move the reader or sources because the applicable native limits have been reached
- **THEN** the action does not relocate cursors, replay an earlier scroll, or change the selected detail

#### Scenario: Repeated events after a completed scroll
- **WHEN** cursor, scroll, idle, or redraw events occur after an explanation-driven scroll and final cursor selection have settled
- **THEN** both source cursors and source/reader viewports retain their settled positions without replaying selection or scrolling
- **AND** explicit collapse retains the current source-aligned destination rather than a temporary scrolloff-normalization position

### Requirement: Expanded prose visual-row synchronization

Explanation-driven movement through expanded summary, metadata and prose SHALL synchronize the source cursor by relative content-screen row after viewport synchronization. Targets SHALL be real anchored source lines, resolving wraps, folds and diff filler. Outside the anchors, the nearest visible anchored position SHALL be used. With no visible anchored target, prose mapping SHALL leave the native source cursor unchanged. Focus and source viewport SHALL be preserved. This selection SHALL also follow completed explanation-driven scrolling, including sticky-edge scrolling that changes the source viewport without moving the reader cursor.

#### Scenario: Move inside prose without scrolling
- **WHEN** an expanded explanation references new-side lines 37–58 and the cursor moves from its summary to prose displayed beside new-side line 42 without changing either viewport
- **THEN** the new-side source cursor moves to line 42 instead of remaining at line 37
- **AND** detail stays expanded and the explanation pane retains focus

#### Scenario: Move across wrapped prose segments
- **WHEN** one paragraph buffer line wraps onto several screen rows beside distinct anchored source lines and the cursor moves to a later wrapped segment
- **THEN** the source cursor follows that segment's relative screen row even though the paragraph buffer line number did not change

#### Scenario: Source geometry differs from prose geometry
- **WHEN** the prose cursor's relative screen row corresponds to a wrapped source line or a closed fold containing anchored code
- **THEN** the target is that source buffer line or the fold start, not a line calculated from the Markdown buffer row
- **AND** wrapping and fold state remain unchanged

#### Scenario: Prose beside old-only deleted code
- **WHEN** the prose cursor sits beside an anchored deleted line represented as filler in the new-side source
- **THEN** the old-side source cursor selects the real deleted line and the paired new-side cursor follows the native comparison coordinate
- **AND** focus remains in the explanation pane and the pane remains outside the diff comparison

#### Scenario: Prose extends beyond visible anchor boundaries
- **WHEN** the prose cursor sits above or below the visible anchored extent, including beside unrelated code or past source EOF
- **THEN** the source cursor selects the nearest visible anchored position rather than unrelated code
- **AND** prose remains readable without collapsing and cursor synchronization does not change the source viewport

#### Scenario: Prose beside a gap between anchors
- **WHEN** an expanded explanation has disjoint visible anchor ranges and the prose cursor sits beside the unanchored gap
- **THEN** the source cursor selects the nearest visible anchored display position, choosing the earlier position for equal distances

#### Scenario: Read beyond off-screen anchors
- **WHEN** scrolling a long explanation takes all its anchored code off-screen
- **THEN** paired viewports retain their native displayed-row scrolling and prose mapping does not snap the source viewport or cursor back to an off-screen anchor
- **AND** detail remains expanded

#### Scenario: Expansion and source-driven motion do not trigger prose mapping
- **WHEN** detail is first opened or the user moves in a paired source window while detail is open
- **THEN** the new prose mapping does not relocate the source cursor to the inactive explanation cursor's screen row
- **AND** expansion alone does not move code and existing source-driven viewport synchronization remains available

#### Scenario: Top-pinned prose cursor stays still while code scrolls
- **WHEN** each source line occupies one display row with no filler, the reader cursor is on the fourth content-screen row of a top-pinned card, visible anchors cover source lines 40–100, the source topline is 70 with scrolloff zero, and Ctrl-y moves that topline to 69 while the reader stays at its upper buffer limit
- **THEN** source cursor selection changes from line 73 to line 72 although the reader cursor stays on the same buffer line and column
- **AND** the source topline remains 69 and detail stays expanded

#### Scenario: Final selection crosses a scrolloff boundary
- **WHEN** an explanation-driven scroll leaves prose beside a visible anchored source line inside the source's effective scrolloff margin
- **THEN** the source cursor selects that anchored line while preserving the completed source viewport and original scrolloff settings
- **AND** repeating the action does not leave the cursor at a viewport-middle normalization position

#### Scenario: Post-scroll prose resolves current geometry and bounds
- **WHEN** an explanation-driven scroll places a wrapped prose segment beside a source wrap, fold, deletion filler, or gap between disjoint anchors
- **THEN** selection uses the segment's final content-screen row and the current source geometry with the existing nearest-visible and earlier-row tie rules
- **AND** neither Markdown buffer line numbers nor pre-scroll source positions determine the result

#### Scenario: Entry initialization and geometry changes are not reading scrolls
- **WHEN** n/p/N initializes another detail entry or resizing, folding, or Markdown reflow changes placement without a user reading action
- **THEN** the resulting events do not apply the reader's inactive prose cursor to source code
- **AND** existing entry selection, native source positions, and logical reading-position preservation remain unchanged
