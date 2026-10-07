# Spec Delta

## MODIFIED Requirements

### Requirement: Free expanded cursor and scrolling

Expanded detail SHALL allow ordinary cursor movement through prose, blank anchored continuation and surrounding context. Leaving the active anchored context SHALL collapse at the destination; ordinary movement SHALL not auto-expand another note. Prose line numbers SHALL not become code line numbers. Explanation-driven viewport scrolling SHALL move paired sources by displayed-row distance, bounded by native buffer limits. Source-driven scrolling SHALL preserve sticky detail visibility rather than require equal explanation viewport movement. Completed explanation-driven scrolls SHALL synchronize the source cursor to the reader's final source-aligned target without adding viewport movement; anchored context SHALL retain its exact source target and prose SHALL use visible-anchor visual-row selection. Expanded Ctrl-e/Ctrl-y actions SHALL settle without displaying an intermediate scroll that is subsequently undone by card-placement reconciliation. A further reader Ctrl-y blocked solely by a fitting card's bottom placement limit SHALL enter the source-backed display row immediately above the card, collapsing only when that destination is outside its active anchors.

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
- **AND** this behavior remains available while the card is pinned, with the bottom placement escape defined below taking precedence when applicable
- **AND** the source cursor selects the reader's final source-aligned target after scrolling, even when the reader cursor's buffer line and column remain unchanged

#### Scenario: Scroll upward at the expanded reader's upper limit
- **WHEN** Ctrl-y is pressed with no earlier explanation buffer rows, or k is pressed on the expanded summary at the top content-screen edge
- **THEN** paired sources scroll upward by the requested count of native display rows while detail remains selected and available, except when a subsequent Ctrl-y step qualifies for the bottom placement escape
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
- **AND** source-driven scrolling does not trigger the reader's bottom placement escape

#### Scenario: Counted scrolling relocates the reader cursor into anchored continuation
- **WHEN** a counted Ctrl-e/Ctrl-y scroll forces the reader cursor onto a different real context row inside the active anchors
- **THEN** source cursor selection retains that row's exact source position, including folded or deleted code, after the scroll completes
- **AND** detail remains selected, explanation focus is retained, and source viewports receive no extra movement from selection

#### Scenario: Scroll reaches a native limit without movement
- **WHEN** Ctrl-e/Ctrl-y cannot move the reader or sources because the applicable native limits have been reached, rather than solely because a fitting card has reached its bottom placement limit
- **THEN** the action does not relocate cursors, replay an earlier scroll, or change the selected detail
- **AND** the action does not flash a temporary displaced card or invent a context destination beyond the file boundary

#### Scenario: Repeated events after a completed scroll
- **WHEN** cursor, scroll, idle, or redraw events occur after an explanation-driven scroll and final cursor selection have settled
- **THEN** both source cursors and source/reader viewports retain their settled positions without replaying selection or scrolling
- **AND** explicit collapse retains the current source-aligned destination rather than a temporary scrolloff-normalization position

#### Scenario: Ctrl-e at the top edge does not flash a correction
- **WHEN** a fitting expanded card is at the top content edge and Ctrl-e is pressed once or repeatedly
- **THEN** the reader does not display the card scrolled above the edge and then restored by a later placement correction
- **AND** any valid paired scrolling and final source selection happen once, while a genuine native no-op leaves the settled state unchanged
- **AND** the action does not collapse detail solely because the card touches the top edge

#### Scenario: Reach the bottom placement edge without leaving detail
- **WHEN** reader Ctrl-y moves a fitting expanded card to the last position where its full content fits
- **THEN** detail remains expanded and the action does not move the cursor into outside context merely because the edge was reached

#### Scenario: Further Ctrl-y escapes a placement-blocked card
- **WHEN** the cursor is within a fitting card at its bottom placement limit, the next reader Ctrl-y step would be blocked solely by keeping the card fully visible, and the source-backed display row immediately above the card is outside the active anchors
- **THEN** the cursor enters that context row and detail collapses at its corresponding source destination
- **AND** the explanation pane retains focus, both diff sources remain synchronized, and no neighboring note is automatically expanded
- **AND** collapse preserves the current source viewport within native visibility limits rather than restoring the summary or expansion-time view

#### Scenario: Preceding context is still anchored
- **WHEN** the bottom placement escape from within the card targets a source-backed row inside the active anchors
- **THEN** the cursor selects that exact context destination and detail remains expanded
- **AND** the action does not skip over anchored rows to force a collapse
- **AND** subsequent context navigation does not repeatedly force the cursor back to that escape row

#### Scenario: Count crosses the placement boundary
- **WHEN** a counted reader Ctrl-y reaches the bottom placement edge with additional steps remaining
- **THEN** preceding steps scroll normally and the first placement-blocked step performs the context escape exactly once
- **AND** that command stops at the escape destination without applying leftover steps or replaying the original count after collapse
- **AND** a count ending exactly at the placement edge retains expanded detail without escaping

#### Scenario: Escape resolves wrapped folded and deleted context
- **WHEN** the preceding source-backed display row is a wrapped segment, a closed fold, or old-side deleted code represented by filler on the followed side
- **THEN** the escape resolves that row's actual source owner and line, retaining fold state and native diff alignment
- **AND** the destination is not calculated by subtracting one from a Markdown buffer line or by treating filler as new-side code

#### Scenario: Viewport-filling and long prose remain readable
- **WHEN** a card is taller than the content viewport, or a viewport-filling card has no preceding source-backed display row available
- **THEN** the bottom placement escape does not replace ordinary prose scrolling or fabricate a context row
- **AND** all prose remains reachable with the existing paired-scroll and anchor-bounded selection behavior

#### Scenario: Events after a boundary escape are idempotent
- **WHEN** scroll, cursor, idle, or redraw events follow a completed context escape
- **THEN** the destination, focus, detail state, and paired viewports remain unchanged
- **AND** no stale expanded placement reopens detail, restores the old cursor, or applies the escape again
