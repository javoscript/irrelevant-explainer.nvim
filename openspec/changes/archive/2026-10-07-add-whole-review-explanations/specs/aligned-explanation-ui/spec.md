# Spec Delta

## ADDED Requirements

### Requirement: Comparison narrative reading mode

Diff readers SHALL offer Review and File modes in the same right-hand pane. Review SHALL display the whole-change narrative as read-only, independently scrollable Markdown, without source alignment, source focus decorations, or a floating window. File SHALL retain aligned overview and expanded detail behavior. Review SHALL use the explainr filetype, optional syntax highlighting, visible Markdown markers, and native wrapping without a renderer dependency.

#### Scenario: Read across files without displacing code
- **WHEN** Review is selected after a review response is accepted
- **THEN** its title, narrative sections, intent labels, and file references appear in the existing pane
- **AND** no narrative rows are inserted above the aligned File notes or into source buffers

#### Scenario: Independent narrative scrolling
- **WHEN** the user moves or scrolls through a long Review narrative, including wrapped paragraphs
- **THEN** all narrative content remains reachable without moving either source cursor or viewport
- **AND** source scrolling does not scroll or collapse Review; native old/new diff synchronization remains active

#### Scenario: Enter Review from expanded file detail
- **WHEN** the user switches from expanded File detail to Review
- **THEN** file-note dimming, anchor rails, and source-linked detail motion are removed from the active reader
- **AND** returning to File restores aligned overview without changing source wrapping, folds, gutters, or diff membership

#### Scenario: No Markdown parser
- **WHEN** optional syntax parsers are unavailable
- **THEN** Review remains readable with literal Markdown markers and no automatic parser installation or renderer invocation

### Requirement: Display-only narrative access

Explainr SHALL expose `:ExplainrReview`, `require("explainr").review()`, and a pane-local remappable `<Plug>(ExplainrReview)` action to select Review without inference. They SHALL show a retained narrative or an explicit pending, empty, failed, or stale state for the current comparison. No global default mapping SHALL be installed. Reopening the same narrative SHALL preserve its reading position.

#### Scenario: Return to the narrative
- **WHEN** the user scrolls Review, reads two files, and invokes ExplainrReview
- **THEN** the same narrative returns at its saved reading position without another request or selecting another Diffview file

#### Scenario: Narrative has not been generated
- **WHEN** ExplainrReview is invoked in a supported comparison without a retained or pending review
- **THEN** the reader shows an empty Review state directing the user to ExplainrDiff review
- **AND** opening that state does not generate explanations, including with Auto enabled

#### Scenario: No supported comparison
- **WHEN** display-only Review access is invoked outside a supported Diffview comparison
- **THEN** it reports the missing comparison without inference or changing a code explanation reader

#### Scenario: Review generation begins
- **WHEN** ExplainrDiff review is explicitly requested
- **THEN** the pane selects Review pending mode without stealing focus and preserves any still-fresh prior narrative while waiting
- **AND** a replacement narrative starts at its beginning only if Review is still selected when installed

### Requirement: Narrative file navigation and return

Enter on a rendered Review file reference SHALL select that exact comparison entry and show File mode after its panes become coherent, without inference for valid returned notes. Arbitrary narrative text SHALL not become an executable link. Esc in Review SHALL return to the current File overview; q SHALL close the reader. Actual Diffview file changes SHALL select File mode, while retaining the narrative reading position.

#### Scenario: Follow a renamed or deleted file
- **WHEN** Enter activates a validated reference to a renamed or deleted manifest entry
- **THEN** Diffview selects that entry using its comparison identity and File displays the correct available old/new notes rather than opening a guessed working-tree path

#### Scenario: Reference has no textual annotations
- **WHEN** a Review reference selects a binary or both-empty entry
- **THEN** the reader shows its no-text-annotations state without fabricating ranges or invoking a file explanation

