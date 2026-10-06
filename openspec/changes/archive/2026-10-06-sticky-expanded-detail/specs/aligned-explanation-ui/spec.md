# Spec Delta

## MODIFIED Requirements

### Requirement: Free expanded cursor and scrolling

Expanded detail SHALL allow ordinary cursor movement through prose, blank anchored continuation and surrounding context. Leaving the active anchored context SHALL collapse at the destination; ordinary movement SHALL not auto-expand another note. Prose line numbers SHALL not become code line numbers. Explanation-driven viewport scrolling SHALL move paired sources by displayed-row distance, bounded by native buffer limits. Source-driven scrolling SHALL preserve sticky detail visibility rather than require equal explanation viewport movement.

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

#### Scenario: Native expanded viewport action
- **WHEN** zz/zt/zb or another motion changes the expanded viewport
- **THEN** source viewports follow the displayed-row movement without treating Markdown rows as source lines or collapsing solely because a source scrolled
- **AND** sticky placement does not undo user-driven prose scrolling

#### Scenario: Source scrolloff margins
- **WHEN** expanded scrolling occurs with inherited or window-local source scrolloff, including different margins on the two diff sides
- **THEN** synchronization uses the actual displayed-row movement without adding or losing distance to a pending cursor-margin correction
- **AND** the original global and local scrolloff values are retained, source-driven motion stays native, and repeated redraw or synchronization events do not introduce drift

#### Scenario: Source-driven scroll with detail open
- **WHEN** a keyboard viewport action, cursor motion that scrolls, or mouse wheel moves either source while detail is expanded
- **THEN** the paired sources retain native synchronization and the selected explanation follows its natural position only within sticky viewport bounds
- **AND** pinning does not scroll sources again, steal focus, or apply prose cursor mapping to an inactive explanation cursor

## ADDED Requirements

### Requirement: Sticky expanded detail placement

Code-driven scrolling SHALL keep expanded detail inside the explanation content viewport, aligned with its selected summary when space permits and clamped at the top or bottom otherwise. A fitting card SHALL remain fully visible; a taller card SHALL retain a visible reading area. Placement SHALL exclude the persistent header and preserve selection and prose reading position, including when all source anchors leave the screen.

#### Scenario: Natural alignment before an edge
- **WHEN** code scrolls while the expanded card still fits at its summary's natural display position
- **THEN** the card follows that position instead of remaining permanently fixed at the top

#### Scenario: Pin at the top
- **WHEN** scrolling code down would move a short expanded card partly or entirely above the explanation content viewport
- **THEN** the whole card remains visible with its top clamped immediately below the persistent header
- **AND** its original range labels and selected identity remain unchanged

#### Scenario: Pin at the bottom
- **WHEN** scrolling code up would move a short expanded card partly or entirely below the explanation content viewport
- **THEN** the whole card remains visible with its bottom clamped to the content viewport's last row
- **AND** no source viewport adjustment is added to make the card fit

#### Scenario: Return from either edge
- **WHEN** code scrolls back until the expanded card's natural position fits inside the viewport again
- **THEN** the card resumes that aligned position without changing the selected explanation or resetting the reading position

#### Scenario: All source anchors leave the screen
- **WHEN** code scrolls beyond all anchors of the selected explanation
- **THEN** its expanded reading area remains available until explicit collapse, explanation navigation, movement into outside context, or normal pane/result cleanup
- **AND** source-driven scrolling alone neither collapses detail nor expands another explanation

#### Scenario: Detail is taller than the viewport
- **WHEN** an expanded explanation's summary, metadata and prose exceed the available content height and code scrolls
- **THEN** a reading area remains inside the explanation pane and the current prose reading position is preserved
- **AND** the user can still reach every paragraph by scrolling the explanation, with code following that reading scroll
- **AND** visibility of every paragraph or a separately sticky summary is not required

#### Scenario: Preserve a wrapped reading position
- **WHEN** the user is reading a later wrapped segment of a paragraph and then scrolls code enough to pin or unpin the explanation
- **THEN** placement retains that logical reading position rather than jumping to the paragraph start or first detail line

#### Scenario: Neighboring context and range extent
- **WHEN** code scrolls with a short explanation covering a long source range and neighboring notes are available
- **THEN** sticky bounds are based on the explanation card rather than its blank anchored continuation
- **AND** dimmed neighboring context remains available where space permits without displacing the active reading area off-screen or hiding neighboring notes permanently

#### Scenario: Geometry changes while expanded
- **WHEN** a resize, width-dependent wrap, source fold change, or diff-filler update changes display geometry
- **THEN** placement is recomputed within the new content viewport without changing source options, selected identity, or the logical prose reading position
- **AND** repeated synchronization events do not oscillate between aligned and pinned placement

#### Scenario: Existing navigation and cleanup
- **WHEN** the user selects another explanation with n/p/N, collapses detail, changes the diff file, replaces results, or closes a paired window
- **THEN** sticky state is reset or removed through that action's existing lifecycle without leaving stale context, decorations, or viewport synchronization
- **AND** explicit collapse uses the current source-aligned destination rather than replaying a pinning position or expansion-time source view
