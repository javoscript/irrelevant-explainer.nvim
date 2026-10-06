# Spec Delta

## MODIFIED Requirements

### Requirement: Free expanded cursor and scrolling

Expanded detail SHALL allow ordinary cursor movement through prose, blank anchored continuation and surrounding context. Leaving the active anchored context SHALL collapse at the destination; ordinary movement SHALL not auto-expand another note. Prose line numbers SHALL not become code line numbers. Viewport scrolling SHALL move paired sources by displayed-row distance, bounded by native buffer limits.

#### Scenario: Leave the expanded range
- **WHEN** the cursor moves into surrounding context outside the current anchors
- **THEN** detail collapses and the overview/source cursor maps to that destination rather than jumping back to the summary

#### Scenario: Read a long paragraph
- **WHEN** the cursor moves within prose taller than its source anchor
- **THEN** all prose remains reachable without collapsing or auto-expanding another note
- **AND** prose-driven source cursor synchronization uses anchored display positions rather than paragraph buffer line numbers

#### Scenario: Scroll one line with detail open
- **WHEN** Ctrl-e/Ctrl-y, with or without a count, scrolls the explanation or either diff source
- **THEN** all paired viewports scroll by the corresponding display-row distance, accounting for folds, wraps and filler

#### Scenario: Native expanded viewport action
- **WHEN** zz/zt/zb or another motion changes the expanded viewport
- **THEN** source viewports follow the displayed-row movement without treating Markdown rows as source lines or collapsing solely because a source scrolled

## ADDED Requirements

### Requirement: Expanded prose visual-row synchronization

Explanation-driven movement through expanded summary, metadata and prose SHALL synchronize the source cursor by relative content-screen row after viewport synchronization. Targets SHALL be real anchored source lines, resolving wraps, folds and diff filler. Outside the anchors, the nearest visible anchored position SHALL be used. With no visible anchored target, prose mapping SHALL leave the native source cursor unchanged. Focus and source viewport SHALL be preserved.

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