#### Scenario: Enter on ordinary prose
- **WHEN** Enter is pressed on narrative text that is not a rendered file reference
- **THEN** no file navigation, command execution, note expansion, or AI request occurs

#### Scenario: Return and close have distinct controls
- **WHEN** Esc is pressed in Review
- **THEN** the pane returns to File overview without cancelling pending work
- **AND** q or ExplainrClose instead closes the reader and cancels owned pending work

#### Scenario: Navigate through Diffview bindings
- **WHEN** a configured next/previous-file action or explorer selection actually changes the file while Review is displayed
- **THEN** the pane shows that file's notes or pending/empty state, without cancelling existing generation
- **AND** a disabled mapping or a no-op navigation at a list boundary does not reset Review

### Requirement: Nondisruptive background completion

Background completion SHALL update retained results and request status without stealing focus, changing the selected file or reader mode, or resetting unrelated expanded detail or narrative reading position. A fresh replacement for a currently expanded file batch SHALL become visible after detail exits. Stale content SHALL be cleared or identified rather than preserved as current solely to avoid disruption.

#### Scenario: Hidden file completes
- **WHEN** A completes while the user reads expanded notes for B
- **THEN** B's detail buffer, selection, cursor, viewport, and source positions remain unchanged
- **AND** only A's retained result and background request status change

#### Scenario: Review finishes after the user leaves Review
- **WHEN** a review completes after the user navigates into File mode
- **THEN** the narrative becomes available without switching the pane back to Review
- **AND** an existing expanded file note remains open until the user exits it, unless its content became stale

#### Scenario: Off-screen failure
- **WHEN** generation for hidden A fails while B has valid notes
- **THEN** the error identifies A and does not mark B's accepted notes as a failed result

### Requirement: Review and background status

The diff-pane header SHALL identify the active Review/File mode and distinguish selected-target pending work from requests running elsewhere and queued work. Review SHALL show comparison/request state instead of file-note ordinals and retain Auto when enabled. No progress percentage or per-file completion progress SHALL be invented before a whole-review response validates. Status updates SHALL not alter the editor statusline or reset reading state.

#### Scenario: Other file is still generating
- **WHEN** B is selected while A runs and B is queued
- **THEN** the header distinguishes B's queued state from background generation rather than displaying A's notes or indicating that B is already generating

#### Scenario: Whole-review request pending
- **WHEN** one review invocation is running
- **THEN** Review reports pending comparison work and its target file count without claiming individual files have completed

#### Scenario: Narrow Review header
- **WHEN** the Review pane cannot fit its full header
- **THEN** it prioritizes active mode and request state, plus Auto when those fit, over hints and descriptions
- **AND** File retains its existing count/Auto priorities and neither mode inserts a header into buffer content

## MODIFIED Requirements

### Requirement: Aligned annotation pane

The plugin SHALL open a read-only explanation pane at the far right of the tab, outside both diff sources. In code mode and diff File mode, the collapsed pane SHALL preserve one logical row per followed source line, including blank rows, with additional rows allowed for exhausted overlaps. Summaries SHALL be visibly truncated rather than wrapped; original anchor labels SHALL remain attached to their notes. Diff Review mode SHALL instead use the independent narrative reading contract.

#### Scenario: Sparse notes
- **WHEN** notes target source lines 40, 43, and 46
- **THEN** the pane leaves intervening rows blank and does not compress the notes into a continuous list

#### Scenario: Narrow pane
- **WHEN** a summary is wider than the explanation pane
- **THEN** the summary is truncated with an expansion indicator and subsequent notes retain their row positions

#### Scenario: Request from the old diff side
- **WHEN** explanation is requested from the left old-side window in Diffview
- **THEN** the pane opens beyond the new-side window, not between old and new

### Requirement: Scoped animated loading

Active and queued request ranges matching the displayed code or diff File target SHALL receive a steady faint full-width tint with an animated cursor-width gutter rail and a smooth cascading glow. Off-screen requests SHALL use status without misplaced range decorations. A pending Review SHALL animate its own visible narrative viewport, including an empty narrative, independently of source ranges. Animation SHALL preserve accepted text and source diff highlights, update only visible decorations, and pause repainting on the focused logical cursor row. It SHALL stop on completion, failure, cancellation, staleness or closure and not modify global cursor or terminal redraw options.

#### Scenario: Narrative generation is pending
- **WHEN** Review is visible while a whole-review request is pending
- **THEN** the narrative body shows the loading tint and rail without rewriting retained prose or changing its cursor, wrapping or viewport
- **AND** the empty state also animates, leaving source windows unchanged
- **AND** leaving Review clears its decorations; returning resumes them only if the review is still pending

#### Scenario: Two hunks are waiting
- **WHEN** one hunk is being explained and another is queued for the displayed file
- **THEN** both matching explanation ranges animate, including wrapped/folded rows and deletion/EOF filler, while accepted notes remain readable

#### Scenario: Snapshot not yet collected
- **WHEN** a diff request begins before exact anchors are available
- **THEN** a matching displayed file request previews the whole source and a hunk request previews its cursor/native changed region until collected anchors replace the provisional range
- **AND** navigation to a different file removes those provisional decorations rather than transferring them

#### Scenario: Cursor is on a loading row
- **WHEN** notes have focus during loading
- **THEN** the cursor row and status spinner stop repainting while other requested rails continue; the plugin leaves guicursor and termsync unchanged and documents synchronized terminal output as a flicker dependency

### Requirement: Lifecycle and status

The UI SHALL identify pending, failed, and stale explanation states separately from valid notes in code, diff File, and Review modes. Closing the source/view or explicitly closing explanation SHALL close its pane, detail and narrative, cancel all owned pending work, and remove its event handlers without changing unrelated windows. Ordinary file navigation within the same diff comparison SHALL preserve owned requests and reset only file-specific display state.

#### Scenario: Failure after previous success
- **WHEN** a refresh fails while an older explanation exists
- **THEN** the pane identifies the failure and does not present older notes or a narrative as a successful fresh result

#### Scenario: Source closes
- **WHEN** the paired source window or Diffview view closes
- **THEN** its explanation pane, in-pane detail, narrative buffer, pending requests, timers and handlers are cleaned up
- **AND** late callbacks cannot reopen the reader or install cancelled results

#### Scenario: Explicit reader close
- **WHEN** the user presses q/Esc in the code or diff File collapsed overview, q in Review, or invokes ExplainrClose
- **THEN** the owned reader is closed and pending work is cancelled without closing the source; q/Esc in expanded detail instead collapses the current entry and Esc in Review returns to File

### Requirement: Explanation status and legend

Code and diff File mode SHALL show request state, explanation count, current/total ordinal when focused, and the D documented / ~ inferred / ? unknown legend in a separate matched header, without taking ownership of the editor's statusline. Focused-context status SHALL identify effective radius and omitted-file count only in the File overview. Expanded detail SHALL retain its compact count/navigation header. Review SHALL use comparison status rather than file-note counts.

#### Scenario: Navigation updates the ordinal
- **WHEN** the second of five explanations is focused or expanded
- **THEN** status identifies 2 / 5; folded groups identify their ordinal range, and appending notes updates the total

#### Scenario: Narrow status area
- **WHEN** the code or diff File pane cannot fit full state/context/legend text
- **THEN** explanation counts remain prioritized and other text is shortened or abbreviated within the header
- **AND** status never falls back to a content row, including virtual filler, and visible segments retain their semantic colors

#### Scenario: External lualine remains active
- **WHEN** focus, loading, expansion, Review/File switching or entry navigation updates Explainr
- **THEN** the user's local/global statusline remains unchanged, with pane state available through vim.b.explainr_status for optional user integration
